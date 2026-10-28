-- Meeting links + attendance, scheduled meeting reminders and AMC/warranty alerts, editable caretaker
-- checklist items, dues reminders and payment receipts as in-app notifications, amenity availability.

alter table association_meetings add column meeting_link text
  check (meeting_link is null or meeting_link ~ '^https://\S+$');

create function set_meeting_link(p_meeting uuid, p_link text) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); link text := nullif(trim(p_link), '');
begin
  if a is null or not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can set the meeting link';
  end if;
  if link is not null and link !~ '^https://\S+$' then raise exception 'invalid: paste the full https:// meeting link'; end if;
  update association_meetings set meeting_link = link, updated_at = now() where id = p_meeting and association_id = a;
  if not found then raise exception 'not_found'; end if;
end $$;

create function meeting_audience(p_meeting uuid) returns table (user_id uuid)
language sql stable security definer set search_path=public as $$
  select distinct mb.user_id from association_meetings am
  join memberships mb on mb.association_id = am.association_id and mb.ended_at is null
  where am.id = p_meeting and case am.meeting_type
    when 'General Body' then mb.role in ('owner','resident')
    when 'Staff meeting' then mb.role in ('caretaker','security')
    when 'Office bearers' then mb.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer')
    else mb.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member')
  end;
$$;
revoke execute on function meeting_audience(uuid) from public, anon, authenticated;

create table meeting_attendance (
  meeting_id uuid not null references association_meetings(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  association_id uuid not null references associations(id) on delete cascade,
  present boolean not null,
  how text not null check (how in ('joined_online','marked')),
  marked_by uuid not null references profiles(id),
  marked_at timestamptz not null default now(),
  primary key (meeting_id, user_id)
);
alter table meeting_attendance enable row level security;
create policy meeting_attendance_read on meeting_attendance for select using (
  association_id = my_association() and (user_id = auth.uid()
    or has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[])));

-- Returns the link and records the caller as present (joined online). Opens 15 min before start, closes 3 h after.
create function join_meeting(p_meeting uuid) returns text
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); m association_meetings;
begin
  select * into m from association_meetings where id = p_meeting and association_id = a;
  if m.id is null then raise exception 'not_found'; end if;
  if m.meeting_mode = 'inPerson' or m.meeting_link is null then raise exception 'invalid: this meeting has no online link yet'; end if;
  if now() < m.starts_at - interval '15 minutes' or now() > m.starts_at + interval '3 hours' then
    raise exception 'invalid: the meeting can be joined from 15 minutes before the start time';
  end if;
  if not exists (select 1 from meeting_audience(m.id) x where x.user_id = auth.uid()) then
    raise exception 'not_allowed: you are not invited to this meeting';
  end if;
  insert into meeting_attendance (meeting_id, user_id, association_id, present, how, marked_by)
  values (m.id, auth.uid(), a, true, 'joined_online', auth.uid()) on conflict (meeting_id, user_id) do nothing;
  return m.meeting_link;
end $$;

create function mark_meeting_attendance(p_meeting uuid, p_user uuid, p_present boolean) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); m association_meetings;
begin
  if a is null or not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can mark attendance';
  end if;
  select * into m from association_meetings where id = p_meeting and association_id = a;
  if m.id is null then raise exception 'not_found'; end if;
  if now() < m.starts_at - interval '15 minutes' then raise exception 'invalid: attendance opens when the meeting starts'; end if;
  if not exists (select 1 from meeting_audience(m.id) x where x.user_id = p_user) then
    raise exception 'invalid: this person is not invited to the meeting';
  end if;
  insert into meeting_attendance (meeting_id, user_id, association_id, present, how, marked_by)
  values (m.id, p_user, a, p_present, 'marked', auth.uid())
  on conflict (meeting_id, user_id) do update set present = excluded.present, how = 'marked',
    marked_by = excluded.marked_by, marked_at = now();
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'mark_attendance', 'meeting', m.id::text, jsonb_build_object('user', p_user, 'present', p_present));
end $$;

create function meeting_attendance_list(p_meeting uuid)
returns table (user_id uuid, full_name text, rsvp text, present boolean, how text)
language plpgsql stable security definer set search_path=public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[])
     or not exists (select 1 from association_meetings where id = p_meeting and association_id = a) then
    raise exception 'not_allowed';
  end if;
  return query
    select x.user_id, p.full_name, r.status, t.present, t.how
    from meeting_audience(p_meeting) x join profiles p on p.id = x.user_id
    left join meeting_rsvps r on r.meeting_id = p_meeting and r.user_id = x.user_id
    left join meeting_attendance t on t.meeting_id = p_meeting and t.user_id = x.user_id
    order by p.full_name;
end $$;

create function notify_meeting_reminders() returns void
language plpgsql security definer set search_path=public as $$
begin
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select am.association_id, x.user_id, 'meeting-reminder:' || am.id::text || ':' || am.starts_at::text, 'Meeting reminder',
    am.title || ' · ' || to_char(am.starts_at at time zone 'Asia/Kolkata', 'DD Mon, HH12:MI AM')
      || case when am.meeting_mode <> 'inPerson' then ' · join from Meetings' else '' end,
    '/meetings'
  from association_meetings am cross join lateral meeting_audience(am.id) x
  where am.starts_at between now() and now() + interval '24 hours'
  on conflict (association_id, user_id, event_key) do nothing;
end $$;
revoke execute on function notify_meeting_reminders() from public, anon, authenticated;

