-- Every amenity booking follows the W25 approval workflow, whatever the amenity's old requires_approval flag says.
-- A booking stays pending and unpaid until approved; a zero-fee booking is marked waived only on approval.
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
  select role into actor_role from memberships where association_id=a and user_id=auth.uid()
    and flat_id=p_flat and ended_at is null and role in ('owner','resident') order by role limit 1;
  insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category)
  values (a,request_ref,'W25','Amenity booking: '||amenity_row.name,
    jsonb_build_object('Amenity',amenity_row.name,'Flat',p_flat::text,'Start',p_starts_at,'End',p_ends_at),
    auth.uid(),my_name(),actor_role,'Amenity booking') returning id into approval_id;
  insert into approval_steps (request_id,seq,role,name) values (approval_id,1,'secretary','Secretary');
  insert into amenity_bookings (association_id,amenity_id,flat_id,booked_by,approval_request_id,starts_at,ends_at,
    guest_count,amount_due,payment_status,status,note)
  values (a,p_amenity,p_flat,auth.uid(),approval_id,p_starts_at,p_ends_at,coalesce(p_guest_count,0),amenity_row.fee,
    'unpaid','pending',trim(coalesce(p_note,'')))
  returning id into booking_id;
  return booking_id;
end $$;

create or replace function sync_amenity_booking_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; new_status text;
begin
  if old.decision is not distinct from new.decision or new.decision = 'pending' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.code <> 'W25' then return new; end if;
  if new.decision = 'approved' and exists (select 1 from approval_steps where request_id = new.request_id and decision = 'pending') then
    return new;
  end if;
  new_status := case new.decision when 'approved' then 'approved' when 'rejected' then 'rejected' else 'pending' end;
  update amenity_bookings set status = new_status, approved_by = case when new_status = 'approved' then new.decided_by else null end,
    approved_at = case when new_status = 'approved' then now() else null end,
    payment_status = case when new_status = 'approved' and amount_due = 0 then 'waived' else payment_status end
  where approval_request_id = new.request_id;
  return new;
end $$;
