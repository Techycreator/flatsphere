alter table visitor_requests drop constraint if exists visitor_requests_other_purpose;
alter table visitor_requests add constraint visitor_requests_other_purpose
  check (entry_type <> 'other' or note ~ '[^[:space:]]') not valid;

drop function search_vehicle_contacts(text);
create function search_vehicle_contacts(p_vehicle_number text)
returns table (registration_number text, vehicle_type text, flat_number text, person_name text, phone text)
language plpgsql stable security definer set search_path = public as $$
declare
  a uuid := my_association();
  search_value text := regexp_replace(upper(coalesce(p_vehicle_number, '')), '[^A-Z0-9]', '', 'g');
begin
  if a is null or not has_role(a, array[
    'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer',
    'ec_member','caretaker','security'
  ]::app_role[]) then
    raise exception 'not_allowed: vehicle lookup is limited to gate staff, office bearers and EC members';
  end if;
  if length(search_value) < 3 then raise exception 'invalid: enter at least three characters'; end if;
  return query
    select s.registration_number, s.vehicle_type, s.flat_number, s.person_name, s.phone from (
      select v.registration_number, v.vehicle_type, f.number as flat_number, p.full_name as person_name,
             coalesce(m.contact_phone, p.mobile, inv.mobile) as phone,
             case m.role when 'owner' then 0 when 'resident' then 1 else 2 end as rank
      from flat_vehicles v
      join flats f on f.id = v.flat_id and f.association_id = a
      left join memberships m on m.flat_id = f.id and m.association_id = a and m.ended_at is null
        and m.role in ('owner','resident')
      left join profiles p on p.id = m.user_id
      left join lateral (
        select i.mobile from invites i
        where i.association_id = a and i.flat_id = f.id and i.role = m.role and lower(i.email) = lower(p.email)
        order by i.created_at desc limit 1
      ) inv on true
      where v.association_id = a
        and regexp_replace(upper(v.registration_number), '[^A-Z0-9]', '', 'g') like '%' || search_value || '%'
      union all
      (select distinct on (vr.vehicle_number, vr.flat_id, vr.meet_staff) vr.vehicle_number, 'visitor',
             coalesce(f.number, 'Staff: ' || vr.meet_staff),
             vr.guest_name || ' (visitor of ' || coalesce(vr.host_name, 'resident') || ')', vr.guest_phone, 3
       from visitor_requests vr
       left join flats f on f.id = vr.flat_id and f.association_id = a
       where vr.association_id = a and vr.vehicle_number is not null and vr.status <> 'cancelled'
         and regexp_replace(upper(vr.vehicle_number), '[^A-Z0-9]', '', 'g') like '%' || search_value || '%'
       order by vr.vehicle_number, vr.flat_id, vr.meet_staff, vr.expected_arrival desc)
    ) s
    order by s.flat_number, s.rank, s.person_name;
end $$;
revoke all on function search_vehicle_contacts(text) from public;
grant execute on function search_vehicle_contacts(text) to authenticated;
