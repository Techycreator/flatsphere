-- W2 is the visibility-change workflow described in the app: Secretary review,
-- EC vote, then President approval. Approval steps already created remain unchanged.
create or replace function set_visibility_workflow_steps(p_association uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  workflow_id uuid;
begin
  select id into workflow_id
  from workflow_types
  where association_id = p_association and code = 'W2' and active
  order by version desc
  limit 1;

  if workflow_id is null then return; end if;

  delete from workflow_type_steps where workflow_type_id = workflow_id;
  insert into workflow_type_steps (workflow_type_id, step_no, label, role_required, action_type)
  values
    (workflow_id, 1, 'Secretary review', 'secretary', 'approval'),
    (workflow_id, 2, 'EC vote', 'ec_member', 'approval'),
    (workflow_id, 3, 'President approval', 'president', 'approval');
end $$;
revoke all on function set_visibility_workflow_steps(uuid) from public, anon, authenticated;

create or replace function seed_workflow_catalog_on_association() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform seed_workflow_catalog(new.id);
  perform set_visibility_workflow_steps(new.id);
  return new;
end $$;

do $$
declare
  association_id uuid;
begin
  for association_id in select id from associations loop
    perform seed_workflow_catalog(association_id);
    perform set_visibility_workflow_steps(association_id);
  end loop;
end $$;

-- Keep W1 available for future access-change requests; Admins can choose a
-- catalogued approval workflow for it from the workflow assignment screen.
create or replace function assign_process_workflow(p_process text, p_workflow text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_association uuid := my_association();
  workflow_id uuid;
begin
  if v_association is null or not has_role(v_association, array['admin']::app_role[]) then
    raise exception 'not_allowed: only the Admin can manage approval workflows';
  end if;
  if p_process not in ('W1', 'W12', 'W22', 'W23', 'W24', 'W25', 'W30') then
    raise exception 'invalid: this process has built-in checks and cannot be reassigned';
  end if;
  select id into workflow_id
  from workflow_types
  where workflow_types.association_id = v_association and code = p_workflow and active
  order by version desc
  limit 1;
  if workflow_id is null or not exists (
    select 1 from workflow_type_steps
    where workflow_type_id = workflow_id and action_type = 'approval' and role_required is not null
  ) then
    raise exception 'invalid: choose a workflow that has at least one approval step';
  end if;
  if exists (
    select 1 from workflow_type_steps
    where workflow_type_id = workflow_id and action_type = 'approval' and role_required = 'owner'
  ) then
    raise exception 'invalid: workflows with a flat owner consent step cannot be used for this process';
  end if;
  if p_workflow = p_process then
    delete from process_workflow_assignments
    where process_workflow_assignments.association_id = v_association
      and process_code = p_process;
  else
    insert into process_workflow_assignments (association_id, process_code, workflow_code, updated_by)
    values (v_association, p_process, p_workflow, auth.uid())
    on conflict (association_id, process_code)
    do update set workflow_code = excluded.workflow_code, updated_by = excluded.updated_by, updated_at = now();
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (v_association, auth.uid(), 'assign_process_workflow', 'workflow', p_process, jsonb_build_object('workflow', p_workflow));
end $$;

create or replace function workflow_admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_association uuid := my_association();
begin
  if v_association is null or not has_role(v_association, array['admin']::app_role[]) then
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
      where t.association_id = v_association and t.active
        and t.version = (select max(v.version) from workflow_types v where v.association_id = v_association and v.code = t.code and v.active)
    ), '[]'::jsonb),
    'processes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', p.code, 'name', p.name, 'reassignable', p.reassignable, 'note', p.note,
        'workflow', coalesce(x.workflow_code, p.code)) order by length(p.code), p.code)
      from (values
        ('W1', 'Access change', true, 'Reserved for future access-change requests'),
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
      left join process_workflow_assignments x on x.association_id = v_association and x.process_code = p.code
    ), '[]'::jsonb)
  );
end $$;

-- Keep complaint counters in sync with actual uploaded files, not UI placeholders.
create or replace function sync_complaint_media_counts() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  target_complaint uuid;
begin
  if tg_op = 'DELETE' then
    target_complaint := old.complaint_id;
  else
    target_complaint := new.complaint_id;
  end if;
  update complaints
  set photo_count = (select count(*)::integer from complaint_media where complaint_id = target_complaint and kind = 'photo'),
      has_voice_note = exists (select 1 from complaint_media where complaint_id = target_complaint and kind = 'voice')
  where id = target_complaint;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

create trigger complaint_media_sync_counts
after insert or delete on complaint_media
for each row execute function sync_complaint_media_counts();

create or replace function guard_complaint_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('app.complaint_closure', true) = 'on' then return new; end if;
  if new.status = 'closed' then
    raise exception 'not_allowed: use the close or reopen action to close a resolved request';
  end if;
  if new.status is distinct from old.status and not (
    has_role(old.association_id, array['caretaker','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = old.association_id and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and old.category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  ) then
    raise exception 'not_allowed: status updates require caretaker, Secretary, Joint Secretary, or the assigned area monitor';
  end if;
  return new;
end $$;

-- A resolved request can be closed; a closed request can later be reopened.
create or replace function close_or_reopen_complaint(p_ref text, p_close boolean, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare
  v_association uuid := my_association();
  complaint_row complaints;
  next_status ticket_status := case when p_close then 'closed' else 'in_progress' end;
begin
  if v_association is null then raise exception 'not_allowed: association session required'; end if;
  select * into complaint_row
  from complaints
  where complaints.association_id = v_association and ref = p_ref
  for update;
  if complaint_row.id is null then raise exception 'not_found: complaint not found'; end if;
  if (p_close and complaint_row.status <> 'resolved')
    or (not p_close and complaint_row.status not in ('resolved', 'closed')) then
    raise exception 'invalid: only a resolved request can be closed, and only a resolved or closed request can be reopened';
  end if;
  if not (
    complaint_row.raised_by = auth.uid()
    or has_role(v_association, array['president','vice_president','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = v_association and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and complaint_row.category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  ) then
    raise exception 'not_allowed: only the person who raised it, the President, Vice President, Secretary, Joint Secretary or the area monitor can close or reopen';
  end if;
  if not p_close and coalesce(trim(p_note), '') = '' then raise exception 'invalid: add a reason to reopen'; end if;
  perform set_config('app.complaint_closure', 'on', true);
  update complaints set status = next_status where id = complaint_row.id;
  perform set_config('app.complaint_closure', 'off', true);
  insert into complaint_remarks (complaint_id, author, author_name, body)
  values (complaint_row.id, auth.uid(), my_name(), '[' || next_status::text || '] ' ||
    coalesce(nullif(trim(p_note), ''), 'Confirmed resolved'));
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (v_association, auth.uid(), 'close_or_reopen_complaint', 'complaint', complaint_row.ref,
    jsonb_build_object('status', complaint_row.status), jsonb_build_object('status', next_status, 'note', p_note));
end $$;
