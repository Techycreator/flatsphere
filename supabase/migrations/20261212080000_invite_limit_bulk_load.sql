-- A one-time migration of a 100-flat association can need several hundred invites in a day.
create or replace function limit_invites_per_day() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if (select count(*) from invites where association_id = new.association_id and created_at > now() - interval '1 day') >= 400 then
    raise exception 'limit: at most 400 invites per day per association';
  end if;
  return new;
end $$;
