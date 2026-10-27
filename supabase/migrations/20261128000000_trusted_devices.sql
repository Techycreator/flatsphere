-- Devices where a user enabled PIN / biometric quick unlock. No PIN or biometric data is stored here;
-- the row only lets the user (or the Secretary/President/Admin) see and revoke a device.
create table trusted_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  label text not null check (length(trim(label)) between 1 and 80),
  method text not null check (method in ('pin','biometric')),
  session_id uuid,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references profiles(id)
);
create index trusted_devices_user_idx on trusted_devices (user_id) where revoked_at is null;
alter table trusted_devices enable row level security;
create policy trusted_devices_read_self on trusted_devices for select using (user_id = auth.uid());

create function register_trusted_device(p_label text, p_method text) returns uuid
language plpgsql security definer set search_path=public as $$
declare d uuid;
begin
  if auth.uid() is null then raise exception 'not_allowed'; end if;
  if (select count(*) from trusted_devices where user_id = auth.uid() and revoked_at is null) >= 10 then
    raise exception 'limit: remove an old device first (maximum 10)';
  end if;
  insert into trusted_devices (user_id, label, method, session_id)
  values (auth.uid(), left(trim(p_label), 80), p_method, nullif(auth.jwt()->>'session_id', '')::uuid)
  returning id into d;
  return d;
end $$;

-- True while the device is still trusted; also refreshes last-used time and the linked login session.
create function touch_trusted_device(p_device uuid) returns boolean
language plpgsql security definer set search_path=public as $$
begin
  update trusted_devices set last_used_at = now(),
    session_id = coalesce(nullif(auth.jwt()->>'session_id', '')::uuid, session_id)
  where id = p_device and user_id = auth.uid() and revoked_at is null;
  return found;
end $$;

create function list_trusted_devices()
returns table (id uuid, label text, method text, created_at timestamptz, last_used_at timestamptz)
language sql stable security definer set search_path=public as $$
  select d.id, d.label, d.method, d.created_at, d.last_used_at from trusted_devices d
  where d.user_id = auth.uid() and d.revoked_at is null order by d.last_used_at desc;
$$;

create function _revoke_device(d trusted_devices) returns void
language plpgsql security definer set search_path=public as $$
begin
  update trusted_devices set revoked_at = now(), revoked_by = auth.uid() where id = d.id and revoked_at is null;
  if d.session_id is not null then
    begin
      delete from auth.sessions where id = d.session_id;
    exception when others then null;
    end;
  end if;
end $$;
revoke execute on function _revoke_device(trusted_devices) from public, anon, authenticated;

create function revoke_trusted_device(p_device uuid) returns void
language plpgsql security definer set search_path=public as $$
declare d trusted_devices;
begin
  select * into d from trusted_devices where id = p_device and user_id = auth.uid();
  if d.id is null then raise exception 'not_found'; end if;
  perform _revoke_device(d);
end $$;

-- Lost phone: Secretary / President / Admin removes every trusted device of a member of their association.
create function revoke_member_devices(p_email text) returns integer
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); target uuid; d trusted_devices; n integer := 0;
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: President, Secretary or Admin only';
  end if;
  select u.id into target from auth.users u
  where lower(u.email) = lower(trim(p_email))
    and exists (select 1 from memberships m where m.user_id = u.id and m.association_id = a);
  if target is null then raise exception 'not_found: no member with that email in this association'; end if;
  for d in select * from trusted_devices where user_id = target and revoked_at is null loop
    perform _revoke_device(d);
    n := n + 1;
  end loop;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'revoke_devices', 'profile', target::text, jsonb_build_object('devices', n));
  return n;
end $$;

revoke execute on function register_trusted_device(text, text), touch_trusted_device(uuid), list_trusted_devices(),
  revoke_trusted_device(uuid), revoke_member_devices(text) from public, anon;
grant execute on function register_trusted_device(text, text), touch_trusted_device(uuid), list_trusted_devices(),
  revoke_trusted_device(uuid), revoke_member_devices(text) to authenticated;
