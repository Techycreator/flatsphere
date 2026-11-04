-- Walk-ins: an "Other" visitor type, visitors for the caretaker/staff (confirmed by phone),
-- and deliveries left at the lobby when the flat cannot be reached. All scoped to the open association.
alter table visitor_requests drop constraint if exists visitor_requests_entry_type_check;
alter table visitor_requests add constraint visitor_requests_entry_type_check
  check (entry_type in ('guest','delivery','cab','service','other'));
alter table visitor_requests drop constraint if exists visitor_requests_approval_check;
alter table visitor_requests add constraint visitor_requests_approval_check
  check (approval in ('pre_approved','awaiting','approved','denied','lobby','staff_confirmed'));
alter table visitor_requests add column if not exists meet_staff text
  check (meet_staff is null or length(trim(meet_staff)) between 1 and 120);
alter table visitor_requests alter column flat_id drop not null;
alter table visitor_requests drop constraint if exists visitor_requests_flat_or_staff;
alter table visitor_requests add constraint visitor_requests_flat_or_staff check (flat_id is not null or meet_staff is not null);

drop function if exists gate_walk_in(text, text, text, text, text, uuid);
drop function if exists gate_walk_in(text, text, text, text, text);
create function gate_walk_in(
  p_flat text, p_name text, p_phone text, p_type text, p_vehicle text,
  p_request_id uuid default gen_random_uuid(),
  p_mode text default 'ask',
  p_note text default '',
  p_meet text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  fid uuid;
  rid uuid;
  fno text;
  mode text := coalesce(nullif(trim(p_mode), ''), 'ask');
  typ text := coalesce(nullif(trim(p_type), ''), 'guest');
  meet text := nullif(trim(coalesce(p_meet, '')), '');
  inside boolean;
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  if p_request_id is null then raise exception 'invalid: walk-in request ID is required'; end if;
  if mode not in ('ask','lobby','staff') then raise exception 'invalid: unknown walk-in mode'; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'invalid: enter the visitor name'; end if;
  if length(coalesce(p_note, '')) > 240 then raise exception 'invalid: note must be 240 characters or fewer'; end if;
  if mode = 'staff' then
    if meet is null then raise exception 'invalid: choose the staff member they are meeting'; end if;
  else
    meet := null;
    select f.id, f.number into fid, fno from flats f where f.association_id = a and upper(f.number) = upper(trim(p_flat));
    if fid is null then raise exception 'not_found: no flat %', p_flat; end if;
  end if;
  if mode = 'lobby' and typ <> 'delivery' then raise exception 'invalid: only deliveries can be left at the lobby'; end if;
  inside := mode <> 'ask';

  insert into visitor_requests (
    id, association_id, flat_id, host_id, host_name, guest_name, guest_phone, expected_arrival,
    vehicle_number, note, entry_type, approval, meet_staff, status, checked_in_at, verified_by, verified_by_name
  )
  values (
    p_request_id, a, fid, auth.uid(), coalesce(my_name(), 'Gate'), trim(p_name),
    nullif(trim(coalesce(p_phone, '')), ''), now(),
    nullif(upper(trim(coalesce(p_vehicle, ''))), ''), trim(coalesce(p_note, '')), typ,
    case mode when 'ask' then 'awaiting' when 'lobby' then 'lobby' else 'staff_confirmed' end,
    meet, case when inside then 'checked_in' else 'expected' end,
    case when inside then now() end, case when inside then auth.uid() end, case when inside then my_name() end
  )
  on conflict (id) do nothing
  returning id into rid;

  if rid is null then
    -- Retried offline submission: return the original row if it is the same visitor.
    select v.id into rid from visitor_requests v
    where v.id = p_request_id and v.association_id = a and v.flat_id is not distinct from fid
      and v.host_id = auth.uid() and v.guest_name = trim(p_name)
      and v.guest_phone is not distinct from nullif(trim(coalesce(p_phone, '')), '')
      and v.entry_type = typ
      and v.vehicle_number is not distinct from nullif(upper(trim(coalesce(p_vehicle, ''))), '');
    if rid is null then raise exception 'invalid: walk-in request ID was already used'; end if;
    return rid;
  end if;

  if mode = 'ask' then
    insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
    select a, m.user_id, 'gate-visitor:' || rid, 'Visitor at the gate',
      initcap(typ) || ': ' || trim(p_name) || ' for flat ' || fno || '. Approve or deny in Visitors.', '/visitors'
    from memberships m where m.association_id = a and m.flat_id = fid and m.role in ('owner','resident') and m.ended_at is null
    on conflict (association_id, user_id, event_key) do nothing;
  elsif mode = 'lobby' then
    insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
    select a, m.user_id, 'gate-lobby:' || rid, 'Delivery left at the lobby',
      trim(p_name) || ' delivery for flat ' || fno || ' was left at the lobby at '
        || to_char(now() at time zone 'Asia/Kolkata', 'HH24:MI') || ' (flat could not be reached).', '/visitors'
    from memberships m where m.association_id = a and m.flat_id = fid and m.role in ('owner','resident') and m.ended_at is null
    on conflict (association_id, user_id, event_key) do nothing;
  else
    insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
    select distinct a, m.user_id, 'gate-staff:' || rid, 'Visitor for you at the gate',
      trim(p_name) || ' was let in to meet you at ' || to_char(now() at time zone 'Asia/Kolkata', 'HH24:MI') || '.', '/home'
    from memberships m join profiles p on p.id = m.user_id
    where m.association_id = a and m.ended_at is null and m.role not in ('owner','resident') and p.full_name = meet
    on conflict (association_id, user_id, event_key) do nothing;
  end if;
  if inside then
    insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'gate_walk_in_' || mode, 'visitor_request', rid::text,
      jsonb_build_object('flat', fno, 'meet', meet, 'type', typ, 'name', trim(p_name)));
  end if;
  return rid;
