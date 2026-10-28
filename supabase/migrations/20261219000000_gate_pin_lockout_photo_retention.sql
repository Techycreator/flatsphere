-- Guard PIN lockout (5 wrong tries -> 15 minutes) and 60-day visitor photo retention.
alter table gate_guards add column failed_attempts int not null default 0, add column locked_until timestamptz;

drop function gate_start_shift(uuid, text);
create function gate_start_shift(p_guard uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  g gate_guards;
  sid uuid := nullif(auth.jwt()->>'session_id', '')::uuid;
begin
  if not has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  select * into g from gate_guards where id = p_guard and association_id = my_association() and active for update;
  if g.id is null then return jsonb_build_object('ok', false, 'error', 'Guard not found'); end if;
  if g.locked_until > now() then
    return jsonb_build_object('ok', false, 'error', 'Too many wrong PINs. Try again after '
      || to_char(g.locked_until at time zone 'Asia/Kolkata', 'HH24:MI') || ' or ask the Secretary to reset the PIN.');
  end if;
  if g.pin_hash <> extensions.crypt(coalesce(p_pin, ''), g.pin_hash) then
    if g.failed_attempts + 1 >= 5 then
      update gate_guards set failed_attempts = 0, locked_until = now() + interval '15 minutes' where id = g.id;
      return jsonb_build_object('ok', false, 'error', 'Too many wrong PINs. This guard is locked for 15 minutes.');
    end if;
    update gate_guards set failed_attempts = failed_attempts + 1 where id = g.id;
    return jsonb_build_object('ok', false, 'error', 'Wrong PIN. ' || (4 - g.failed_attempts) || ' tries left.');
  end if;
  if sid is null then return jsonb_build_object('ok', false, 'error', 'Session missing, log in again'); end if;
  update gate_guards set failed_attempts = 0, locked_until = null where id = g.id;
  insert into gate_shifts (user_id, session_id, guard_id) values (auth.uid(), sid, g.id)
  on conflict (user_id, session_id) do update set guard_id = excluded.guard_id, started_at = now();
  return jsonb_build_object('ok', true, 'name', g.name);
end $$;
revoke all on function gate_start_shift(uuid, text) from public, anon;
grant execute on function gate_start_shift(uuid, text) to authenticated;

create or replace function save_gate_guard(p_id uuid, p_name text, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role(my_association(), array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: President, Secretary or Admin only';
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'invalid: guard PIN must be 4 digits'; end if;
  if p_id is null then
    insert into gate_guards (name, pin_hash) values (trim(p_name), extensions.crypt(p_pin, extensions.gen_salt('bf')));
  else
    update gate_guards set name = trim(p_name), pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
      failed_attempts = 0, locked_until = null
    where id = p_id and association_id = my_association();
  end if;
end $$;

create policy visitor_photos_delete on storage.objects for delete to authenticated using (
  bucket_id = 'visitor-photos' and (storage.foldername(name))[1] = my_association()::text
  and has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[])
  and exists (select 1 from visitor_requests v
              where v.photo_path = objects.name and v.created_at < now() - interval '60 days'));

create function expired_visitor_photos() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(photo_path), '{}') from (
    select photo_path from visitor_requests
    where association_id = my_association() and photo_path is not null
      and created_at < now() - interval '60 days'
      and has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[])
    limit 100) t
$$;

create function clear_visitor_photos(p_paths text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  update visitor_requests v set photo_path = null
  where v.association_id = my_association() and v.photo_path = any(p_paths)
    and v.created_at < now() - interval '60 days'
    and not exists (select 1 from storage.objects o where o.bucket_id = 'visitor-photos' and o.name = v.photo_path);
end $$;
revoke all on function expired_visitor_photos(), clear_visitor_photos(text[]) from public, anon;
grant execute on function expired_visitor_photos(), clear_visitor_photos(text[]) to authenticated;
