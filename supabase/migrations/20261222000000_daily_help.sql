-- Daily help passes (maid, cook, driver, newspaper, milk...): registered once, permanent 6-digit code,
-- quick in/out at the gate within allowed days/hours, alerts to the flats, monthly log. Strictly per association.
create table daily_help (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 80),
  kind text not null default 'maid' check (kind in ('maid','cook','driver','cleaner','newspaper','milk','other')),
  phone text check (phone is null or phone ~ '^[0-9+ -]{6,20}$'),
  flat_ids uuid[] not null default '{}', -- empty = association-wide service (newspaper, milk, garbage)
  days smallint[] not null default '{1,2,3,4,5,6,7}' check (days <@ '{1,2,3,4,5,6,7}'::smallint[] and cardinality(days) > 0),
  start_time time,
  end_time time,
  notify boolean not null default true,
  pass_code text not null check (pass_code ~ '^[0-9]{6}$'),
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index daily_help_active_code on daily_help (association_id, pass_code) where active;
alter table daily_help enable row level security;
create policy daily_help_read on daily_help for select using (
  association_id = my_association() and (
    has_role(association_id, array['security','caretaker','admin','president','secretary']::app_role[])
    or flat_ids && array(select my_flat_ids(association_id))));
revoke all on daily_help from anon, authenticated;
grant select on daily_help to authenticated;

