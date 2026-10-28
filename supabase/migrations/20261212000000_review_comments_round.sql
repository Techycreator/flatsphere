-- 1. Complaint closure and reopening by the raiser, office bearers or the area monitor.
create or replace function guard_complaint_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('app.complaint_closure', true) = 'on' then return new; end if;
  if new.status is distinct from old.status and not (
    has_role(old.association_id, array['caretaker','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = old.association_id and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and old.category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  ) then
    raise exception 'not_allowed: status updates require caretaker, Secretary, Joint Secretary, or the assigned area monitor';
  end if;
  return new;
end $$;

create function close_or_reopen_complaint(p_ref text, p_close boolean, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  c complaints;
  new_status ticket_status := case when p_close then 'closed' else 'in_progress' end;
begin
  if a is null then raise exception 'not_allowed: association session required'; end if;
  select * into c from complaints where association_id = a and ref = p_ref for update;
  if c.id is null then raise exception 'not_found: complaint not found'; end if;
  if c.status <> 'resolved' then raise exception 'invalid: only a resolved complaint can be closed or reopened'; end if;
  if not (
    c.raised_by = auth.uid()
    or has_role(a, array['president','vice_president','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = a and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and c.category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  ) then
    raise exception 'not_allowed: only the person who raised it, the President, Vice President, Secretary, Joint Secretary or the area monitor can close or reopen';
  end if;
  if not p_close and coalesce(trim(p_note), '') = '' then raise exception 'invalid: add a reason to reopen'; end if;
  perform set_config('app.complaint_closure', 'on', true);
  update complaints set status = new_status where id = c.id;
  perform set_config('app.complaint_closure', 'off', true);
  insert into complaint_remarks (complaint_id, author, author_name, body)
  values (c.id, auth.uid(), my_name(), '[' || new_status::text || '] ' ||
    coalesce(nullif(trim(p_note), ''), 'Confirmed resolved'));
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (a, auth.uid(), 'close_or_reopen_complaint', 'complaint', c.ref,
    jsonb_build_object('status', c.status), jsonb_build_object('status', new_status, 'note', p_note));
end $$;
revoke all on function close_or_reopen_complaint(text, boolean, text) from public;
grant execute on function close_or_reopen_complaint(text, boolean, text) to authenticated;

-- 2. Vehicle lookup ignores spaces, hyphens, slashes and other separators, and also searches visitor vehicles.
drop function search_vehicle_contacts(text);
create function search_vehicle_contacts(p_vehicle_number text)
returns table (registration_number text, vehicle_type text, flat_number text, person_name text, phone text)
language plpgsql stable security definer set search_path = public as $$
declare
  a uuid := my_association();
  search_value text := regexp_replace(upper(coalesce(p_vehicle_number, '')), '[^A-Z0-9]', '', 'g');
begin
  if a is null or not has_role(a, array[
    'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer',
    'ec_member','caretaker','security'
  ]::app_role[]) then
    raise exception 'not_allowed: vehicle lookup is limited to gate staff, office bearers and EC members';
  end if;
  if length(search_value) < 3 then raise exception 'invalid: enter at least three characters'; end if;
  return query
    select s.registration_number, s.vehicle_type, s.flat_number, s.person_name, s.phone from (
      select v.registration_number, v.vehicle_type, f.number as flat_number, p.full_name as person_name,
             coalesce(m.contact_phone, p.mobile, inv.mobile) as phone,
             case m.role when 'owner' then 0 when 'resident' then 1 else 2 end as rank
      from flat_vehicles v
      join flats f on f.id = v.flat_id and f.association_id = a
      left join memberships m on m.flat_id = f.id and m.association_id = a and m.ended_at is null
        and m.role in ('owner','resident')
      left join profiles p on p.id = m.user_id
      left join lateral (
        select i.mobile from invites i
        where i.association_id = a and i.flat_id = f.id and i.role = m.role and lower(i.email) = lower(p.email)
        order by i.created_at desc limit 1
      ) inv on true
      where v.association_id = a
        and regexp_replace(upper(v.registration_number), '[^A-Z0-9]', '', 'g') like '%' || search_value || '%'
      union all
      (select distinct on (vr.vehicle_number, vr.flat_id) vr.vehicle_number, 'visitor', f.number,
             vr.guest_name || ' (visitor of ' || coalesce(vr.host_name, 'resident') || ')', vr.guest_phone, 3
      from visitor_requests vr
      join flats f on f.id = vr.flat_id and f.association_id = a
      where vr.association_id = a and vr.vehicle_number is not null and vr.status <> 'cancelled'
        and regexp_replace(upper(vr.vehicle_number), '[^A-Z0-9]', '', 'g') like '%' || search_value || '%'
      order by vr.vehicle_number, vr.flat_id, vr.expected_arrival desc)
    ) s
    order by s.flat_number, s.rank, s.person_name;
end $$;
revoke all on function search_vehicle_contacts(text) from public;
grant execute on function search_vehicle_contacts(text) to authenticated;

-- 3. Visitor list: six office-bearer roles, caretaker and security see all; owners and residents only their own.
drop policy visitor_requests_read on visitor_requests;
create policy visitor_requests_read on visitor_requests for select using (
  association_id = my_association()
    and (host_id = auth.uid() or has_role(association_id,
      array['admin','president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer','caretaker','security']::app_role[]))
);

-- 4. Marketplace removal: the author or an office bearer; never caretaker or security for others' posts.
drop policy marketplace_update on marketplace_posts;
create policy marketplace_update on marketplace_posts for update using (
  association_id = my_association() and (created_by = auth.uid() or has_role(association_id,
    array['admin','president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer']::app_role[]))
) with check (association_id = my_association());

create or replace function remove_marketplace_post(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update marketplace_posts set status = 'removed', removed_at = now()
  where id = p_id and association_id = my_association() and status = 'active'
    and (created_by = auth.uid() or has_role(association_id,
      array['admin','president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer']::app_role[]));
  if not found then raise exception 'not_allowed: only the author or an office bearer can remove this post'; end if;
end $$;

-- 5. Association documents are hidden from residents, security and auditors.
drop policy association_documents_read on association_documents;
create policy association_documents_read on association_documents for select using (
  association_id = my_association()
  and has_role(association_id, array['admin','president','vice_president','secretary','joint_secretary','treasurer',
    'joint_treasurer','ec_member','monitor','caretaker','owner']::app_role[])
  and (archived_at is null or can_manage_members(association_id))
);

-- 6. Staff attendance can be read by EC members and treasurers too.
create or replace function can_read_staff_area(assoc uuid, staff_area text) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and (
    has_role(assoc, array['admin','president','vice_president','secretary','joint_secretary','treasurer',
      'joint_treasurer','ec_member','caretaker']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and staff_area = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= timezone('Asia/Kolkata', now())::date)
        and (m.monitor_until is null or m.monitor_until >= timezone('Asia/Kolkata', now())::date)
    )
  );
$$;

-- 7. Amenity booking failed because gen_random_bytes is not on the function search path.
create or replace function request_amenity_booking(
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
  request_ref text := 'APR-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
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

-- 8. Real photo and voice-note attachments for complaints.
create table complaint_media (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  complaint_id uuid not null references complaints(id) on delete cascade,
  kind text not null check (kind in ('photo','voice')),
  storage_path text not null unique,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
create index complaint_media_complaint_idx on complaint_media (complaint_id);
alter table complaint_media enable row level security;
create policy complaint_media_read on complaint_media for select using (
  association_id = my_association() and exists (select 1 from complaints c where c.id = complaint_media.complaint_id)
);
create policy complaint_media_insert on complaint_media for insert with check (
  association_id = my_association() and created_by = auth.uid()
  and exists (select 1 from complaints c where c.id = complaint_id and c.raised_by = auth.uid())
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('complaint-media', 'complaint-media', false, 5242880, array['image/jpeg','audio/wav'])
on conflict (id) do nothing;
create policy complaint_media_storage_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'complaint-media' and (storage.foldername(name))[1] = my_association()::text
);
create policy complaint_media_storage_read on storage.objects for select to authenticated using (
  bucket_id = 'complaint-media' and exists (select 1 from complaint_media m where m.storage_path = name)
);
