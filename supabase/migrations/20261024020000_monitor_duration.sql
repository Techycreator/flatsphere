-- Monitor assignments have a period and record who assigned them.
alter table memberships add column monitor_from date, add column monitor_until date, add column assigned_by text;
alter table invites add column monitor_from date, add column monitor_until date, add column assigned_by text;

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
                           monitor_from, monitor_until, assigned_by)
    select association_id, new.id, role, flat_id, designations, monitor_categories, monitor_from, monitor_until, assigned_by
    from invites where lower(email) = lower(new.email) and claimed_at is null;
  update invites set claimed_at = now() where lower(email) = lower(new.email) and claimed_at is null;
  return new;
end $$;

drop function directory();
create function directory()
returns table (kind text, id uuid, full_name text, email text, mobile text, role app_role, flat_number text,
               designations text[], monitor_categories text[], monitor_from date, monitor_until date,
               assigned_by text, since timestamptz)
language sql stable security definer set search_path = public as $$
  select 'member', m.id, p.full_name, p.email, p.mobile, m.role, f.number, m.designations, m.monitor_categories,
         m.monitor_from, m.monitor_until, m.assigned_by, m.started_at
  from memberships m join profiles p on p.id = m.user_id left join flats f on f.id = m.flat_id
  where m.association_id = my_association() and m.ended_at is null and can_manage_members(m.association_id)
  union all
  select 'invited', i.id, i.full_name, i.email, i.mobile, i.role, f.number, i.designations, i.monitor_categories,
         i.monitor_from, i.monitor_until, i.assigned_by, i.created_at
  from invites i left join flats f on f.id = i.flat_id
  where i.association_id = my_association() and i.claimed_at is null and can_manage_members(i.association_id)
$$;

create function assigner_label(a uuid) returns text
language sql stable security definer set search_path = public as $$
  select p.full_name || coalesce(' (' || (
    select initcap(replace(m.role::text, '_', ' ')) from memberships m
    where m.user_id = p.id and m.association_id = a and m.ended_at is null
      and m.role in ('president','secretary','joint_secretary','admin')
    order by array_position(array['president','secretary','joint_secretary','admin']::app_role[], m.role) limit 1) || ')', '')
  from profiles p where p.id = auth.uid();
$$;

drop function set_member_details(text, uuid, text[], text[]);
create function set_member_details(p_kind text, p_id uuid, p_designations text[], p_monitor_categories text[],
                                   p_from date default null, p_until date default null)
returns void language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); who text;
begin
  if a is null or not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can change designations or monitor areas';
  end if;
  if p_until is not null and p_from is not null and p_until < p_from then
    raise exception 'invalid: the end date must be after the start date';
  end if;
  who := assigner_label(a);
  if p_kind = 'member' then
    update memberships set designations = coalesce(p_designations, '{}'),
      monitor_categories = coalesce(p_monitor_categories, '{}'), monitor_from = p_from, monitor_until = p_until,
      assigned_by = case when cardinality(coalesce(p_monitor_categories, '{}')) > 0 then who end
      where id = p_id and association_id = a and ended_at is null;
  else
    update invites set designations = coalesce(p_designations, '{}'),
      monitor_categories = coalesce(p_monitor_categories, '{}'), monitor_from = p_from, monitor_until = p_until,
      assigned_by = case when cardinality(coalesce(p_monitor_categories, '{}')) > 0 then who end
      where id = p_id and association_id = a and claimed_at is null;
  end if;
  if not found then raise exception 'not_found'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'set_member_details', p_kind, p_id::text,
            jsonb_build_object('designations', p_designations, 'monitor_categories', p_monitor_categories,
                               'from', p_from, 'until', p_until));
end $$;

drop function add_member(text, text, text, app_role, text, text[]);
create function add_member(p_full_name text, p_email text, p_mobile text, p_role app_role, p_flat text,
                           p_designations text[] default '{}', p_monitor_categories text[] default '{}',
                           p_from date default null, p_until date default null)
returns text language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); fid uuid; uid uuid; e text := lower(trim(p_email)); res text; who text;
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
  end if;
  who := case when cardinality(coalesce(p_monitor_categories, '{}')) > 0 then assigner_label(a) end;
  select id into uid from profiles where lower(email) = e;
  if uid is not null then
    if exists (select 1 from memberships where association_id = a and user_id = uid and role = p_role
               and flat_id is not distinct from fid and ended_at is null) then
      raise exception 'duplicate: this person already has that role';
    end if;
    insert into memberships (association_id, user_id, role, flat_id, designations, monitor_categories,
                             monitor_from, monitor_until, assigned_by)
      values (a, uid, p_role, fid, coalesce(p_designations, '{}'), coalesce(p_monitor_categories, '{}'),
              p_from, p_until, who);
    res := 'member';
  else
    if exists (select 1 from invites where association_id = a and lower(email) = e and role = p_role
               and flat_id is not distinct from fid and claimed_at is null) then
      raise exception 'duplicate: this person is already invited with that role';
    end if;
    insert into invites (association_id, email, full_name, mobile, role, flat_id, designations, monitor_categories,
                         monitor_from, monitor_until, assigned_by, invited_by)
      values (a, e, trim(p_full_name), nullif(trim(p_mobile), ''), p_role, fid, coalesce(p_designations, '{}'),
              coalesce(p_monitor_categories, '{}'), p_from, p_until, who, auth.uid());
    res := 'invited';
  end if;
  if p_role = 'resident' then
    update flats set occupancy = 'rented' where id = fid and occupancy = 'vacant';
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'add_member', 'membership', e,
            jsonb_build_object('role', p_role, 'flat', p_flat, 'result', res));
  return res;
end $$;
