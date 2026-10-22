alter table membership_changes
  add constraint membership_changes_incoming_mobile_required
  check (incoming_mobile is not null and incoming_mobile ~ '^[+0-9() -]{5,24}$') not valid;

update memberships m
set contact_phone = coalesce(
  (select nullif(trim(i.mobile), '') from invites i
   join profiles p on lower(p.email) = lower(i.email)
   where i.association_id = m.association_id and i.flat_id is not distinct from m.flat_id
     and i.role = m.role and p.id = m.user_id and i.mobile is not null
   order by i.claimed_at desc nulls last, i.created_at desc limit 1),
  p.mobile
)
from profiles p
where p.id = m.user_id and m.role in ('owner','resident') and m.contact_phone is null;

drop function add_member(text,text,text,app_role,text,text[],text[],date,date,text[]);
create or replace function add_member(
  p_full_name text,
  p_email text,
  p_mobile text,
  p_role app_role,
  p_flat text,
  p_designations text[] default '{}',
  p_monitor_categories text[] default '{}',
  p_from date default null,
  p_until date default null,
  p_support_flags text[] default '{}',
  p_birth_date date default null
) returns text language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  fid uuid;
  uid uuid;
  e text := lower(trim(p_email));
  mobile_value text := trim(coalesce(p_mobile, ''));
  res text;
  who text;
begin
  if a is null or not can_manage_members(a) then raise exception 'not_allowed'; end if;
  if p_role not in ('owner','resident')
     and not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can assign committee or staff roles';
  end if;
  if coalesce(trim(p_full_name), '') = '' or e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid: name and a valid email are required';
  end if;
  if p_until is not null and p_from is not null and p_until < p_from then
    raise exception 'invalid: the end date must be after the start date';
  end if;
  if p_role in ('owner','resident') then
    if mobile_value !~ '^[+0-9() -]{5,24}$' then raise exception 'invalid: a valid owner/resident phone number is required'; end if;
    if p_birth_date > current_date then raise exception 'invalid: date of birth cannot be in the future'; end if;
    select id into fid from flats where association_id = a and number = p_flat;
    if fid is null then raise exception 'invalid: choose a flat for an owner or resident'; end if;
  elsif cardinality(coalesce(p_support_flags, '{}')) > 0 then
    raise exception 'invalid: support flags are only available for owners and residents';
  end if;
  if not coalesce(p_support_flags, '{}') <@ array['child','senior_citizen','wheelchair_assisted']::text[] then
    raise exception 'invalid: unsupported member classification';
  end if;
  who := case when cardinality(coalesce(p_monitor_categories, '{}')) > 0 then assigner_label(a) end;
  select id into uid from profiles where lower(email) = e;
  if uid is not null then
    if exists (select 1 from memberships where association_id = a and user_id = uid and role = p_role
               and flat_id is not distinct from fid and ended_at is null) then
      raise exception 'duplicate: this person already has that role';
    end if;
    insert into memberships (association_id, user_id, role, flat_id, designations, monitor_categories,
                 monitor_from, monitor_until, assigned_by, support_flags, contact_phone, date_of_birth)
      values (a, uid, p_role, fid, coalesce(p_designations, '{}'), coalesce(p_monitor_categories, '{}'),
              p_from, p_until, who, coalesce(p_support_flags, '{}'),
          case when p_role in ('owner','resident') then mobile_value else null end,
          case when p_role in ('owner','resident') then p_birth_date else null end);
    res := 'member';
  else
    if exists (select 1 from invites where association_id = a and lower(email) = e and role = p_role
               and flat_id is not distinct from fid and claimed_at is null) then
      raise exception 'duplicate: this person is already invited with that role';
    end if;
    insert into invites (association_id, email, full_name, mobile, role, flat_id, designations, monitor_categories,
               monitor_from, monitor_until, assigned_by, invited_by, support_flags, date_of_birth)
      values (a, e, trim(p_full_name), nullif(mobile_value, ''), p_role, fid, coalesce(p_designations, '{}'),
          coalesce(p_monitor_categories, '{}'), p_from, p_until, who, auth.uid(), coalesce(p_support_flags, '{}'),
          case when p_role in ('owner','resident') then p_birth_date else null end);
    res := 'invited';
  end if;
  if p_role = 'resident' then update flats set occupancy = 'rented' where id = fid and occupancy = 'vacant'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'add_member', 'membership', e,
      jsonb_build_object('role', p_role, 'flat', p_flat, 'result', res, 'support_flags', p_support_flags));
  return res;
