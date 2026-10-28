-- Flagged-for-discussion expenses: reason, committee notification, agenda feed, resolution note, approval block.
alter table expenses
  add column flag_reason text,
  add column flagged_at timestamptz,
  add column flag_resolution text,
  add column flag_resolved_at timestamptz;

create or replace function decide_expense(p_id uuid, p_action text, p_comment text default null) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); me uuid := auth.uid(); e expenses;
begin
  select * into e from expenses where id = p_id and association_id = a for update;
  if e.id is null then raise exception 'not_found'; end if;
  if p_action = 'send_back' and coalesce(trim(p_comment), '') = '' then
    raise exception 'invalid: add a comment saying what is missing';
  end if;
  case p_action
  when 'verify' then
    if e.status <> 'awaiting_treasurer' then raise exception 'invalid: this expense is not waiting for the Treasurer'; end if;
    if not has_role(a, array['treasurer']::app_role[]) then raise exception 'not_allowed: only the Treasurer can verify'; end if;
    if e.entered_by = me then raise exception 'not_allowed: you entered this expense, so someone else must verify it'; end if;
    if cardinality(e.bill_paths) = 0 then raise exception 'invalid: attach the bill before verifying'; end if;
    update expenses set status = 'awaiting_president', verified_by = me, comment = null where id = e.id;
  when 'approve' then
    if e.status <> 'awaiting_president' then raise exception 'invalid: this expense is not waiting for the President'; end if;
    if not has_role(a, array['president']::app_role[]) then raise exception 'not_allowed: only the President can approve'; end if;
    if e.flagged then raise exception 'invalid: this expense is flagged for discussion; resolve the flag first'; end if;
    if e.entered_by = me then raise exception 'not_allowed: you entered this expense, so you cannot approve it'; end if;
    if e.verified_by = me then raise exception 'not_allowed: you verified this expense, so another person must approve it'; end if;
    update expenses set status = 'approved', approved_by = me where id = e.id;
  when 'send_back' then
    if not ((e.status = 'awaiting_treasurer' and has_role(a, array['treasurer']::app_role[]))
            or (e.status = 'awaiting_president' and has_role(a, array['president']::app_role[]))) then
      raise exception 'not_allowed: you cannot send this expense back at its current stage';
    end if;
    update expenses set status = 'sent_back', verified_by = null, comment = trim(p_comment) where id = e.id;
  when 'resubmit' then
    if e.status <> 'sent_back' or e.entered_by <> me then
      raise exception 'not_allowed: only the person who entered a sent-back expense can resubmit it';
    end if;
    update expenses set status = 'awaiting_treasurer', comment = nullif(trim(coalesce(p_comment, '')), '') where id = e.id;
  when 'flag' then
    if not has_role(a, array['president']::app_role[]) then raise exception 'not_allowed: only the President can flag'; end if;
    if e.flagged then raise exception 'invalid: this expense is already flagged'; end if;
    if coalesce(trim(p_comment), '') = '' then raise exception 'invalid: say why this expense needs discussion'; end if;
    update expenses set flagged = true, flag_reason = trim(p_comment), flagged_at = now(),
      flag_resolution = null, flag_resolved_at = null where id = e.id;
    perform notify_committee(a, 'expense_flag:' || e.ref_no || ':' || extract(epoch from now())::bigint,
      'Expense flagged for discussion',
      e.ref_no || ' · ' || e.category || ' · ' || e.vendor || ' · Rs. ' || e.amount || '. Reason: ' || trim(p_comment),
      '/finance');
  when 'resolve_flag' then
    if not has_role(a, array['president','secretary']::app_role[]) then
      raise exception 'not_allowed: only the President or Secretary can resolve a flag';
    end if;
    if not e.flagged then raise exception 'invalid: this expense is not flagged'; end if;
    if coalesce(trim(p_comment), '') = '' then raise exception 'invalid: record what was decided (for example the meeting date and outcome)'; end if;
    update expenses set flagged = false, flag_resolution = trim(p_comment), flag_resolved_at = now() where id = e.id;
    perform notify_committee(a, 'expense_flag_resolved:' || e.ref_no || ':' || extract(epoch from now())::bigint,
      'Flagged expense resolved', e.ref_no || ': ' || trim(p_comment), '/finance');
  else
    raise exception 'invalid: unknown action %', p_action;
  end case;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
    values (a, me, 'expense_' || p_action, 'expense', e.ref_no, jsonb_build_object('status', e.status),
            jsonb_build_object('comment', p_comment));
end $$;

-- Agenda lines for every open flagged expense, used to pre-fill the next EC / office-bearer meeting agenda.
create function flagged_expense_agenda() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(
    'Discuss flagged expense ' || e.ref_no || ' (' || e.category || ', ' || e.vendor || ', Rs. ' || e.amount || ') - ' || e.flag_reason
    order by e.flagged_at), '{}')
  from expenses e
  where e.association_id = my_association() and e.flagged
    and has_role(e.association_id, array['admin','president','secretary']::app_role[]);
$$;
revoke all on function flagged_expense_agenda() from public, anon;
grant execute on function flagged_expense_agenda() to authenticated;
