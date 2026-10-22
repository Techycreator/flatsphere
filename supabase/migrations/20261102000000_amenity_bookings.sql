create extension if not exists btree_gist;

create table amenities (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 100),
  rules text not null default '',
  fee integer not null default 0 check (fee >= 0),
  requires_approval boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (association_id, name)
);
alter table amenities enable row level security;
create policy amenities_read on amenities for select using (is_member(association_id));
create policy amenities_manage on amenities for all using (
  has_role(association_id,array['president','secretary']::app_role[])
) with check (has_role(association_id,array['president','secretary']::app_role[]));

insert into amenities (association_id,name,rules,fee) select a.id,x.name,x.rules,x.fee
from associations a cross join (values
  ('Party hall','Reservation required; restore the venue after use.',3000),
  ('Terrace','No amplified sound after 10 PM.',1000),
  ('Guest room','Maximum two consecutive nights.',1500),
  ('BBQ area','Clean the grill and dispose of charcoal safely.',1000),
  ('Club house','Association rules apply; booking approval required.',2000)
) as x(name,rules,fee)
on conflict (association_id,name) do nothing;

insert into workflow_types (association_id,code,version,name,description,requires_mom)
select id,'W25',1,'Amenity booking','Approve flat reservations for shared amenities',false from associations
on conflict (association_id,code,version) do nothing;
insert into workflow_type_steps (workflow_type_id,step_no,label,role_required,action_type)
select id,1,'Secretary approval','secretary','approval' from workflow_types where code='W25' and version=1
on conflict (workflow_type_id,step_no) do nothing;
insert into workflow_type_steps (workflow_type_id,step_no,label,action_type)
select id,2,'Confirm amenity reservation','execute' from workflow_types where code='W25' and version=1
on conflict (workflow_type_id,step_no) do nothing;

create table amenity_bookings (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  amenity_id uuid not null references amenities(id),
  flat_id uuid not null references flats(id),
  booked_by uuid not null default auth.uid() references profiles(id),
  approval_request_id uuid references approval_requests(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  guest_count smallint not null default 0 check (guest_count between 0 and 500),
  amount_due integer not null default 0 check (amount_due >= 0),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','paid','waived','refunded')),
  payment_reference text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled','completed')),
  note text not null default '' check (length(note) <= 500),
  created_at timestamptz not null default now(),
  approved_by uuid references profiles(id),
  approved_at timestamptz,
  check (ends_at > starts_at)
);
alter table amenity_bookings add constraint amenity_no_overlapping_active_bookings
  exclude using gist (amenity_id with =, tstzrange(starts_at,ends_at,'[)') with &&)
  where (status in ('pending','approved'));
create index amenity_bookings_tenant_date_idx on amenity_bookings (association_id,starts_at);
alter table amenity_bookings enable row level security;
create policy amenity_bookings_read on amenity_bookings for select using (
  association_id = my_association() and (
    booked_by = auth.uid()
    or has_role(association_id,array['president','vice_president','secretary','joint_secretary','caretaker']::app_role[])
  )
);

create function request_amenity_booking(
  p_amenity uuid,p_flat uuid,p_starts_at timestamptz,p_ends_at timestamptz,
  p_guest_count smallint default 0,p_note text default ''
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  m memberships;
  amenity_row amenities;
  approval_id uuid;
  booking_id uuid;
  actor_role app_role;
  request_ref text := 'APR-'||upper(substr(encode(gen_random_bytes(6),'hex'),1,10));
begin
  select * into m from memberships where association_id=a and user_id=auth.uid()
    and flat_id=p_flat and ended_at is null and role in ('owner','resident') limit 1;
  if a is null or m.id is null then raise exception 'not_allowed: active owner or resident membership for this flat required'; end if;
  select * into amenity_row from amenities where id=p_amenity and association_id=a and active;
  if amenity_row.id is null then raise exception 'not_found: amenity is not available'; end if;
  if p_starts_at < now() or p_ends_at <= p_starts_at or p_ends_at-p_starts_at > interval '24 hours' then
    raise exception 'invalid: choose a future time range up to 24 hours';
  end if;
  if length(coalesce(p_note,''))>500 then raise exception 'invalid: booking note is too long'; end if;
  if amenity_row.requires_approval then
    select role into actor_role from memberships where association_id=a and user_id=auth.uid()
      and flat_id=p_flat and ended_at is null and role in ('owner','resident') order by role limit 1;
    insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category)
    values (a,request_ref,'W25','Amenity booking: '||amenity_row.name,
      jsonb_build_object('Amenity',amenity_row.name,'Flat',p_flat::text,'Start',p_starts_at,'End',p_ends_at),
      auth.uid(),my_name(),actor_role,'Amenity booking') returning id into approval_id;
    insert into approval_steps (request_id,seq,role,name) values (approval_id,1,'secretary','Secretary');
  end if;
  insert into amenity_bookings (association_id,amenity_id,flat_id,booked_by,approval_request_id,starts_at,ends_at,
    guest_count,amount_due,payment_status,status,note)
  values (a,p_amenity,p_flat,auth.uid(),approval_id,p_starts_at,p_ends_at,coalesce(p_guest_count,0),amenity_row.fee,
    case when amenity_row.fee=0 then 'waived' else 'unpaid' end,
    case when amenity_row.requires_approval then 'pending' else 'approved' end,trim(coalesce(p_note,'')))
  returning id into booking_id;
  return booking_id;
end $$;

create function record_amenity_payment(p_booking uuid,p_reference text default null,p_waive boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid:=my_association(); b amenity_bookings;
begin
  if a is null or not has_role(a,array['treasurer','joint_treasurer','secretary']::app_role[]) then
    raise exception 'not_allowed: Treasurer, Joint Treasurer or Secretary required';
  end if;
  select * into b from amenity_bookings where id=p_booking and association_id=a for update;
  if b.id is null then raise exception 'not_found'; end if;
  if b.status not in ('approved','completed') then raise exception 'invalid: only an approved booking can be paid'; end if;
  update amenity_bookings set payment_status=case when p_waive then 'waived' else 'paid' end,
    payment_reference=nullif(trim(p_reference), '') where id=p_booking;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
    values (a,auth.uid(),case when p_waive then 'amenity_fee_waived' else 'amenity_payment_recorded' end,
      'amenity_booking',p_booking::text,jsonb_build_object('reference',p_reference));
end $$;

create function sync_amenity_booking_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; new_status text;
begin
  if old.decision is not distinct from new.decision or new.decision='pending' then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  if r.code<>'W25' then return new; end if;
  new_status:=case new.decision when 'approved' then 'approved' when 'rejected' then 'rejected' else 'pending' end;
  update amenity_bookings set status=new_status,approved_by=case when new_status='approved' then new.decided_by else null end,
    approved_at=case when new_status='approved' then now() else null end where approval_request_id=new.request_id;
  return new;
end $$;
create trigger amenity_booking_approval_sync after update of decision on approval_steps
  for each row execute function sync_amenity_booking_approval();

revoke all on function request_amenity_booking(uuid,uuid,timestamptz,timestamptz,smallint,text) from public;
grant execute on function request_amenity_booking(uuid,uuid,timestamptz,timestamptz,smallint,text) to authenticated;
revoke all on function record_amenity_payment(uuid,text,boolean) from public;
grant execute on function record_amenity_payment(uuid,text,boolean) to authenticated;