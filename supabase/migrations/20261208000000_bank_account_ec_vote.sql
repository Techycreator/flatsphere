-- EC vote steps, association bank account with Treasurer-raised change requests (W3), 48-hour activation.

alter table approval_steps add column step_type text not null default 'approval'
  check (step_type in ('approval', 'ec_vote'));

alter table workflow_type_steps drop constraint if exists workflow_type_steps_action_type_check;
alter table workflow_type_steps add constraint workflow_type_steps_action_type_check
  check (action_type in ('approval', 'cooling_period', 'execute', 'notification', 'ec_vote'));

create table ec_votes (
  id bigint generated always as identity primary key,
  request_id uuid not null references approval_requests(id) on delete cascade,
  voter uuid not null references profiles(id),
  voter_name text not null,
  vote text not null check (vote in ('yes', 'no')),
  comment text,
  voted_at timestamptz not null default now(),
  unique (request_id, voter)
);
alter table ec_votes enable row level security;

-- The EC is the EC members plus the office bearers; the person who raised the request is excluded.
create function ec_voter_ids(p_assoc uuid, p_exclude uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct m.user_id from memberships m
  where m.association_id = p_assoc and m.ended_at is null
    and m.role in ('ec_member', 'president', 'vice_president', 'secretary', 'joint_secretary', 'treasurer', 'joint_treasurer')
    and m.user_id is distinct from p_exclude;
$$;
revoke all on function ec_voter_ids(uuid, uuid) from public, anon, authenticated;

create function guard_ec_vote_step() returns trigger language plpgsql as $$
begin
  if old.step_type = 'ec_vote' and new.decision is distinct from old.decision
     and coalesce(current_setting('flatsphere.ec_vote', true), '') <> '1' then
    raise exception 'ec_vote: this step is decided by the EC vote';
  end if;
  return new;
end $$;
create trigger approval_step_guard_ec_vote before update of decision on approval_steps
  for each row execute function guard_ec_vote_step();

create function ec_vote_summary(p_request uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r approval_requests; s approval_steps; total integer; y integer; n integer; mine text; open_now boolean;
begin
  select * into r from approval_requests where id = p_request;
  if r.id is null or r.association_id is distinct from my_association() then raise exception 'not_found: request not found'; end if;
  if r.initiator is distinct from auth.uid() and not has_role(r.association_id,
      array['admin','president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer','ec_member']::app_role[]) then
    raise exception 'not_allowed: committee access required';
  end if;
  select count(*) into total from ec_voter_ids(r.association_id, r.initiator);
  select count(*) filter (where vote = 'yes'), count(*) filter (where vote = 'no') into y, n from ec_votes where request_id = p_request;
  select vote into mine from ec_votes where request_id = p_request and voter = auth.uid();
  select * into s from approval_steps where request_id = p_request and decision = 'pending' order by seq limit 1;
  open_now := s.id is not null and s.step_type = 'ec_vote';
  return jsonb_build_object(
    'total', total, 'yes', y, 'no', n, 'needed', total / 2 + 1, 'my_vote', mine, 'open', open_now,
    'can_vote', open_now and mine is null and exists (select 1 from ec_voter_ids(r.association_id, r.initiator) u where u = auth.uid()),
    'votes', (select coalesce(jsonb_agg(jsonb_build_object('name', voter_name, 'vote', vote, 'comment', comment) order by voted_at), '[]'::jsonb)
              from ec_votes where request_id = p_request));
end $$;
revoke all on function ec_vote_summary(uuid) from public, anon;
grant execute on function ec_vote_summary(uuid) to authenticated;

create function cast_ec_vote(p_request uuid, p_vote text, p_comment text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r approval_requests; s approval_steps; v uuid := auth.uid(); total integer; y integer; n integer; need integer; verdict text;
begin
  if p_vote not in ('yes', 'no') then raise exception 'invalid: vote must be yes or no'; end if;
  select * into r from approval_requests where id = p_request for update;
  if r.id is null or r.association_id is distinct from my_association() then raise exception 'not_found: request not found'; end if;
  select * into s from approval_steps where request_id = p_request and decision = 'pending' order by seq limit 1 for update;
  if s.id is null or s.step_type <> 'ec_vote' then
    raise exception 'not_open: the EC vote opens after the earlier approval steps';
  end if;
  if r.mom_required and coalesce(trim(r.mom_ref), '') = '' then
    raise exception 'invalid: link the MOM before the EC vote';
  end if;
  if v = r.initiator then raise exception 'not_allowed: the person who raised this request cannot vote'; end if;
  if not exists (select 1 from ec_voter_ids(r.association_id, r.initiator) u where u = v) then
    raise exception 'not_allowed: only EC members can vote';
  end if;
  insert into ec_votes (request_id, voter, voter_name, vote, comment)
  values (p_request, v, coalesce(my_name(), 'EC member'), p_vote, nullif(trim(coalesce(p_comment, '')), ''))
  on conflict (request_id, voter) do nothing;
  if not found then raise exception 'invalid: you have already voted'; end if;

  select count(*) into total from ec_voter_ids(r.association_id, r.initiator);
  select count(*) filter (where vote = 'yes'), count(*) filter (where vote = 'no') into y, n from ec_votes where request_id = p_request;
  need := total / 2 + 1;
  verdict := case when y >= need then 'approved' when n > total - need then 'rejected' end;
  if verdict is not null then
    perform set_config('flatsphere.ec_vote', '1', true);
    update approval_steps set decision = verdict::decision, decided_by = v, decided_by_name = 'EC vote',
      comment = format('EC %s Yes, %s No of %s - EC %s', y, n, total, verdict), decided_at = now()
    where id = s.id;
    perform set_config('flatsphere.ec_vote', '0', true);
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, v, 'cast_ec_vote', 'approval_request', p_request::text,
    jsonb_build_object('vote', p_vote, 'yes', y, 'no', n, 'of', total, 'result', verdict));
end $$;
revoke all on function cast_ec_vote(uuid, text, text) from public, anon;
grant execute on function cast_ec_vote(uuid, text, text) to authenticated;

-- Association bank account (the sample account below is a placeholder until the Treasurer replaces it).
create table bank_accounts (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  bank_name text not null,
  branch text not null default '',
  account_name text not null,
  account_number text not null check (account_number ~ '^[0-9]{9,18}$'),
  ifsc text not null check (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  is_sample boolean not null default false,
  status text not null default 'active' check (status in ('active', 'retired')),
  active_from timestamptz not null default now(),
  retired_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index bank_accounts_one_active on bank_accounts (association_id) where status = 'active';
alter table bank_accounts enable row level security;

create table bank_change_requests (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  approval_request_id uuid not null unique references approval_requests(id) on delete cascade,
  bank_name text not null,
  branch text not null default '',
  account_name text not null,
  account_number text not null check (account_number ~ '^[0-9]{9,18}$'),
  ifsc text not null check (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'cooling', 'active', 'rejected')),
  effective_at timestamptz,
  requested_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  activated_at timestamptz
);
alter table bank_change_requests enable row level security;

insert into bank_accounts (association_id, bank_name, branch, account_name, account_number, ifsc, is_sample)
select a.id, 'State Bank of India', 'Kakkanad (sample)', a.name, '000000004521', 'SBIN0000000', true
from associations a
where not exists (select 1 from bank_accounts b where b.association_id = a.id and b.status = 'active');

create function notify_committee(p_assoc uuid, p_key text, p_title text, p_body text, p_path text) returns void
language sql security definer set search_path = public as $$
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select p_assoc, u, p_key, p_title, p_body, p_path from ec_voter_ids(p_assoc, null) u
  on conflict (association_id, user_id, event_key) do nothing;
$$;
revoke all on function notify_committee(uuid, text, text, text, text) from public, anon, authenticated;

create function activate_due_bank_changes() returns void
language plpgsql security definer set search_path = public as $$
declare q bank_change_requests;
begin
  for q in select * from bank_change_requests where status = 'cooling' and effective_at <= now() for update loop
    update bank_accounts set status = 'retired', retired_at = now() where association_id = q.association_id and status = 'active';
    insert into bank_accounts (association_id, bank_name, branch, account_name, account_number, ifsc, is_sample)
    values (q.association_id, q.bank_name, q.branch, q.account_name, q.account_number, q.ifsc, false);
    update bank_change_requests set status = 'active', activated_at = now() where id = q.id;
    insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (q.association_id, null, 'activate_bank_account', 'bank_account', q.id::text,
      jsonb_build_object('bank', q.bank_name, 'last4', right(q.account_number, 4)));
    perform notify_committee(q.association_id, 'bank-active:' || q.id, 'New bank account is now active',
      q.bank_name || ' ••••' || right(q.account_number, 4) || ' is the association account.', '/finance');
  end loop;
end $$;
revoke all on function activate_due_bank_changes() from public, anon, authenticated;

create function current_bank_account() returns jsonb
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); acc bank_accounts; q bank_change_requests; seen boolean;
begin
  if a is null or not is_member(a) then raise exception 'not_allowed: association member required'; end if;
  perform activate_due_bank_changes();
  select * into acc from bank_accounts where association_id = a and status = 'active';
  select * into q from bank_change_requests where association_id = a and status in ('pending', 'cooling')
    order by created_at desc limit 1;
  seen := has_role(a, array['admin','president','vice_president','secretary','joint_secretary','treasurer','joint_treasurer','ec_member','auditor']::app_role[]);
  return jsonb_build_object(
    'account', case when acc.id is null then null else jsonb_build_object(
      'bank_name', acc.bank_name, 'branch', acc.branch, 'account_name', acc.account_name,
      'account_number', acc.account_number, 'ifsc', acc.ifsc, 'is_sample', acc.is_sample, 'active_from', acc.active_from) end,
    'pending', case when q.id is null or not seen then null else jsonb_build_object(
      'status', q.status, 'effective_at', q.effective_at, 'bank_name', q.bank_name,
      'masked_number', '••••' || right(q.account_number, 4), 'requested_at', q.created_at,
      'approval_ref', (select ref from approval_requests where id = q.approval_request_id)) end,
    'can_change', has_role(a, array['treasurer']::app_role[]));
end $$;
revoke all on function current_bank_account() from public, anon;
grant execute on function current_bank_account() to authenticated;

create function request_bank_account_change(
  p_bank_name text, p_branch text, p_account_name text, p_account_number text, p_ifsc text, p_reason text, p_mom_ref text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association(); acc bank_accounts; rid uuid; qid uuid;
  num text := regexp_replace(coalesce(p_account_number, ''), '\D', '', 'g');
  code text := upper(trim(coalesce(p_ifsc, '')));
  request_ref text := 'APR-' || upper(substr(md5(random()::text), 1, 10));
begin
  if a is null or not has_role(a, array['treasurer']::app_role[]) then
    raise exception 'not_allowed: only the Treasurer can request a bank account change';
  end if;
  if exists (select 1 from bank_change_requests where association_id = a and status in ('pending', 'cooling')) then
    raise exception 'invalid: a bank account change is already in progress';
  end if;
  if coalesce(trim(p_bank_name), '') = '' or coalesce(trim(p_account_name), '') = '' then raise exception 'invalid: enter the bank and account name'; end if;
  if num !~ '^[0-9]{9,18}$' then raise exception 'invalid: account number must be 9 to 18 digits'; end if;
  if code !~ '^[A-Z]{4}0[A-Z0-9]{6}$' then raise exception 'invalid: enter a valid IFSC code'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'invalid: enter the reason for the change'; end if;
  if length(trim(coalesce(p_mom_ref, ''))) < 3 then raise exception 'invalid: link the MOM decision for this change'; end if;
  select * into acc from bank_accounts where association_id = a and status = 'active';
  if acc.id is not null and acc.account_number = num and acc.ifsc = code then
    raise exception 'invalid: this is already the active account';
  end if;

  insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role,
    category, mom_required, mom_ref, high_risk)
  values (a, request_ref, 'W3', 'Change association bank account',
    jsonb_build_object(
      'Current account', coalesce(acc.bank_name || ' ••••' || right(acc.account_number, 4), 'Not set'),
      'New account', trim(p_bank_name) || ' ••••' || right(num, 4),
      'Reason', trim(p_reason),
      'Cooling-off', '48 hours after final approval'),
    auth.uid(), coalesce(my_name(), 'Treasurer'), 'treasurer', 'Bank change', true, trim(p_mom_ref), true)
  returning id into rid;
  insert into approval_steps (request_id, seq, role, name) values (rid, 1, 'secretary', 'Secretary');
  insert into approval_steps (request_id, seq, role, name) values (rid, 2, 'president', 'President');
  insert into approval_steps (request_id, seq, role, name, step_type) values (rid, 3, 'ec_member', 'EC vote', 'ec_vote');

  insert into bank_change_requests (association_id, approval_request_id, bank_name, branch, account_name,
    account_number, ifsc, reason, requested_by)
  values (a, rid, trim(p_bank_name), trim(coalesce(p_branch, '')), trim(p_account_name), num, code, trim(p_reason), auth.uid())
  returning id into qid;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'request_bank_account_change', 'bank_change', qid::text, jsonb_build_object('last4', right(num, 4)));
  perform notify_committee(a, 'bank-request:' || rid, 'Bank account change requested',
    'The Treasurer has requested a new association bank account. Approval chain: Secretary, President, EC vote.',
    '/approvals/' || request_ref);
  return rid;
end $$;
revoke all on function request_bank_account_change(text, text, text, text, text, text, text) from public, anon;
grant execute on function request_bank_account_change(text, text, text, text, text, text, text) to authenticated;

create function sync_bank_change_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests;
begin
  if old.decision is not distinct from new.decision or new.decision = 'pending' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.code <> 'W3' then return new; end if;
  perform notify_committee(r.association_id, 'bank-step:' || r.id || ':' || new.id || ':' || new.decision,
    'Bank account change: ' || coalesce(new.name, 'step') || ' ' || new.decision::text,
    coalesce(new.comment, ''), '/approvals/' || r.ref);
  if new.decision = 'approved' then
    if not exists (select 1 from approval_steps where request_id = new.request_id and decision <> 'approved') then
      update bank_change_requests set status = 'cooling', effective_at = now() + interval '48 hours'
      where approval_request_id = new.request_id;
    end if;
  else
    update bank_change_requests set status = 'rejected' where approval_request_id = new.request_id;
  end if;
  return new;
end $$;
create trigger bank_change_approval_sync after update of decision on approval_steps
  for each row execute function sync_bank_change_approval();

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('flatsphere-bank-activation', '*/15 * * * *', 'select public.activate_due_bank_changes()');
exception when others then raise notice 'pg_cron not scheduled: %', sqlerrm;
end $$;

-- Catalogue entry for the bank change workflow now matches how it runs.
delete from workflow_type_steps where workflow_type_id in (select id from workflow_types where code = 'W3');
insert into workflow_type_steps (workflow_type_id, step_no, label, role_required, action_type)
select t.id, v.n, v.label, v.role::app_role, v.kind
from workflow_types t
cross join (values
  (1, 'Secretary approval', 'secretary', 'approval'),
  (2, 'President approval', 'president', 'approval'),
  (3, 'EC vote', 'ec_member', 'ec_vote'),
  (4, '48-hour cooling period', null, 'cooling_period'),
  (5, 'Activate new bank details', null, 'execute')
) as v(n, label, role, kind)
where t.code = 'W3';

-- Workflow reassignment understands EC vote steps.
create or replace function apply_workflow_assignment() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; w text; wt uuid; st record; n integer := 0;
begin
  if current_setting('flatsphere.wf_building', true) = '1' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.id is null then return new; end if;
  select workflow_code into w from process_workflow_assignments
    where association_id = r.association_id and process_code = r.code;
  if w is null or w = r.code then return new; end if;
  if r.workflow_code is not null then return null; end if;
  select id into wt from workflow_types where association_id = r.association_id and code = w and active
    order by version desc limit 1;
  if wt is null or not exists (select 1 from workflow_type_steps where workflow_type_id = wt
      and ((action_type = 'approval' and role_required is not null) or action_type = 'ec_vote')) then
    return new;
  end if;
  perform set_config('flatsphere.wf_building', '1', true);
  update approval_requests set workflow_code = w where id = r.id;
  for st in select * from workflow_type_steps where workflow_type_id = wt
      and ((action_type = 'approval' and role_required is not null) or action_type = 'ec_vote') order by step_no loop
    n := n + 1;
    insert into approval_steps (request_id, seq, role, alternate_role, name, step_type)
    values (r.id, n, case when st.action_type = 'ec_vote' then 'ec_member'::app_role else st.role_required end,
      st.alternate_role, case when st.action_type = 'ec_vote' then 'EC vote' else regexp_replace(st.label, ' approval$', '') end,
      case when st.action_type = 'ec_vote' then 'ec_vote' else 'approval' end);
  end loop;
  perform set_config('flatsphere.wf_building', '0', true);
  return null;
end $$;

create or replace function assign_process_workflow(p_process text, p_workflow text) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); wt uuid;
begin
  if a is null or not has_role(a, array['admin']::app_role[]) then
    raise exception 'not_allowed: only the Admin can manage approval workflows';
  end if;
  if p_process not in ('W12', 'W22', 'W23', 'W24', 'W25', 'W30') then
    raise exception 'invalid: this process has built-in checks and cannot be reassigned';
  end if;
  select id into wt from workflow_types where association_id = a and code = p_workflow and active
    order by version desc limit 1;
  if wt is null or not exists (select 1 from workflow_type_steps where workflow_type_id = wt
      and ((action_type = 'approval' and role_required is not null) or action_type = 'ec_vote')) then
    raise exception 'invalid: choose a workflow that has at least one approval or EC vote step';
  end if;
  if exists (select 1 from workflow_type_steps where workflow_type_id = wt and action_type = 'approval' and role_required = 'owner') then
    raise exception 'invalid: workflows with a flat owner consent step cannot be used for this process';
  end if;
  if p_workflow = p_process then
    delete from process_workflow_assignments where association_id = a and process_code = p_process;
  else
    insert into process_workflow_assignments (association_id, process_code, workflow_code, updated_by)
    values (a, p_process, p_workflow, auth.uid())
    on conflict (association_id, process_code)
    do update set workflow_code = excluded.workflow_code, updated_by = excluded.updated_by, updated_at = now();
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'assign_process_workflow', 'workflow', p_process, jsonb_build_object('workflow', p_workflow));
end $$;

