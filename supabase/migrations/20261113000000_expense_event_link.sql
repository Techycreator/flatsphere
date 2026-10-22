alter table expenses add column event_id uuid references community_events(id) on delete set null;

create function validate_expense_event_association() returns trigger
language plpgsql set search_path=public as $$
begin
  if new.event_id is not null and not exists (
    select 1 from community_events e
    where e.id=new.event_id and e.association_id=new.association_id
  ) then
    raise exception 'invalid: selected event is not in this association';
  end if;
  return new;
end $$;
create trigger expenses_validate_event before insert or update of event_id,association_id on expenses
  for each row execute function validate_expense_event_association();

create index expenses_event_approved_idx on expenses(association_id,event_id)
  where event_id is not null and status='approved';
