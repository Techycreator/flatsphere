-- Clients send only flat_number; derive flat_id so owners/residents of that flat can see non-private tickets.
create function set_complaint_flat_id() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.flat_id := (select id from flats where association_id = new.association_id and number = new.flat_number);
  return new;
end $$;

create trigger complaints_set_flat_id before insert or update of flat_number on complaints
  for each row execute function set_complaint_flat_id();

update complaints c set flat_id = f.id from flats f
where f.association_id = c.association_id and f.number = c.flat_number and c.flat_id is distinct from f.id;
