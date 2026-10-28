-- Read-only household staff list for office bearers, EC members and the caretaker; ID proofs stay with the flat's owner/resident.
create function household_staff_overview()
returns table (id uuid, flat_number text, full_name text, usual_in time, usual_out time, resides_in_flat boolean)
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array[
    'president','secretary','joint_secretary','vice_president','treasurer','ec_member','caretaker'
  ]::app_role[]) then
    raise exception 'not_allowed: household staff list is limited to office bearers, EC members and the caretaker';
  end if;
  return query
    select w.id, f.number, w.full_name, w.usual_in, w.usual_out, w.resides_in_flat
    from flat_housekeeping_workers w
    join flats f on f.id = w.flat_id and f.association_id = a
    where w.association_id = a and w.active
    order by f.number, w.full_name;
end $$;
revoke all on function household_staff_overview() from public, anon;
grant execute on function household_staff_overview() to authenticated;
