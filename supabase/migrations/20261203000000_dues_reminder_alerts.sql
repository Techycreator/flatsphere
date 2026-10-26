-- Reminder numbering and an owner-readable view of active reminders (kept until the dues are paid).
create function due_reminder_count(p_flat uuid) returns integer
language sql stable security definer set search_path=public as $$
  select count(*)::integer from dues_reminders r
  where r.flat_id=p_flat and r.sent_on >= coalesce((
    select min(d.created_at)::date from dues d
    where d.flat_id=p_flat and d.amount > coalesce((select sum(p.amount) from payments p where p.due_id=d.id),0)
  ), current_date+1);
$$;
revoke all on function due_reminder_count(uuid) from public, anon, authenticated;

create or replace function send_dues_reminders(p_flats uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); f record; n integer := 0; pending integer; seq integer;
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
    seq := due_reminder_count(f.id);
    insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
    select a, m.user_id, 'dues-reminder:' || f.id::text || ':' || current_date::text,
      case when seq <= 1 then 'Dues reminder' else 'Reminder ' || seq || ': dues still unpaid' end,
      'Flat ' || f.number || ': ₹' || pending || ' pending.'
        || case when seq > 1 then ' This is reminder ' || seq || ' from the association.' else '' end
        || ' Please pay the Treasurer and check My dues.', '/dues'
    from memberships m where m.association_id = a and m.flat_id = f.id and m.role = 'owner' and m.ended_at is null
    on conflict (association_id, user_id, event_key) do nothing;
    n := n + 1;
  end loop;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'send_dues_reminders', 'dues', null, jsonb_build_object('flats', n));
  return n;
end $$;

create function my_due_reminders()
returns table (flat_number text, pending integer, reminder_count integer, last_sent_on date)
language sql stable security definer set search_path=public as $$
  select x.number, x.pending, x.cnt, x.last_sent from (
    select f.number,
      (select coalesce(sum(greatest(d.amount - coalesce((select sum(p.amount) from payments p where p.due_id=d.id),0),0)),0)::integer
         from dues d where d.flat_id=f.id) as pending,
      due_reminder_count(f.id) as cnt,
      (select max(r.sent_on) from dues_reminders r where r.flat_id=f.id) as last_sent
    from flats f
    where f.association_id=my_association() and f.id in (select my_flat_ids(my_association()))
  ) x where x.pending>0 and x.cnt>0
  order by x.number;
$$;
revoke all on function my_due_reminders() from public, anon;
grant execute on function my_due_reminders() to authenticated;
