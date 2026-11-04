-- Approving a walk-in: only an active owner/resident of that visitor's flat, in that visitor's association,
-- with clear messages when the visitor was already handled or the user is not from that flat.
create or replace function decide_gate_visitor(p_request uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v visitor_requests; fno text;
begin
  select * into v from visitor_requests where id = p_request for update;
  if v.id is null or not exists (
    select 1 from memberships m where m.user_id = auth.uid() and m.association_id = v.association_id and m.ended_at is null
  ) then
    raise exception 'not_found: visitor not found';
  end if;
  select number into fno from flats where id = v.flat_id;
  if v.flat_id is null or not exists (
    select 1 from memberships m
    where m.user_id = auth.uid() and m.association_id = v.association_id and m.flat_id = v.flat_id
      and m.ended_at is null and m.role in ('owner','resident')
  ) then
    raise exception 'not_allowed: only the owner or resident of flat % can approve this visitor', coalesce(fno, '?');
  end if;
  if v.approval <> 'awaiting' or v.status <> 'expected' then
    raise exception 'invalid: this visitor was already %', case
      when v.approval = 'approved' then 'approved'
      when v.approval = 'denied' then 'denied'
      when v.approval = 'lobby' then 'left at the lobby'
      when v.status = 'checked_out' then 'checked out'
      else 'handled by the gate' end;
  end if;
  update visitor_requests set approval = case when p_approve then 'approved' else 'denied' end,
    status = case when p_approve then status else 'cancelled' end
  where id = v.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (v.association_id, auth.uid(), case when p_approve then 'approve_gate_visitor' else 'deny_gate_visitor' end,
    'visitor_request', v.id::text, jsonb_build_object('approval', v.approval),
    jsonb_build_object('approval', case when p_approve then 'approved' else 'denied' end));
end $$;
revoke all on function decide_gate_visitor(uuid, boolean) from public, anon;
grant execute on function decide_gate_visitor(uuid, boolean) to authenticated;
