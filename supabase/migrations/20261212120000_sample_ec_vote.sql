-- Sample request waiting for an EC vote (Secretary and President already approved, 3 of 8 EC members voted).
do $$
declare
  a constant uuid := '00000000-0000-0000-0000-000000000001';
  init uuid; me uuid; rid uuid; n integer := 0; v uuid;
begin
  select m.user_id into init from memberships m where m.association_id = a and m.role = 'treasurer' and m.ended_at is null
    order by (select count(*) from memberships x where x.user_id = m.user_id) limit 1;
  select id into me from profiles where full_name = 'Ajeesh G' limit 1;
  if init is null or exists (select 1 from approval_requests where ref = 'APR-SAMPLE-ECVOTE') then
    raise notice 'sample EC vote skipped';
    return;
  end if;

  insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role,
    category, mom_required, mom_ref)
  values (a, 'APR-SAMPLE-ECVOTE', 'W12', 'Terrace waterproofing - Rs. 1,80,000 (sample)',
    jsonb_build_object('Work', 'Terrace waterproofing, blocks A to C', 'Amount', 180000,
      'Quotes', 'Three quotes collected; lowest chosen', 'Note', 'Sample record to try the EC vote'),
    init, 'Thomas Kurian', 'treasurer', 'Fund request', true, 'EC-2026-09')
  returning id into rid;

  insert into approval_steps (request_id, seq, role, name, decision, decided_by, decided_by_name, comment, decided_at)
  values (rid, 1, 'secretary', 'Secretary', 'approved', me, 'Secretary', 'Quotes checked', now() - interval '2 days'),
         (rid, 2, 'president', 'President', 'approved', me, 'President', 'Go ahead to EC vote', now() - interval '1 day');
  insert into approval_steps (request_id, seq, role, name, step_type) values (rid, 3, 'ec_member', 'EC vote', 'ec_vote');

  for v in select u from ec_voter_ids(a, init) u where u is distinct from me limit 3 loop
    n := n + 1;
    insert into ec_votes (request_id, voter, voter_name, vote, comment)
    values (rid, v, coalesce((select full_name from profiles where id = v), 'EC member'),
      case when n = 3 then 'no' else 'yes' end,
      case when n = 3 then 'Prefer to wait for the monsoon to end' end);
  end loop;
end $$;
