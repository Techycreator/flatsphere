create table flat_vehicles (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  flat_id uuid not null references flats(id) on delete cascade,
  vehicle_type text not null check (vehicle_type in ('car','bike')),
  registration_number text not null check (length(trim(registration_number)) between 3 and 24),
  parking_slot text check (parking_slot is null or length(trim(parking_slot)) <= 24),
  created_at timestamptz not null default now(),
  unique (flat_id, vehicle_type),
  unique (association_id, registration_number)
);
alter table flat_vehicles enable row level security;
create policy flat_vehicles_read on flat_vehicles for select using (
  association_id = my_association()
  and (flat_id in (select my_flat_ids(association_id))
         or has_role(association_id, array['president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer','ec_member','monitor','caretaker','security']::app_role[]))
);

create function save_flat_vehicles(p_flat uuid, p_car text, p_bike text, p_slot text default null) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not can_manage_members(a) then
    raise exception 'not_allowed: only the President or Secretary can edit flat vehicle records';
  end if;
  if not exists (select 1 from flats where id = p_flat and association_id = a) then
    raise exception 'not_found: flat not found in this association';
  end if;
  if length(trim(coalesce(p_car, ''))) > 24 or length(trim(coalesce(p_bike, ''))) > 24
     or length(trim(coalesce(p_slot, ''))) > 24 then
    raise exception 'invalid: vehicle and parking values must be 24 characters or fewer';
  end if;
  if nullif(trim(p_car), '') is null then
    delete from flat_vehicles where flat_id = p_flat and vehicle_type = 'car';
  else
    insert into flat_vehicles (association_id, flat_id, vehicle_type, registration_number, parking_slot)
    values (a, p_flat, 'car', upper(trim(p_car)), nullif(trim(p_slot), ''))
    on conflict (flat_id, vehicle_type) do update
      set registration_number = excluded.registration_number, parking_slot = excluded.parking_slot;
  end if;
  if nullif(trim(p_bike), '') is null then
    delete from flat_vehicles where flat_id = p_flat and vehicle_type = 'bike';
  else
    insert into flat_vehicles (association_id, flat_id, vehicle_type, registration_number, parking_slot)
    values (a, p_flat, 'bike', upper(trim(p_bike)), nullif(trim(p_slot), ''))
    on conflict (flat_id, vehicle_type) do update
      set registration_number = excluded.registration_number, parking_slot = excluded.parking_slot;
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'save_flat_vehicles', 'flat', p_flat::text,
    jsonb_build_object('car', nullif(trim(p_car), ''), 'bike', nullif(trim(p_bike), ''), 'slot', nullif(trim(p_slot), '')));
end $$;

create table visitor_requests (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  flat_id uuid not null references flats(id),
  host_id uuid not null default auth.uid() references profiles(id),
  host_name text not null default my_name(),
  guest_name text not null check (length(trim(guest_name)) between 1 and 120),
  guest_phone text check (guest_phone is null or length(trim(guest_phone)) <= 24),
  expected_arrival timestamptz not null,
  vehicle_number text check (vehicle_number is null or length(trim(vehicle_number)) <= 24),
  note text not null default '' check (length(note) <= 240),
  status text not null default 'expected' check (status in ('expected','checked_in','checked_out','cancelled')),
  verified_by uuid references profiles(id),
  verified_by_name text,
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  created_at timestamptz not null default now()
);
create index visitor_requests_association_arrival_idx on visitor_requests (association_id, expected_arrival desc);
alter table visitor_requests enable row level security;
create policy visitor_requests_read on visitor_requests for select using (
  association_id = my_association()
    and (host_id = auth.uid() or has_role(association_id,
      array['president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer','ec_member','monitor','caretaker','security']::app_role[]))
);

create function create_visitor_request(
  p_flat uuid,
  p_guest_name text,
  p_guest_phone text,
  p_expected_arrival timestamptz,
  p_vehicle_number text default null,
  p_note text default ''
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  request_id uuid;
begin
  if a is null or not exists (
    select 1 from memberships m where m.association_id = a and m.user_id = auth.uid()
      and m.flat_id = p_flat and m.ended_at is null and m.role in ('owner','resident')
  ) then
    raise exception 'not_allowed: only an active owner or resident of the selected flat can register visitors';
  end if;
  if coalesce(trim(p_guest_name), '') = '' then raise exception 'invalid: enter the visitor name'; end if;
  if p_expected_arrival < now() - interval '5 minutes' or p_expected_arrival > now() + interval '1 year' then
    raise exception 'invalid: arrival time must be in the next year';
  end if;
  if length(coalesce(p_note, '')) > 240 then raise exception 'invalid: note must be 240 characters or fewer'; end if;
  insert into visitor_requests (association_id, flat_id, guest_name, guest_phone, expected_arrival, vehicle_number, note)
  values (a, p_flat, trim(p_guest_name), nullif(trim(p_guest_phone), ''), p_expected_arrival,
    nullif(upper(trim(p_vehicle_number)), ''), trim(coalesce(p_note, '')))
  returning id into request_id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'create_visitor_request', 'visitor_request', request_id::text,
    jsonb_build_object('flat_id', p_flat, 'guest_name', trim(p_guest_name), 'expected_arrival', p_expected_arrival));
  return request_id;
end $$;

create function verify_visitor_request(p_request uuid, p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  v visitor_requests;
  who text := my_name();
begin
  if a is null or not has_role(a, array['security','caretaker']::app_role[]) then
    raise exception 'not_allowed: only Security or the caretaker can verify visitor arrivals';
  end if;
  select * into v from visitor_requests where id = p_request and association_id = a for update;
  if v.id is null then raise exception 'not_found: visitor request not found'; end if;
  if p_action = 'check_in' and v.status = 'expected' then
    update visitor_requests set status = 'checked_in', verified_by = auth.uid(), verified_by_name = who, checked_in_at = now()
      where id = p_request;
  elsif p_action = 'check_out' and v.status = 'checked_in' then
    update visitor_requests set status = 'checked_out', verified_by = auth.uid(), verified_by_name = who, checked_out_at = now()
      where id = p_request;
  else
    raise exception 'invalid: visitor request cannot be updated to that status';
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (a, auth.uid(), 'verify_visitor_' || p_action, 'visitor_request', p_request::text,
    jsonb_build_object('status', v.status), jsonb_build_object('status', case p_action when 'check_in' then 'checked_in' else 'checked_out' end));
end $$;

revoke all on function save_flat_vehicles(uuid, text, text, text) from public;
grant execute on function save_flat_vehicles(uuid, text, text, text) to authenticated;
revoke all on function create_visitor_request(uuid, text, text, timestamptz, text, text) from public;
grant execute on function create_visitor_request(uuid, text, text, timestamptz, text, text) to authenticated;
revoke all on function verify_visitor_request(uuid, text) from public;
grant execute on function verify_visitor_request(uuid, text) to authenticated;