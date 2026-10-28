-- Gate mode: pre-approved guests get a 6-digit pass code; walk-in visitors wait for the flat's approval.
alter table visitor_requests add column entry_type text not null default 'guest'
  check (entry_type in ('guest','delivery','cab','service'));
alter table visitor_requests add column approval text not null default 'pre_approved'
  check (approval in ('pre_approved','awaiting','approved','denied'));
alter table visitor_requests add column pass_code text check (pass_code is null or pass_code ~ '^[0-9]{6}$');

create function set_visitor_pass_code() returns trigger language plpgsql as $$
begin
  if new.approval = 'pre_approved' and new.pass_code is null then
    new.pass_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
  end if;
  return new;
end $$;
create trigger visitor_pass_code before insert on visitor_requests for each row execute function set_visitor_pass_code();

create policy visitor_requests_read_flat on visitor_requests for select
  using (association_id = my_association() and flat_id in (select my_flat_ids(association_id)));

create function gate_check_pass(p_code text) returns table (id uuid, guest_name text, flat_number text, host_name text)
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  return query
    update visitor_requests v set status = 'checked_in', checked_in_at = now(), verified_by = auth.uid(), verified_by_name = my_name()
    from flats f
    where f.id = v.flat_id and v.association_id = a and v.pass_code = trim(p_code) and v.status = 'expected'
      and v.approval in ('pre_approved','approved')
      and (v.expected_arrival at time zone 'Asia/Kolkata')::date between current_date - 1 and current_date + 1
    returning v.id, v.guest_name, f.number, v.host_name;
end $$;

create function gate_walk_in(p_flat text, p_name text, p_phone text, p_type text, p_vehicle text) returns uuid
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); fid uuid; rid uuid;
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  select f.id into fid from flats f where f.association_id = a and upper(f.number) = upper(trim(p_flat));
  if fid is null then raise exception 'not_found: no flat %', p_flat; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'invalid: enter the visitor name'; end if;
  insert into visitor_requests (association_id, flat_id, host_id, host_name, guest_name, guest_phone, expected_arrival,
    vehicle_number, note, entry_type, approval)
  values (a, fid, auth.uid(), coalesce(my_name(), 'Gate'), trim(p_name), nullif(trim(coalesce(p_phone, '')), ''), now(),
    nullif(upper(trim(coalesce(p_vehicle, ''))), ''), '', coalesce(p_type, 'guest'), 'awaiting')
  returning id into rid;
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select a, m.user_id, 'gate-visitor:' || rid, 'Visitor at the gate',
    initcap(coalesce(p_type, 'guest')) || ': ' || trim(p_name) || ' for flat ' || upper(trim(p_flat)) || '. Approve or deny in Visitors.',
    '/visitors'
  from memberships m where m.association_id = a and m.flat_id = fid and m.role in ('owner','resident') and m.ended_at is null
  on conflict (association_id, user_id, event_key) do nothing;
  return rid;
end $$;

create function decide_gate_visitor(p_request uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update visitor_requests set approval = case when p_approve then 'approved' else 'denied' end,
    status = case when p_approve then status else 'cancelled' end
  where id = p_request and association_id = my_association() and approval = 'awaiting'
    and flat_id in (select my_flat_ids(association_id));
  if not found then raise exception 'not_found: this visitor is no longer waiting'; end if;
end $$;

revoke all on function gate_check_pass(text), gate_walk_in(text, text, text, text, text), decide_gate_visitor(uuid, boolean) from public, anon;
grant execute on function gate_check_pass(text), gate_walk_in(text, text, text, text, text), decide_gate_visitor(uuid, boolean) to authenticated;