create table daily_help_log (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  help_id uuid not null references daily_help(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  guard_name text
);
create index daily_help_log_help on daily_help_log (help_id, checked_in_at desc);
alter table daily_help_log enable row level security;
-- Visible exactly when the pass is visible (daily_help RLS applies inside the subquery).
create policy daily_help_log_read on daily_help_log for select using (
  association_id = my_association() and exists (select 1 from daily_help h where h.id = help_id));
revoke all on daily_help_log from anon, authenticated;
grant select on daily_help_log to authenticated;
create trigger daily_help_log_stamp_guard before insert or update on daily_help_log
for each row execute function stamp_gate_guard();

create function new_daily_help_code(a uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text; tries int := 0;
begin
  loop
    c := lpad(((('x' || lpad(encode(extensions.gen_random_bytes(4), 'hex'), 16, '0'))::bit(64)::bigint) % 1000000)::text, 6, '0');
    exit when not exists (select 1 from daily_help where association_id = a and pass_code = c and active);
    tries := tries + 1;
    if tries > 20 then raise exception 'could not generate a pass code, try again'; end if;
  end loop;
  return c;
end $$;

create function save_daily_help(p_id uuid, p_flat uuid, p_name text, p_kind text, p_phone text,
  p_days smallint[], p_start time, p_end time, p_notify boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  committee boolean := has_role(a, array['caretaker','admin','president','secretary']::app_role[]);
  ph text := nullif(trim(coalesce(p_phone, '')), '');
  hid uuid;
begin
  if a is null or not is_member(a) then raise exception 'not_allowed: members only'; end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'invalid: enter the name'; end if;
  if p_start is not null and p_end is not null and p_start >= p_end then
    raise exception 'invalid: end time must be after start time';
  end if;
  if p_flat is null then
    if not committee then raise exception 'not_allowed: choose your flat'; end if;
  elsif not (p_flat in (select my_flat_ids(a))
             or (committee and exists (select 1 from flats where id = p_flat and association_id = a))) then
    raise exception 'not_allowed: not your flat';
  end if;
  if p_id is null then
    -- Same person already serving another flat here: link this flat to the existing pass.
    if ph is not null and p_flat is not null then
      select id into hid from daily_help
      where association_id = a and active and phone is not null
        and regexp_replace(phone, '\D', '', 'g') = regexp_replace(ph, '\D', '', 'g')
      limit 1;
      if hid is not null then
        update daily_help set flat_ids = array_append(flat_ids, p_flat)
        where id = hid and not (p_flat = any(flat_ids));
        return hid;
      end if;
    end if;
    insert into daily_help (association_id, name, kind, phone, flat_ids, days, start_time, end_time, notify, pass_code)
    values (a, trim(p_name), coalesce(p_kind, 'other'), ph,
      case when p_flat is null then '{}'::uuid[] else array[p_flat] end,
      coalesce(p_days, '{1,2,3,4,5,6,7}'), p_start, p_end, coalesce(p_notify, true), new_daily_help_code(a))
    returning id into hid;
    return hid;
  end if;
  update daily_help set name = trim(p_name), kind = coalesce(p_kind, kind), phone = ph,
    days = coalesce(p_days, days), start_time = p_start, end_time = p_end, notify = coalesce(p_notify, notify)
  where id = p_id and association_id = a and active
    and (committee or flat_ids && array(select my_flat_ids(a)));
  if not found then raise exception 'not_found'; end if;
  return p_id;
end $$;

create function remove_daily_help(p_id uuid, p_flat uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  committee boolean := has_role(a, array['caretaker','admin','president','secretary']::app_role[]);
begin
  if p_flat is null then
    if not committee then raise exception 'not_allowed: committee only'; end if;
    update daily_help set active = false where id = p_id and association_id = a;
  else
    if not (p_flat in (select my_flat_ids(a)) or committee) then raise exception 'not_allowed: not your flat'; end if;
    update daily_help set flat_ids = array_remove(flat_ids, p_flat),
      active = active and cardinality(array_remove(flat_ids, p_flat)) > 0
    where id = p_id and association_id = a and p_flat = any(flat_ids);
  end if;
  if not found then raise exception 'not_found'; end if;
end $$;

create function gate_daily_help(p_id uuid, p_in boolean, p_at timestamptz default null) returns text
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  h daily_help;
  t timestamptz := coalesce(p_at, now());
  lt timestamp;
  lid uuid;
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  if t > now() + interval '5 minutes' or t < now() - interval '12 hours' then t := now(); end if;
  lt := t at time zone 'Asia/Kolkata';
  select * into h from daily_help where id = p_id and association_id = a and active;
  if h.id is null then raise exception 'not_found: this pass is removed or blocked'; end if;
  if p_in then
    if exists (select 1 from daily_help_log where help_id = h.id and checked_out_at is null
               and checked_in_at > now() - interval '20 hours') then
      raise exception 'invalid: % is already inside', h.name;
    end if;
    if not (extract(isodow from lt)::smallint = any(h.days))
       or (h.start_time is not null and lt::time < h.start_time)
       or (h.end_time is not null and lt::time > h.end_time) then
      raise exception 'invalid: % is outside allowed days/hours. Use Walk-in so the flat can approve.', h.name;
    end if;
    insert into daily_help_log (association_id, help_id, checked_in_at) values (a, h.id, t) returning id into lid;
  else
    update daily_help_log set checked_out_at = greatest(t, checked_in_at)
    where id = (select id from daily_help_log where help_id = h.id and checked_out_at is null
                order by checked_in_at desc limit 1)
    returning id into lid;
    if lid is null then raise exception 'invalid: % is not checked in', h.name; end if;
  end if;
  if h.notify and cardinality(h.flat_ids) > 0 then
    insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
    select distinct a, m.user_id, 'daily-help:' || lid || case when p_in then ':in' else ':out' end,
      'Daily help ' || case when p_in then 'entered' else 'left' end,
      h.name || ' (' || h.kind || ') ' || case when p_in then 'entered' else 'left' end || ' at ' || to_char(lt, 'HH24:MI'),
      '/visitors'
    from memberships m
    where m.association_id = a and m.flat_id = any(h.flat_ids) and m.role in ('owner','resident') and m.ended_at is null
    on conflict (association_id, user_id, event_key) do nothing;
  end if;
  return h.name;
end $$;

revoke all on function new_daily_help_code(uuid) from public, anon, authenticated;
revoke all on function save_daily_help(uuid, uuid, text, text, text, smallint[], time, time, boolean),
  remove_daily_help(uuid, uuid), gate_daily_help(uuid, boolean, timestamptz) from public, anon;
grant execute on function save_daily_help(uuid, uuid, text, text, text, smallint[], time, time, boolean),
  remove_daily_help(uuid, uuid), gate_daily_help(uuid, boolean, timestamptz) to authenticated;