create or replace function workflow_admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin']::app_role[]) then
    raise exception 'not_allowed: only the Admin can manage approval workflows';
  end if;
  return jsonb_build_object(
    'workflows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', t.code, 'name', t.name, 'description', coalesce(t.description, ''),
        'flow', (select coalesce(jsonb_agg(jsonb_build_object(
            'step', s.step_no, 'label', s.label, 'role', s.role_required, 'type', s.action_type) order by s.step_no), '[]'::jsonb)
          from workflow_type_steps s where s.workflow_type_id = t.id)
      ) order by length(t.code), t.code)
      from workflow_types t
      where t.association_id = a and t.active
        and t.version = (select max(v.version) from workflow_types v where v.association_id = a and v.code = t.code and v.active)
    ), '[]'::jsonb),
    'processes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', p.code, 'name', p.name, 'reassignable', p.reassignable, 'note', p.note,
        'workflow', coalesce(x.workflow_code, p.code)) order by length(p.code), p.code)
      from (values
        ('W3', 'Bank change', false, 'Fixed security flow: Secretary, President, EC vote, 48-hour wait'),
        ('W6', 'Monitor assignment', false, 'Not used in the app yet'),
        ('W12', 'Fund request', true, ''),
        ('W16', 'Late fee rule', false, 'Not used in the app yet'),
        ('W20', 'Owner change', false, 'Dues and ID-proof checks are tied to its approval stages'),
        ('W21', 'Resident change', false, 'Dues and ID-proof checks are tied to its approval stages'),
        ('W22', 'Committee change', true, ''),
        ('W23', 'Income category', true, ''),
        ('W24', 'Association register change', true, ''),
        ('W25', 'Amenity booking', true, ''),
        ('W30', 'Family member addition', true, '')
      ) as p(code, name, reassignable, note)
      left join process_workflow_assignments x on x.association_id = a and x.process_code = p.code
    ), '[]'::jsonb)
  );
end $$;
