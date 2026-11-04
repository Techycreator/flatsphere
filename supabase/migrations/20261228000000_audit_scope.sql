-- Audit and workflow logs: only elevated roles, only in the association currently open.
drop policy if exists active_association_only on audit_log;
create policy active_association_only on audit_log as restrictive for select to authenticated
  using (association_id = my_association());

drop policy if exists audit_insert_view on audit_log;
create policy audit_insert_view on audit_log for insert to authenticated with check (
  actor = auth.uid() and action = 'view' and association_id = my_association());

drop policy if exists workflow_action_log_read on workflow_action_log;
create policy workflow_action_log_read on workflow_action_log for select to authenticated using (
  exists (
    select 1 from workflow_instances w
    where w.id = workflow_action_log.workflow_instance_id
      and w.association_id = my_association()
      and has_role(w.association_id, array['admin','president','secretary','treasurer','auditor']::app_role[])
  )
);
