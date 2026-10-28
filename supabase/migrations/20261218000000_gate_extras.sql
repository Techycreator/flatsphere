-- Gate extras: visitor photos (private bucket), shared gate phone with per-guard shifts.
alter table visitor_requests add column photo_path text, add column guard_name text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('visitor-photos', 'visitor-photos', false, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy visitor_photos_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'visitor-photos' and (storage.foldername(name))[1] = my_association()::text
  and has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[]));
-- Anyone who can see the visitor row (gate staff, office bearers, that flat) can see its photo.
create policy visitor_photos_read on storage.objects for select to authenticated using (
  bucket_id = 'visitor-photos' and exists (select 1 from visitor_requests v where v.photo_path = objects.name));

create function set_visitor_photo(p_request uuid, p_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  if p_path not like my_association()::text || '/' || p_request::text || '.%' then raise exception 'invalid: bad photo path'; end if;
  update visitor_requests set photo_path = p_path where id = p_request and association_id = my_association();
  if not found then raise exception 'not_found'; end if;
end $$;

create table gate_guards (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 80),
  pin_hash text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table gate_guards enable row level security;
create policy gate_guards_read on gate_guards for select using (
  association_id = my_association()
  and has_role(association_id, array['security','caretaker','admin','president','secretary']::app_role[]));
revoke all on gate_guards from anon, authenticated;
grant select (id, association_id, name, active, created_at) on gate_guards to authenticated;

create table gate_shifts (
  user_id uuid not null,
  session_id uuid not null,
  guard_id uuid not null references gate_guards(id) on delete cascade,
  started_at timestamptz not null default now(),
  primary key (user_id, session_id)
);
alter table gate_shifts enable row level security;
revoke all on gate_shifts from anon, authenticated;

create function save_gate_guard(p_id uuid, p_name text, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role(my_association(), array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: President, Secretary or Admin only';
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'invalid: guard PIN must be 4 digits'; end if;
  if p_id is null then
    insert into gate_guards (name, pin_hash) values (trim(p_name), extensions.crypt(p_pin, extensions.gen_salt('bf')));
  else
    update gate_guards set name = trim(p_name), pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf'))
    where id = p_id and association_id = my_association();
  end if;
end $$;

create function remove_gate_guard(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role(my_association(), array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: President, Secretary or Admin only';
  end if;
  update gate_guards set active = false where id = p_id and association_id = my_association();
end $$;

create function gate_start_shift(p_guard uuid, p_pin text) returns text
language plpgsql security definer set search_path = public as $$
declare
  g gate_guards;
  sid uuid := nullif(auth.jwt()->>'session_id', '')::uuid;
begin
  if not has_role(my_association(), array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  select * into g from gate_guards where id = p_guard and association_id = my_association() and active;
  if g.id is null or g.pin_hash <> extensions.crypt(coalesce(p_pin, ''), g.pin_hash) then
    raise exception 'invalid: wrong guard or PIN';
  end if;
  if sid is null then raise exception 'invalid: session missing, log in again'; end if;
  insert into gate_shifts (user_id, session_id, guard_id) values (auth.uid(), sid, g.id)
  on conflict (user_id, session_id) do update set guard_id = excluded.guard_id, started_at = now();
  return g.name;
end $$;

-- Every gate entry/check-in/out records the guard on duty on this phone's session.
create function stamp_gate_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text;
begin
  select gg.name into g from gate_shifts s join gate_guards gg on gg.id = s.guard_id
  where s.user_id = auth.uid() and s.session_id = nullif(auth.jwt()->>'session_id', '')::uuid and gg.active;
  if g is not null then new.guard_name := g; end if;
  return new;
end $$;
create trigger visitor_requests_stamp_guard before insert or update on visitor_requests
for each row execute function stamp_gate_guard();

revoke all on function set_visitor_photo(uuid, text), save_gate_guard(uuid, text, text), remove_gate_guard(uuid),
  gate_start_shift(uuid, text) from public, anon;
grant execute on function set_visitor_photo(uuid, text), save_gate_guard(uuid, text, text), remove_gate_guard(uuid),
  gate_start_shift(uuid, text) to authenticated;
revoke all on function stamp_gate_guard() from public, anon, authenticated;