end $$;

create function require_membership_contact_phone() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  invited_phone text;
begin
  if new.role in ('owner','resident') then
    if new.contact_phone is null then
      select nullif(trim(i.mobile), '') into invited_phone
      from invites i
      join profiles p on lower(p.email) = lower(i.email)
      where i.association_id = new.association_id and i.flat_id is not distinct from new.flat_id
        and i.role = new.role and p.id = new.user_id
      order by i.created_at desc
      limit 1;
      new.contact_phone := invited_phone;
    end if;
    if coalesce(new.contact_phone, '') !~ '^[+0-9() -]{5,24}$' then
      raise exception 'invalid: a valid phone number is required for every owner or resident';
    end if;
  end if;
  return new;
end $$;
create trigger memberships_require_contact_phone before insert on memberships
  for each row execute function require_membership_contact_phone();

drop function directory();
create function directory()
returns table (
  kind text, id uuid, full_name text, email text, mobile text, role app_role, flat_number text,
  designations text[], monitor_categories text[], monitor_from date, monitor_until date,
  assigned_by text, support_flags text[], since timestamptz, date_of_birth date
)
language sql stable security definer set search_path = public as $$
  select 'member', m.id, p.full_name, p.email, coalesce(m.contact_phone, p.mobile), m.role, f.number,
    m.designations, m.monitor_categories, m.monitor_from, m.monitor_until, m.assigned_by,
    case when has_role(m.association_id, array['president','secretary']::app_role[]) then m.support_flags else '{}'::text[] end,
    m.started_at, m.date_of_birth
  from memberships m join profiles p on p.id = m.user_id left join flats f on f.id = m.flat_id
  where m.association_id = my_association() and m.ended_at is null and can_manage_members(m.association_id)
  union all
  select 'invited', i.id, i.full_name, i.email, i.mobile, i.role, f.number, i.designations,
    i.monitor_categories, i.monitor_from, i.monitor_until, i.assigned_by,
    case when has_role(i.association_id, array['president','secretary']::app_role[]) then i.support_flags else '{}'::text[] end,
    i.created_at, i.date_of_birth
  from invites i left join flats f on f.id = i.flat_id
  where i.association_id = my_association() and i.claimed_at is null and can_manage_members(i.association_id)
$$;

create function search_vehicle_contacts(p_vehicle_number text)
returns table (
  registration_number text,
  vehicle_type text,
  flat_number text,
  person_name text,
  phone text
) language plpgsql stable security definer set search_path = public as $$
declare
  a uuid := my_association();
  search_value text := regexp_replace(upper(trim(coalesce(p_vehicle_number, ''))), '\s+', '', 'g');
begin
  if a is null or not has_role(a, array[
    'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer',
    'ec_member','caretaker','security'
  ]::app_role[]) then
    raise exception 'not_allowed: vehicle lookup is limited to gate staff, office bearers and EC members';
  end if;
  if length(search_value) < 3 then raise exception 'invalid: enter at least three characters'; end if;
  return query
    select v.registration_number, v.vehicle_type, f.number, p.full_name, coalesce(m.contact_phone, p.mobile, inv.mobile)
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
      and regexp_replace(upper(v.registration_number), '\s+', '', 'g') like '%' || search_value || '%'
    order by f.number, case m.role when 'owner' then 0 when 'resident' then 1 else 2 end, p.full_name;
end $$;
revoke all on function search_vehicle_contacts(text) from public;
grant execute on function search_vehicle_contacts(text) to authenticated;

create function export_vehicle_register()
returns table (
  registration_number text,
  vehicle_type text,
  flat_number text,
  parking_slot text
) language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array[
    'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer',
    'ec_member','caretaker','security'
  ]::app_role[]) then
    raise exception 'not_allowed: vehicle export is limited to gate staff, office bearers and EC members';
  end if;
  return query
    select v.registration_number, v.vehicle_type, f.number, v.parking_slot
    from flat_vehicles v
    join flats f on f.id = v.flat_id and f.association_id = a
    where v.association_id = a
    order by v.registration_number;
end $$;
revoke all on function export_vehicle_register() from public;
grant execute on function export_vehicle_register() to authenticated;