-- Vendor AMC renewals and asset warranty/AMC/validity expiries go to all EC members and office bearers.
create function notify_expiry_alerts() returns void
language plpgsql security definer set search_path=public as $$
declare ec app_role[] := array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[];
begin
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select c.association_id, m.user_id, 'vendor-amc-renewal:' || c.id::text || ':' || c.end_date::text, 'AMC renewal due',
    v.name || ' · ' || c.service_name || ' expires ' || to_char(c.end_date, 'DD Mon YYYY'), '/registers'
  from vendor_amc_contracts c
  join association_vendors v on v.id = c.vendor_id and v.association_id = c.association_id
  join memberships m on m.association_id = c.association_id and m.ended_at is null and m.role = any(ec)
  where c.active and v.active and c.end_date between current_date and current_date + c.renewal_notice_days
  on conflict (association_id, user_id, event_key) do nothing;

  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select i.association_id, m.user_id, 'register-expiry:' || i.id::text || ':' || k.kind || ':' || k.d::text,
    k.label || ' expiring', i.name || ' · ' || k.label || ' ends ' || to_char(k.d, 'DD Mon YYYY'), '/registers'
  from association_register_items i
  cross join lateral (values ('warranty', 'Warranty', i.warranty_end), ('amc', 'AMC', i.amc_end),
                             ('validity', 'Validity', i.expires_on)) k(kind, label, d)
  join memberships m on m.association_id = i.association_id and m.ended_at is null and m.role = any(ec)
  where i.status = 'active' and k.d between current_date and current_date + 30
  on conflict (association_id, user_id, event_key) do nothing;
end $$;
revoke execute on function notify_expiry_alerts() from public, anon, authenticated;

create table checklist_items (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  category text not null check (length(trim(category)) between 1 and 60),
  time_window text not null default '',
  proof_required boolean not null default false,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_by uuid default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table checklist_items enable row level security;
create policy checklist_items_read on checklist_items for select using (is_member(association_id));
create policy checklist_items_insert on checklist_items for insert
  with check (has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[]));
create policy checklist_items_update on checklist_items for update
  using (has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[]))
  with check (has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[]));

create table dues_reminders (
  association_id uuid not null references associations(id) on delete cascade,
  flat_id uuid not null references flats(id) on delete cascade,
  sent_on date not null default current_date,
  sent_by uuid not null references profiles(id),
  primary key (flat_id, sent_on)
);
alter table dues_reminders enable row level security;
create policy dues_reminders_read on dues_reminders for select using (fin_reader(association_id));

-- One reminder per flat per day; goes to the flat's owners as an in-app notification. Returns flats reminded.
create function send_dues_reminders(p_flats uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); f record; n integer := 0; pending integer;
begin
  if a is null or not has_role(a, array['admin','treasurer','joint_treasurer','secretary']::app_role[]) then
    raise exception 'not_allowed: only the Treasurer, Joint Treasurer or Secretary can send reminders';
  end if;
  for f in select id, number from flats where association_id = a and id = any(p_flats) loop
    select coalesce(sum(greatest(d.amount - coalesce((select sum(p.amount) from payments p where p.due_id = d.id), 0), 0)), 0)
      into pending from dues d where d.flat_id = f.id;
    continue when pending <= 0;
    insert into dues_reminders (association_id, flat_id, sent_by) values (a, f.id, auth.uid()) on conflict do nothing;
    continue when not found;
    insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
    select a, m.user_id, 'dues-reminder:' || f.id::text || ':' || current_date::text, 'Dues reminder',
      'Flat ' || f.number || ': ₹' || pending || ' pending. Please pay the Treasurer and check My dues.', '/dues'
    from memberships m where m.association_id = a and m.flat_id = f.id and m.role = 'owner' and m.ended_at is null
    on conflict (association_id, user_id, event_key) do nothing;
    n := n + 1;
  end loop;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'send_dues_reminders', 'dues', null, jsonb_build_object('flats', n));
  return n;
end $$;

create function notify_payment_receipt() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select new.association_id, m.user_id, 'payment-receipt:' || new.receipt_no, 'Payment received',
    'Receipt ' || new.receipt_no || ' · ₹' || new.amount || ' for flat ' || f.number || ' on ' || to_char(new.paid_on, 'DD Mon YYYY'),
    '/dues'
  from memberships m join flats f on f.id = new.flat_id
  where m.association_id = new.association_id and m.flat_id = new.flat_id and m.role = 'owner' and m.ended_at is null
  on conflict (association_id, user_id, event_key) do nothing;
  return new;
end $$;
create trigger payments_notify_receipt after insert on payments for each row execute function notify_payment_receipt();

-- Booked times for an amenity on a day (no personal details), so members can pick a free slot.
create function amenity_busy_slots(p_amenity uuid, p_day date)
returns table (starts_at timestamptz, ends_at timestamptz, status text)
language sql stable security definer set search_path=public as $$
  select b.starts_at, b.ends_at, b.status from amenity_bookings b join amenities am on am.id = b.amenity_id
  where b.amenity_id = p_amenity and am.association_id = my_association() and is_member(am.association_id)
    and b.status in ('pending','approved')
    and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_day::timestamp at time zone 'Asia/Kolkata',
                                                             (p_day + 1)::timestamp at time zone 'Asia/Kolkata', '[)')
  order by b.starts_at;
$$;

create extension if not exists pg_cron;
select cron.schedule('flatsphere-meeting-reminders', '5 * * * *', 'select public.notify_meeting_reminders()');
select cron.schedule('flatsphere-expiry-alerts', '30 2 * * *', 'select public.notify_expiry_alerts()');
