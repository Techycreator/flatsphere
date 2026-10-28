-- Admin-managed assignment of approval processes to approval workflows (W-codes).
alter table approval_requests add column workflow_code text;

create table process_workflow_assignments (
  association_id uuid not null references associations(id) on delete cascade,
  process_code text not null,
  workflow_code text not null,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now(),
  primary key (association_id, process_code)
);
alter table process_workflow_assignments enable row level security;

-- Family member addition becomes a catalogued workflow (Secretary approval), like amenity bookings.
insert into workflow_types (association_id, code, version, name, description, requires_mom)
select a.id, 'W30', 1, 'Family member addition', 'Owner or resident adds a family member', false
from associations a
on conflict (association_id, code, version) do nothing;
insert into workflow_type_steps (workflow_type_id, step_no, label, role_required, action_type)
select t.id, 1, 'Secretary approval', 'secretary', 'approval' from workflow_types t
where t.code = 'W30' and t.version = 1
  and not exists (select 1 from workflow_type_steps s where s.workflow_type_id = t.id and s.step_no = 1);
insert into workflow_type_steps (workflow_type_id, step_no, label, action_type)
select t.id, 2, 'Confirm family member', 'execute' from workflow_types t
where t.code = 'W30' and t.version = 1
  and not exists (select 1 from workflow_type_steps s where s.workflow_type_id = t.id and s.step_no = 2);

-- Amenity bookings and family additions only take effect once every approval step is approved.
create or replace function sync_amenity_booking_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; new_status text;
begin
  if old.decision is not distinct from new.decision or new.decision = 'pending' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.code <> 'W25' then return new; end if;
  if new.decision = 'approved' and exists (select 1 from approval_steps where request_id = new.request_id and decision = 'pending') then
    return new;
  end if;
  new_status := case new.decision when 'approved' then 'approved' when 'rejected' then 'rejected' else 'pending' end;
  update amenity_bookings set status = new_status, approved_by = case when new_status = 'approved' then new.decided_by else null end,
    approved_at = case when new_status = 'approved' then now() else null end where approval_request_id = new.request_id;
  return new;
end $$;

create or replace function sync_family_addition_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests;
begin
  if old.decision is not distinct from new.decision or new.decision = 'pending' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.code <> 'W30' then return new; end if;
  if new.decision = 'approved' then
    if exists (select 1 from approval_steps where request_id = new.request_id and decision = 'pending') then return new; end if;
    update family_members set approved_at = now() where approval_request_id = new.request_id and approved_at is null;
  elsif new.decision = 'rejected' then
    update family_members set archived_at = now() where approval_request_id = new.request_id;
  end if;
  return new;
end $$;

-- When a process has been assigned a different workflow, new requests get that workflow's approval steps.
create function apply_workflow_assignment() returns trigger
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
  if wt is null or not exists (select 1 from workflow_type_steps
      where workflow_type_id = wt and action_type = 'approval' and role_required is not null) then
    return new;
  end if;
  perform set_config('flatsphere.wf_building', '1', true);
  update approval_requests set workflow_code = w where id = r.id;
  for st in select * from workflow_type_steps
      where workflow_type_id = wt and action_type = 'approval' and role_required is not null order by step_no loop
    n := n + 1;
    insert into approval_steps (request_id, seq, role, alternate_role, name)
    values (r.id, n, st.role_required, st.alternate_role, regexp_replace(st.label, ' approval$', ''));
  end loop;
  perform set_config('flatsphere.wf_building', '0', true);
  return null;
end $$;
create trigger approval_step_apply_workflow before insert on approval_steps
  for each row execute function apply_workflow_assignment();

create function workflow_admin_overview() returns jsonb
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
        'code', p.code, 'name', p.name, 'reassignable', p.reassignable,
        'workflow', coalesce(x.workflow_code, p.code)) order by length(p.code), p.code)
      from (values
        ('W3', 'Bank change', false), ('W6', 'Monitor assignment', false), ('W12', 'Fund request', true),
        ('W16', 'Late fee rule', false), ('W20', 'Owner change', false), ('W21', 'Resident change', false),
        ('W22', 'Committee change', false), ('W23', 'Income category', true),
        ('W24', 'Association register change', true), ('W25', 'Amenity booking', true),
        ('W30', 'Family member addition', true)
      ) as p(code, name, reassignable)
      left join process_workflow_assignments x on x.association_id = a and x.process_code = p.code
    ), '[]'::jsonb)
  );
end $$;
revoke all on function workflow_admin_overview() from public, anon;
grant execute on function workflow_admin_overview() to authenticated;

create function assign_process_workflow(p_process text, p_workflow text) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); wt uuid;
begin
  if a is null or not has_role(a, array['admin']::app_role[]) then
    raise exception 'not_allowed: only the Admin can manage approval workflows';
  end if;
  if p_process not in ('W12', 'W23', 'W24', 'W25', 'W30') then
    raise exception 'invalid: this process uses built-in rules and cannot be reassigned';
  end if;
  select id into wt from workflow_types where association_id = a and code = p_workflow and active
    order by version desc limit 1;
  if wt is null or not exists (select 1 from workflow_type_steps
      where workflow_type_id = wt and action_type = 'approval' and role_required is not null) then
    raise exception 'invalid: choose a workflow that has at least one approval step';
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
revoke all on function assign_process_workflow(text, text) from public, anon;
grant execute on function assign_process_workflow(text, text) to authenticated;
