-- 1. Payment reversal: a mistaken receipt is never edited; an approved reversal adds a linked negative entry,
--    so every "paid" total nets it out and the due becomes unpaid again.
alter table payments add column if not exists reverses uuid references payments(id);
alter table payments add column if not exists reversal_reason text;
alter table payments drop constraint if exists payments_amount_check;
alter table payments add constraint payments_amount_check
  check ((reverses is null and amount > 0) or (reverses is not null and amount < 0));
create unique index if not exists payments_one_reversal on payments (reverses) where reverses is not null;
drop policy if exists payments_no_direct_reversal on payments;
create policy payments_no_direct_reversal on payments as restrictive for insert to authenticated
  with check (reverses is null);

create table if not exists payment_reversal_requests (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  payment_id uuid not null references payments(id),
  approval_request_id uuid not null references approval_requests(id) on delete cascade,
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','sent_back')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table payment_reversal_requests enable row level security;
drop policy if exists payment_reversals_read on payment_reversal_requests;
create policy payment_reversals_read on payment_reversal_requests for select to authenticated
  using (association_id = my_association() and fin_reader(association_id));

create or replace function request_payment_reversal(p_payment uuid, p_reason text, p_ref text) returns uuid
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); p payments; r uuid; fno text; due_head text; actor_role app_role;
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: only the Treasurer can reverse a payment'; end if;
  select * into p from payments where id = p_payment and association_id = a;
  if p.id is null or p.reverses is not null then raise exception 'not_found: payment not found'; end if;
  if exists (select 1 from payments where reverses = p.id) then raise exception 'invalid: this payment is already reversed'; end if;
  if exists (select 1 from payment_reversal_requests where payment_id = p.id and status = 'pending') then
    raise exception 'invalid: a reversal for this payment is already waiting for approval';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'invalid: enter the reason for the reversal'; end if;
  if coalesce(trim(p_ref), '') = '' then raise exception 'invalid: workflow reference is required'; end if;
  select number into fno from flats where id = p.flat_id;
  select head into due_head from dues where id = p.due_id;
  select role into actor_role from memberships where association_id = a and user_id = auth.uid() and ended_at is null
    and role in ('treasurer','joint_treasurer','admin') order by role limit 1;
  insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role, category)
  values (a, trim(p_ref), 'W13', 'Reverse payment ' || p.receipt_no,
    jsonb_build_object('Receipt', p.receipt_no, 'Flat', fno, 'Due', coalesce(due_head, 'Advance'),
      'Amount', '₹' || p.amount, 'Paid on', to_char(p.paid_on, 'DD Mon YYYY'), 'Reason', trim(p_reason)),
    auth.uid(), coalesce(my_name(), 'Treasurer'), actor_role, 'Payment reversal')
  returning id into r;
  insert into approval_steps (request_id, seq, role, alternate_role, name) values (r, 1, 'president', 'secretary', 'President or Secretary');
  insert into payment_reversal_requests (association_id, payment_id, approval_request_id, reason)
  values (a, p.id, r, trim(p_reason));
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'request_payment_reversal', 'payment', p.id::text, jsonb_build_object('reason', trim(p_reason)));
  return r;
end $$;
revoke all on function request_payment_reversal(uuid, text, text) from public, anon;
grant execute on function request_payment_reversal(uuid, text, text) to authenticated;

create or replace function sync_payment_reversal() returns trigger
language plpgsql security definer set search_path = public as $$
declare q payment_reversal_requests; p payments; s text;
begin
  if old.decision is not distinct from new.decision or new.decision = 'pending' then return new; end if;
  select * into q from payment_reversal_requests where approval_request_id = new.request_id and status = 'pending';
  if q.id is null then return new; end if;
  if new.decision = 'approved' and exists (select 1 from approval_steps where request_id = new.request_id and decision = 'pending') then
    return new;
  end if;
  s := case new.decision when 'approved' then 'approved' when 'rejected' then 'rejected' else 'sent_back' end;
  update payment_reversal_requests set status = s where id = q.id;
  if s = 'approved' then
    select * into p from payments where id = q.payment_id;
    insert into payments (association_id, flat_id, due_id, amount, paid_on, mode, reference, recorded_by, reverses, reversal_reason)
    values (p.association_id, p.flat_id, p.due_id, -p.amount, current_date, p.mode, 'Reversal of ' || p.receipt_no,
      coalesce(new.decided_by, q.created_by), p.id, q.reason);
    insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (p.association_id, new.decided_by, 'reverse_payment', 'payment', p.id::text,
      jsonb_build_object('receipt', p.receipt_no, 'amount', p.amount, 'reason', q.reason));
  end if;
  return new;
end $$;
drop trigger if exists payment_reversal_sync on approval_steps;
create trigger payment_reversal_sync after update of decision on approval_steps
  for each row execute function sync_payment_reversal();