end $$;
revoke all on function gate_walk_in(text, text, text, text, text, uuid, text, text, text) from public, anon;
grant execute on function gate_walk_in(text, text, text, text, text, uuid, text, text, text) to authenticated;

-- A delivery already waiting for the flat: the flat could not be reached, so it is left at the lobby.
create or replace function gate_lobby_drop(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); v visitor_requests; fno text;
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  select * into v from visitor_requests where id = p_request and association_id = a for update;
  if v.id is null then raise exception 'not_found: visitor not found'; end if;
  if v.approval = 'lobby' then return; end if;
  if v.entry_type <> 'delivery' or v.approval <> 'awaiting' or v.status <> 'expected' then
    raise exception 'invalid: only a delivery still waiting for the flat can be left at the lobby';
  end if;
  update visitor_requests set approval = 'lobby', status = 'checked_in', checked_in_at = now(),
    verified_by = auth.uid(), verified_by_name = my_name()
  where id = v.id;
  select number into fno from flats where id = v.flat_id;
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select a, m.user_id, 'gate-lobby:' || v.id, 'Delivery left at the lobby',
    v.guest_name || ' delivery for flat ' || fno || ' was left at the lobby at '
      || to_char(now() at time zone 'Asia/Kolkata', 'HH24:MI') || ' (flat could not be reached).', '/visitors'
  from memberships m where m.association_id = a and m.flat_id = v.flat_id and m.role in ('owner','resident') and m.ended_at is null
  on conflict (association_id, user_id, event_key) do nothing;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (a, auth.uid(), 'gate_lobby_drop', 'visitor_request', v.id::text,
    jsonb_build_object('approval', v.approval), jsonb_build_object('approval', 'lobby'));
end $$;
revoke all on function gate_lobby_drop(uuid) from public, anon;
grant execute on function gate_lobby_drop(uuid) to authenticated;

-- Caretaker, security and office bearers the guard can call to confirm a visitor for them.
create or replace function gate_staff_contacts() returns table (name text, role text, mobile text)
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  return query
    select distinct on (p.full_name) p.full_name, m.role::text, p.mobile
    from memberships m join profiles p on p.id = m.user_id
    where m.association_id = a and m.ended_at is null and p.mobile is not null and p.full_name is not null
      and m.role in ('caretaker','security','admin','president','secretary','joint_secretary','treasurer')
    order by p.full_name, case m.role when 'caretaker' then 0 when 'security' then 1 else 2 end;
end $$;
revoke all on function gate_staff_contacts() from public, anon;
grant execute on function gate_staff_contacts() to authenticated;
