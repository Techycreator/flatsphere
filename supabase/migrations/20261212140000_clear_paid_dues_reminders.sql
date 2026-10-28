-- Reminder notifications disappear once the flat has nothing pending.
create function clear_paid_dues_reminders(p_assoc uuid, p_flat uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pending numeric;
begin
  select coalesce(sum(greatest(d.amount - coalesce((select sum(p.amount) from payments p where p.due_id = d.id), 0), 0)), 0)
    into pending from dues d where d.flat_id = p_flat;
  if pending <= 0 then
    delete from app_notifications where association_id = p_assoc and event_key like 'dues-reminder:' || p_flat::text || ':%';
  end if;
end $$;
revoke all on function clear_paid_dues_reminders(uuid, uuid) from public, anon, authenticated;

create function trg_clear_dues_reminders() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform clear_paid_dues_reminders(new.association_id, new.flat_id);
  return new;
end $$;
create trigger payments_clear_reminders after insert on payments
  for each row execute function trg_clear_dues_reminders();

-- One-off clean-up of reminders already left behind.
do $$
declare f record;
begin
  for f in select distinct association_id, flat_id from dues loop
    perform clear_paid_dues_reminders(f.association_id, f.flat_id);
  end loop;
end $$;
