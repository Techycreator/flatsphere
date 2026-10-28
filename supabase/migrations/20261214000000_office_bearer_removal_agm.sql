-- Removing an office bearer also needs approved AGM (General Body) minutes linked as the MOM.
drop function if exists revoke_member_role(text, uuid, text);
drop function if exists revoke_member_role(text, uuid, text, text);
create function revoke_member_role(p_kind text, p_id uuid, p_reason text, p_mom_ref text default null) returns text
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); m memberships; rid uuid; who text; label text; asker text;
begin
  if length(trim(coalesce(p_reason, ''))) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'invalid: enter a reason of 3 to 300 characters';
  end if;
  if p_kind = 'member' then
    select * into m from memberships where id = p_id and association_id = a and ended_at is null;
    if m.id is not null and m.role::text in ('president','secretary','vice_president','joint_secretary','treasurer','joint_treasurer',
                                             'caretaker','admin','auditor','security') then
      if not has_role(a, array['admin','president','secretary']::app_role[]) then
        raise exception 'not_allowed: only the Admin, President or Secretary can remove a member';
      end if;
      if m.user_id = auth.uid() then raise exception 'not_allowed: you cannot remove your own role'; end if;
      if exists (select 1 from role_removal_requests where membership_id = m.id and status = 'pending') then
        raise exception 'invalid: removal of this role is already waiting for approval';
      end if;
      if m.role::text in ('president','secretary','vice_president','joint_secretary','treasurer','joint_treasurer')
         and not exists (select 1 from association_meetings am
                         where am.association_id = a and am.meeting_type = 'General Body' and am.minutes_status = 'approved'
                           and position(am.title in coalesce(p_mom_ref, '')) = 1) then
        raise exception 'invalid: removing an office bearer needs the approved AGM / General Body minutes (MOM)';
      end if;
      select full_name into who from profiles where id = m.user_id;
      label := initcap(replace(m.role::text, '_', ' '));
      asker := case when has_role(a, array['president']::app_role[]) then 'president'
                    when has_role(a, array['secretary']::app_role[]) then 'secretary' else 'admin' end;
      insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role,
        category, mom_required, mom_ref, high_risk)
      values (a, 'APR-' || upper(substr(md5(random()::text), 1, 10)), 'W26', 'Remove role – ' || label || ': ' || coalesce(who, ''),
        jsonb_build_object('Person', coalesce(who, ''), 'Role to remove', label, 'Reason', trim(p_reason),
                           'Other roles', 'Not affected'),
        auth.uid(), coalesce(my_name(), ''), asker::app_role, 'Committee', p_mom_ref is not null, nullif(trim(coalesce(p_mom_ref, '')), ''), false)
      returning id into rid;
      if asker = 'president' then
        insert into approval_steps (request_id, seq, role, name) values (rid, 1, 'vice_president', 'Vice President (for President)');
      else
        insert into approval_steps (request_id, seq, role, name) values (rid, 1, 'president', 'President');
      end if;
      insert into role_removal_requests (approval_request_id, association_id, membership_id, reason)
      values (rid, a, m.id, trim(p_reason));
      insert into audit_log (association_id, actor, action, entity, entity_id, after)
      values (a, auth.uid(), 'request_role_removal', 'membership', m.id::text,
              jsonb_build_object('role', m.role, 'reason', trim(p_reason)));
      return 'pending_approval';
    end if;
  end if;
  perform remove_member(p_kind, p_id);
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'revoke_role_reason', 'membership', p_id::text, jsonb_build_object('kind', p_kind, 'reason', trim(p_reason)));
  return 'removed';
end $$;
revoke all on function revoke_member_role(text, uuid, text, text) from public, anon;
grant execute on function revoke_member_role(text, uuid, text, text) to authenticated;

