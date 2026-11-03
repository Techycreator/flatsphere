-- Keep shared gate-phone shifts and guard stamps isolated by association.
alter table gate_shifts add column association_id uuid references associations(id) on delete cascade;
update gate_shifts s
set association_id = g.association_id
from gate_guards g
where g.id = s.guard_id;
alter table gate_shifts alter column association_id set not null;
alter table gate_shifts drop constraint gate_shifts_pkey;
alter table gate_shifts add primary key (association_id, user_id, session_id);

create or replace function gate_start_shift(p_guard uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  g gate_guards;
  sid uuid := nullif(auth.jwt()->>'session_id', '')::uuid;
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  select * into g from gate_guards where id = p_guard and association_id = a and active for update;
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
  insert into gate_shifts (association_id, user_id, session_id, guard_id)
  values (a, auth.uid(), sid, g.id)
  on conflict (association_id, user_id, session_id) do update
    set guard_id = excluded.guard_id, started_at = now();
  return jsonb_build_object('ok', true, 'name', g.name);
end $$;

create or replace function stamp_gate_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text;
begin
  select gg.name into g
  from gate_shifts s
  join gate_guards gg on gg.id = s.guard_id
  where s.association_id = new.association_id
    and s.user_id = auth.uid()
    and s.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and gg.active;
  if g is not null then new.guard_name := g; end if;
  return new;
end $$;

create function gate_current_shift() returns text
language sql stable security definer set search_path = public as $$
  select gg.name
  from gate_shifts s
  join gate_guards gg on gg.id = s.guard_id
  where s.association_id = my_association()
    and s.user_id = auth.uid()
    and s.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and gg.active
    and has_role(s.association_id, array['security','caretaker','admin','president','secretary']::app_role[])
  limit 1;
$$;

revoke all on function gate_current_shift() from public, anon;
grant execute on function gate_current_shift() to authenticated;
