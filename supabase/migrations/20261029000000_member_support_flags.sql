alter table memberships add column support_flags text[] not null default '{}';
alter table invites add column support_flags text[] not null default '{}';
alter table memberships add constraint memberships_support_flags_valid
  check (support_flags <@ array['child','senior_citizen','wheelchair_assisted']::text[]);
alter table invites add constraint invites_support_flags_valid
  check (support_flags <@ array['child','senior_citizen','wheelchair_assisted']::text[]);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare n text; mob text;
begin
  select full_name, mobile into n, mob from invites
    where lower(email) = lower(new.email) and claimed_at is null order by mobile nulls last limit 1;
  if n is null then raise exception 'not_invited: this email has not been invited by an association'; end if;
  if exists (select 1 from profiles where mobile = mob) then mob := null; end if;
  insert into profiles (id, full_name, email, mobile) values (new.id, n, new.email, mob);
  insert into memberships (association_id, user_id, role, flat_id, designations, monitor_categories,
                           monitor_from, monitor_until, assigned_by, support_flags)
    select association_id, new.id, role, flat_id, designations, monitor_categories,
           monitor_from, monitor_until, assigned_by, support_flags
    from invites where lower(email) = lower(new.email) and claimed_at is null;
  update invites set claimed_at = now() where lower(email) = lower(new.email) and claimed_at is null;
  return new;
end $$;

drop function add_member(text, text, text, app_role, text, text[], text[], date, date);
create function add_member(
  p_full_name text,
  p_email text,
  p_mobile text,
  p_role app_role,
  p_flat text,
  p_designations text[] default '{}',
  p_monitor_categories text[] default '{}',
  p_from date default null,
  p_until date default null,
  p_support_flags text[] default '{}'
) returns text language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  fid uuid;
  uid uuid;
  e text := lower(trim(p_email));
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
                             monitor_from, monitor_until, assigned_by, support_flags)
      values (a, uid, p_role, fid, coalesce(p_designations, '{}'), coalesce(p_monitor_categories, '{}'),
              p_from, p_until, who, coalesce(p_support_flags, '{}'));
    res := 'member';
  else
    if exists (select 1 from invites where association_id = a and lower(email) = e and role = p_role
               and flat_id is not distinct from fid and claimed_at is null) then
      raise exception 'duplicate: this person is already invited with that role';
    end if;
    insert into invites (association_id, email, full_name, mobile, role, flat_id, designations, monitor_categories,
                         monitor_from, monitor_until, assigned_by, invited_by, support_flags)
      values (a, e, trim(p_full_name), nullif(trim(p_mobile), ''), p_role, fid, coalesce(p_designations, '{}'),
              coalesce(p_monitor_categories, '{}'), p_from, p_until, who, auth.uid(), coalesce(p_support_flags, '{}'));
    res := 'invited';
  end if;
  if p_role = 'resident' then update flats set occupancy = 'rented' where id = fid and occupancy = 'vacant'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'add_member', 'membership', e,
      jsonb_build_object('role', p_role, 'flat', p_flat, 'result', res, 'support_flags', p_support_flags));
  return res;
end $$;

drop function directory();
create function directory()
returns table (
  kind text, id uuid, full_name text, email text, mobile text, role app_role, flat_number text,
  designations text[], monitor_categories text[], monitor_from date, monitor_until date,
  assigned_by text, support_flags text[], since timestamptz
)
language sql stable security definer set search_path = public as $$
    select 'member', m.id, p.full_name, p.email, p.mobile, m.role, f.number, m.designations, m.monitor_categories,
      m.monitor_from, m.monitor_until, m.assigned_by,
      case when has_role(m.association_id, array['president','secretary']::app_role[]) then m.support_flags else '{}'::text[] end,
      m.started_at
  from memberships m join profiles p on p.id = m.user_id left join flats f on f.id = m.flat_id
  where m.association_id = my_association() and m.ended_at is null and can_manage_members(m.association_id)
  union all
    select 'invited', i.id, i.full_name, i.email, i.mobile, i.role, f.number, i.designations, i.monitor_categories,
      i.monitor_from, i.monitor_until, i.assigned_by,
      case when has_role(i.association_id, array['president','secretary']::app_role[]) then i.support_flags else '{}'::text[] end,
      i.created_at
  from invites i left join flats f on f.id = i.flat_id
  where i.association_id = my_association() and i.claimed_at is null and can_manage_members(i.association_id)
$$;