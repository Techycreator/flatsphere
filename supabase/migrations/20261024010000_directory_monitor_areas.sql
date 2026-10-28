-- Flats default to the caller's association; managers assign monitor areas.
alter table flats alter column association_id set default my_association();

drop function directory();
create function directory()
returns table (kind text, id uuid, full_name text, email text, mobile text, role app_role, flat_number text,
               designations text[], monitor_categories text[], since timestamptz)
language sql stable security definer set search_path = public as $$
  select 'member', m.id, p.full_name, p.email, p.mobile, m.role, f.number, m.designations, m.monitor_categories, m.started_at
  from memberships m join profiles p on p.id = m.user_id left join flats f on f.id = m.flat_id
  where m.association_id = my_association() and m.ended_at is null and can_manage_members(m.association_id)
  union all
  select 'invited', i.id, i.full_name, i.email, i.mobile, i.role, f.number, i.designations, i.monitor_categories, i.created_at
  from invites i left join flats f on f.id = i.flat_id
  where i.association_id = my_association() and i.claimed_at is null and can_manage_members(i.association_id)
$$;

create function set_member_details(p_kind text, p_id uuid, p_designations text[], p_monitor_categories text[])
returns void language plpgsql security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can change designations or monitor areas';
  end if;
  if p_kind = 'member' then
    update memberships set designations = coalesce(p_designations, '{}'), monitor_categories = coalesce(p_monitor_categories, '{}')
      where id = p_id and association_id = a and ended_at is null;
  else
    update invites set designations = coalesce(p_designations, '{}'), monitor_categories = coalesce(p_monitor_categories, '{}')
      where id = p_id and association_id = a and claimed_at is null;
  end if;
  if not found then raise exception 'not_found'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'set_member_details', p_kind, p_id::text,
            jsonb_build_object('designations', p_designations, 'monitor_categories', p_monitor_categories));
end $$;
