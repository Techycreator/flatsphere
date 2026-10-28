-- Removing a committee/staff role (President, Secretary, VP, Joint Secretary, Treasurer, Caretaker, Admin,
-- Auditor, Security) needs President approval (Vice President when the President asks). Other roles end at once.
create table role_removal_requests (
  approval_request_id uuid primary key references approval_requests(id) on delete cascade,
  association_id uuid not null references associations(id) on delete cascade,
  membership_id uuid not null references memberships(id) on delete cascade,
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected'))
);
alter table role_removal_requests enable row level security;

drop function if exists revoke_member_role(text, uuid, text);
create function revoke_member_role(p_kind text, p_id uuid, p_reason text) returns text
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); m memberships; rid uuid; who text; label text; asker text;
begin
  if length(trim(coalesce(p_reason, ''))) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'invalid: enter a reason of 3 to 300 characters';
  end if;
  if p_kind = 'member' then
    select * into m from memberships where id = p_id and association_id = a and ended_at is null;
    if m.id is not null and m.role::text in ('president','secretary','vice_president','joint_secretary','treasurer',
                                             'caretaker','admin','auditor','security') then
      if not has_role(a, array['admin','president','secretary']::app_role[]) then
        raise exception 'not_allowed: only the Admin, President or Secretary can remove a member';
      end if;
      if m.user_id = auth.uid() then raise exception 'not_allowed: you cannot remove your own role'; end if;
      if exists (select 1 from role_removal_requests where membership_id = m.id and status = 'pending') then
        raise exception 'invalid: removal of this role is already waiting for approval';
      end if;
      select full_name into who from profiles where id = m.user_id;
      label := initcap(replace(m.role::text, '_', ' '));
      asker := case when has_role(a, array['president']::app_role[]) then 'president'
                    when has_role(a, array['secretary']::app_role[]) then 'secretary' else 'admin' end;
      insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role,
        category, mom_required, high_risk)
      values (a, 'APR-' || upper(substr(md5(random()::text), 1, 10)), 'W26', 'Remove role – ' || label || ': ' || coalesce(who, ''),
        jsonb_build_object('Person', coalesce(who, ''), 'Role to remove', label, 'Reason', trim(p_reason),
                           'Other roles', 'Not affected'),
        auth.uid(), coalesce(my_name(), ''), asker::app_role, 'Committee', false, false)
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
revoke all on function revoke_member_role(text, uuid, text) from public, anon;
grant execute on function revoke_member_role(text, uuid, text) to authenticated;

create function sync_role_removal_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; q role_removal_requests;
begin
  if old.decision is not distinct from new.decision or new.decision = 'pending' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.code <> 'W26' then return new; end if;
  select * into q from role_removal_requests where approval_request_id = r.id and status = 'pending';
  if q.approval_request_id is null then return new; end if;
  if new.decision = 'approved' then
    if exists (select 1 from approval_steps where request_id = r.id and decision = 'pending') then return new; end if;
    update memberships set ended_at = now() where id = q.membership_id and ended_at is null;
    update role_removal_requests set status = 'approved' where approval_request_id = r.id;
    insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (q.association_id, new.decided_by, 'remove_member', 'member', q.membership_id::text, jsonb_build_object('approved_request', r.ref));
  elsif new.decision = 'rejected' then
    update role_removal_requests set status = 'rejected' where approval_request_id = r.id;
  end if;
  return new;
end $$;
create trigger approval_steps_role_removal after update of decision on approval_steps
  for each row execute function sync_role_removal_approval();
