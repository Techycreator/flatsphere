-- Vehicle export carries flat occupancy so gate staff can export owner-occupied or rented flats separately.
drop function if exists export_vehicle_register();
create function export_vehicle_register()
returns table (registration_number text, vehicle_type text, flat_number text, parking_slot text, occupancy text)
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array[
    'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer',
    'ec_member','caretaker','security'
  ]::app_role[]) then
    raise exception 'not_allowed: vehicle export is limited to gate staff, office bearers and EC members';
  end if;
  return query
    select v.registration_number, v.vehicle_type, f.number, v.parking_slot, f.occupancy::text
    from flat_vehicles v
    join flats f on f.id = v.flat_id and f.association_id = a
    where v.association_id = a
    order by v.registration_number;
end $$;
revoke all on function export_vehicle_register() from public, anon;
grant execute on function export_vehicle_register() to authenticated;
