-- Committee change (W22) can be moved to another workflow; locked processes now say why.
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
  if wt is null or not exists (select 1 from workflow_type_steps
      where workflow_type_id = wt and action_type = 'approval' and role_required is not null) then
    raise exception 'invalid: choose a workflow that has at least one approval step';
  end if;
  if exists (select 1 from workflow_type_steps
      where workflow_type_id = wt and action_type = 'approval' and role_required = 'owner') then
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
        ('W3', 'Bank change', false, 'Not used in the app yet'),
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
