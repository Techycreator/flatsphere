drop trigger archive_membership_changes on memberships;
create trigger archive_membership_changes
  after insert or delete or update of role, flat_id, ended_at, designations, monitor_categories, monitor_from, monitor_until, assigned_by
  on memberships for each row execute function archive_row_change('membership');
