-- Vehicle (boom barrier) export is limited to the six roles that may export, enforced in the database.
create or replace function export_vehicle_register()
returns table (
  registration_number text,
  vehicle_type text,
  flat_number text,
  parking_slot text
) language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array[
    'president','secretary','joint_secretary','vice_president','treasurer','ec_member'
  ]::app_role[]) then
    raise exception 'not_allowed: vehicle export is limited to the President, Vice President, Secretary, Joint Secretary, Treasurer and EC members';
  end if;
  return query
    select v.registration_number, v.vehicle_type, f.number, v.parking_slot
    from flat_vehicles v
    join flats f on f.id = v.flat_id and f.association_id = a
    where v.association_id = a
    order by v.registration_number;
end $$;
revoke all on function export_vehicle_register() from public, anon;
grant execute on function export_vehicle_register() to authenticated;