create or replace function notify_payment_receipt() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select new.association_id, m.user_id, 'payment-receipt:' || new.receipt_no,
    case when new.reverses is null then 'Payment received' else 'Payment reversed' end,
    case when new.reverses is null
      then 'Receipt ' || new.receipt_no || ' · ₹' || new.amount || ' for flat ' || f.number || ' on ' || to_char(new.paid_on, 'DD Mon YYYY')
      else 'Receipt ' || (select receipt_no from payments where id = new.reverses) || ' · ₹' || -new.amount
        || ' for flat ' || f.number || ' was cancelled: ' || coalesce(new.reversal_reason, '') end,
    '/dues'
  from memberships m join flats f on f.id = new.flat_id
  where m.association_id = new.association_id and m.flat_id = new.flat_id and m.role = 'owner' and m.ended_at is null
  on conflict (association_id, user_id, event_key) do nothing;
  return new;
end $$;

-- 2. EC decisions taken in a meeting: the Secretary or President records each member's vote from the approved MOM.
alter table ec_votes add column if not exists recorded_by uuid references profiles(id);
alter table ec_votes add column if not exists source text not null default 'app';

create or replace function ec_meeting_voters(p_request uuid)
returns table (id uuid, name text, vote text)
language plpgsql stable security definer set search_path = public as $$
declare r approval_requests;
begin
  select * into r from approval_requests where approval_requests.id = p_request;
  if r.id is null or r.association_id is distinct from my_association() then raise exception 'not_found: request not found'; end if;
  if not has_role(r.association_id, array['president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the Secretary or President can record meeting votes';
  end if;
  return query
    select u, coalesce(p.full_name, 'EC member'), v.vote
    from ec_voter_ids(r.association_id, r.initiator) u
    left join profiles p on p.id = u
    left join ec_votes v on v.request_id = p_request and v.voter = u
    order by 2;
end $$;
revoke all on function ec_meeting_voters(uuid) from public, anon;
grant execute on function ec_meeting_voters(uuid) to authenticated;

create or replace function record_ec_meeting_votes(p_request uuid, p_mom_ref text, p_votes jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r approval_requests; s approval_steps; me uuid := auth.uid(); e jsonb; total integer; y integer; n integer;
  need integer; verdict text; added integer := 0;
begin
  select * into r from approval_requests where id = p_request for update;
  if r.id is null or r.association_id is distinct from my_association() then raise exception 'not_found: request not found'; end if;
  if not has_role(r.association_id, array['president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the Secretary or President can record meeting votes';
  end if;
  if me = r.initiator then raise exception 'not_allowed: the person who raised this request cannot record its votes'; end if;
  select * into s from approval_steps where request_id = p_request and decision = 'pending' order by seq limit 1 for update;
  if s.id is null or s.step_type <> 'ec_vote' then raise exception 'not_open: the EC vote is not open for this request'; end if;
  if coalesce(trim(p_mom_ref), '') = '' and coalesce(trim(r.mom_ref), '') = '' then
    raise exception 'invalid: select the approved minutes (MOM) where the vote was taken';
  end if;
  if coalesce(trim(r.mom_ref), '') = '' then update approval_requests set mom_ref = trim(p_mom_ref) where id = p_request; end if;
  for e in select * from jsonb_array_elements(coalesce(p_votes, '[]'::jsonb)) loop
    if e->>'vote' not in ('yes','no') then continue; end if;
    if not exists (select 1 from ec_voter_ids(r.association_id, r.initiator) u where u = (e->>'voter')::uuid) then
      raise exception 'invalid: only EC members can be recorded';
    end if;
    insert into ec_votes (request_id, voter, voter_name, vote, comment, recorded_by, source)
    select p_request, p.id, coalesce(p.full_name, 'EC member'), e->>'vote',
      'Recorded from MOM: ' || coalesce(nullif(trim(p_mom_ref), ''), r.mom_ref), me, 'meeting'
    from profiles p where p.id = (e->>'voter')::uuid
    on conflict (request_id, voter) do nothing;
    if found then added := added + 1; end if;
  end loop;
  if added = 0 then raise exception 'invalid: mark Yes or No for at least one member who has not voted yet'; end if;
  select count(*) into total from ec_voter_ids(r.association_id, r.initiator);
  select count(*) filter (where vote = 'yes'), count(*) filter (where vote = 'no') into y, n from ec_votes where request_id = p_request;
  need := total / 2 + 1;
  verdict := case when y >= need then 'approved' when n > total - need then 'rejected' end;
  if verdict is not null then
    perform set_config('flatsphere.ec_vote', '1', true);
    update approval_steps set decision = verdict::decision, decided_by = me, decided_by_name = 'EC vote (meeting)',
      comment = format('EC %s Yes, %s No of %s - EC %s', y, n, total, verdict), decided_at = now()
    where id = s.id;
    perform set_config('flatsphere.ec_vote', '0', true);
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, me, 'record_ec_meeting_votes', 'approval_request', p_request::text,
    jsonb_build_object('mom', coalesce(nullif(trim(p_mom_ref), ''), r.mom_ref), 'recorded', added, 'yes', y, 'no', n, 'of', total, 'result', verdict));
end $$;
revoke all on function record_ec_meeting_votes(uuid, text, jsonb) from public, anon;
grant execute on function record_ec_meeting_votes(uuid, text, jsonb) to authenticated;

-- 3. Fund requests: the MOM must be approved minutes, and the EC votes before the President approves.
create or replace function request_fund(p_title text,p_type text,p_amount integer,p_basis text,p_due_day text,p_mom_ref text,p_ref text)
returns uuid language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); r uuid; fund_id uuid; actor_role app_role;
begin
  if a is null or not has_role(a,array['secretary','joint_secretary','treasurer','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: Secretary or Treasurer role required to submit a fund request';
  end if;
  if coalesce(trim(p_title),'')='' or p_type not in ('recurring','ad_hoc') then raise exception 'invalid: enter a title and request type'; end if;
  if p_amount is not null and p_amount<=0 then raise exception 'invalid: amount must be greater than zero'; end if;
  if coalesce(trim(p_mom_ref),'')='' then raise exception 'invalid: EC MOM reference is required'; end if;
  if not exists (select 1 from association_meetings m where m.association_id=a and m.minutes_status='approved'
                 and trim(p_mom_ref) like m.title || '%') then
    raise exception 'invalid: select approved meeting minutes (MOM) for this request';
  end if;
  if coalesce(trim(p_ref),'')='' then raise exception 'invalid: workflow reference is required'; end if;
  select role into actor_role from memberships where association_id=a and user_id=auth.uid() and ended_at is null
    and role in ('secretary','joint_secretary','treasurer','joint_treasurer') order by role limit 1;
  insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category,mom_required,mom_ref)
  values (a,trim(p_ref),'W12','Fund request: '||trim(p_title),jsonb_build_object('Title',trim(p_title),'Amount',p_amount,'Basis',p_basis),
    auth.uid(),my_name(),actor_role,'Fund request',true,trim(p_mom_ref)) returning id into r;
  insert into approval_steps (request_id,seq,role,name,step_type) values (r,1,'ec_member','EC vote','ec_vote');
  insert into approval_steps (request_id,seq,role,name) values (r,2,'president','President');
  insert into fund_requests (association_id,title,request_type,amount,basis,due_day,mom_ref,approval_request_id,created_by)
  values (a,trim(p_title),p_type,p_amount,trim(coalesce(p_basis,'')),nullif(trim(p_due_day),''),trim(p_mom_ref),r,auth.uid())
  returning id into fund_id;
  insert into workflow_action_log (workflow_instance_id,actor_id,action,new_value)
  select workflow_instance_id,auth.uid(),'fund_request_submitted',jsonb_build_object('fund_request_id',fund_id)
  from approval_requests where id=r and workflow_instance_id is not null;
  return fund_id;
end $$;

-- 4. Group visitors: one pass code for the whole group.
alter table visitor_requests add column if not exists guest_count integer not null default 1
  check (guest_count between 1 and 50);
drop function if exists create_visitor_request(uuid, text, text, timestamptz, text, text);
create function create_visitor_request(
  p_flat uuid, p_guest_name text, p_guest_phone text, p_expected_arrival timestamptz,
  p_vehicle_number text default null, p_note text default '', p_guest_count integer default 1
) returns uuid language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); request_id uuid;
begin
  if a is null or not exists (
    select 1 from memberships m where m.association_id = a and m.user_id = auth.uid()
      and m.flat_id = p_flat and m.ended_at is null and m.role in ('owner','resident')
  ) then
    raise exception 'not_allowed: only an active owner or resident of the selected flat can register visitors';
  end if;
  if coalesce(trim(p_guest_name), '') = '' then raise exception 'invalid: enter the visitor name'; end if;
  if coalesce(p_guest_count, 1) not between 1 and 50 then raise exception 'invalid: number of guests must be 1 to 50'; end if;
  if p_expected_arrival < now() - interval '5 minutes' or p_expected_arrival > now() + interval '1 year' then
    raise exception 'invalid: arrival time must be in the next year';
  end if;
  if length(coalesce(p_note, '')) > 240 then raise exception 'invalid: note must be 240 characters or fewer'; end if;
  insert into visitor_requests (association_id, flat_id, guest_name, guest_phone, expected_arrival, vehicle_number, note, guest_count)
  values (a, p_flat, trim(p_guest_name), nullif(trim(p_guest_phone), ''), p_expected_arrival,
    nullif(upper(trim(p_vehicle_number)), ''), trim(coalesce(p_note, '')), coalesce(p_guest_count, 1))
  returning id into request_id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'create_visitor_request', 'visitor_request', request_id::text,
    jsonb_build_object('flat_id', p_flat, 'guest_name', trim(p_guest_name), 'guest_count', coalesce(p_guest_count, 1),
      'expected_arrival', p_expected_arrival));
  return request_id;
end $$;
revoke all on function create_visitor_request(uuid, text, text, timestamptz, text, text, integer) from public;
grant execute on function create_visitor_request(uuid, text, text, timestamptz, text, text, integer) to authenticated;
