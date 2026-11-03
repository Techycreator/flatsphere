drop function if exists gate_walk_in(text, text, text, text, text);

create function gate_walk_in(
  p_flat text,
  p_name text,
  p_phone text,
  p_type text,
  p_vehicle text,
  p_request_id uuid default gen_random_uuid()
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  fid uuid;
  rid uuid;
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  if p_request_id is null then
    raise exception 'invalid: walk-in request ID is required';
  end if;
  select f.id into fid from flats f where f.association_id = a and upper(f.number) = upper(trim(p_flat));
  if fid is null then raise exception 'not_found: no flat %', p_flat; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'invalid: enter the visitor name'; end if;
  insert into visitor_requests (
    id, association_id, flat_id, host_id, host_name, guest_name, guest_phone, expected_arrival,
    vehicle_number, note, entry_type, approval
  )
  values (
    p_request_id, a, fid, auth.uid(), coalesce(my_name(), 'Gate'), trim(p_name),
    nullif(trim(coalesce(p_phone, '')), ''), now(),
    nullif(upper(trim(coalesce(p_vehicle, ''))), ''), '', coalesce(p_type, 'guest'), 'awaiting'
  )
  on conflict (id) do nothing
  returning id into rid;

  if rid is null then
    select v.id into rid
    from visitor_requests v
    where v.id = p_request_id
      and v.association_id = a
      and v.flat_id = fid
      and v.host_id = auth.uid()
      and v.guest_name = trim(p_name)
      and v.guest_phone is not distinct from nullif(trim(coalesce(p_phone, '')), '')
      and v.entry_type = coalesce(p_type, 'guest')
      and v.vehicle_number is not distinct from nullif(upper(trim(coalesce(p_vehicle, ''))), '');
    if rid is null then
      raise exception 'invalid: walk-in request ID was already used';
    end if;
    return rid;
  end if;

  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select a, m.user_id, 'gate-visitor:' || rid, 'Visitor at the gate',
    initcap(coalesce(p_type, 'guest')) || ': ' || trim(p_name) || ' for flat ' || upper(trim(p_flat)) || '. Approve or deny in Visitors.',
    '/visitors'
  from memberships m where m.association_id = a and m.flat_id = fid and m.role in ('owner','resident') and m.ended_at is null
  on conflict (association_id, user_id, event_key) do nothing;
  return rid;
end $$;

revoke all on function gate_walk_in(text, text, text, text, text, uuid) from public, anon;
grant execute on function gate_walk_in(text, text, text, text, text, uuid) to authenticated;
