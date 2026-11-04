alter table approval_requests
  add column if not exists mom_meeting_id uuid references association_meetings(id) on delete set null;
alter table fund_requests
  add column if not exists mom_meeting_id uuid references association_meetings(id) on delete set null;

create or replace function resolve_approved_ec_meeting(p_assoc uuid, p_ref text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare meeting_id uuid; matching_ids uuid[]; meeting_count integer;
begin
  if p_assoc is null or coalesce(trim(p_ref), '') = '' then return null; end if;
  if trim(p_ref) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select id into meeting_id from association_meetings
    where id = trim(p_ref)::uuid and association_id = p_assoc
      and meeting_type = 'Executive Committee' and minutes_status = 'approved';
    return meeting_id;
  end if;
  select array_agg(id), count(*)::integer into matching_ids, meeting_count
  from association_meetings
  where association_id = p_assoc and meeting_type = 'Executive Committee' and minutes_status = 'approved'
    and title || ' · ' || to_char(starts_at at time zone 'Asia/Kolkata', 'FMDD Mon YYYY') = trim(p_ref);
  if meeting_count = 1 then return matching_ids[1]; end if;
  return null;
end $$;
revoke all on function resolve_approved_ec_meeting(uuid, text) from public, anon, authenticated;

create or replace function request_payment_reversal(p_payment uuid, p_reason text, p_ref text) returns uuid
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); p payments; r uuid; fno text; due_head text; actor_role app_role;
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: only the Treasurer can reverse a payment'; end if;
  select * into p from payments where id = p_payment and association_id = a for update;
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
    from ec_voter_ids(r.association_id, null) u
    left join profiles p on p.id = u
    left join ec_votes v on v.request_id = p_request and v.voter = u
    order by 2;
end $$;

create or replace function record_ec_meeting_votes(p_request uuid, p_mom_ref text, p_votes jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  r approval_requests;
  s approval_steps;
  me uuid := auth.uid();
  e jsonb;
  meeting_id uuid;
  meeting_label text;
  meeting association_meetings;
  total integer;
  y integer;
  n integer;
  need integer;
  verdict text;
  added integer := 0;
  requested_meeting uuid;
begin
  select * into r from approval_requests where id = p_request for update;
  if r.id is null or r.association_id is distinct from my_association() then raise exception 'not_found: request not found'; end if;
  if not has_role(r.association_id, array['president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the Secretary or President can record meeting votes';
  end if;
  if me = r.initiator then raise exception 'not_allowed: the person who raised this request cannot record its votes'; end if;
  select * into s from approval_steps where request_id = p_request and decision = 'pending' order by seq limit 1 for update;
  if s.id is null or s.step_type <> 'ec_vote' then raise exception 'not_open: the EC vote is not open for this request'; end if;

  if coalesce(trim(p_mom_ref), '') <> '' then
    requested_meeting := resolve_approved_ec_meeting(r.association_id, p_mom_ref);
    if requested_meeting is null then
      raise exception 'invalid: select approved EC meeting minutes (MOM) for this association';
    end if;
    if r.mom_meeting_id is not null and requested_meeting <> r.mom_meeting_id then
      raise exception 'invalid: the selected minutes do not match this request';
    end if;
  end if;
  meeting_id := coalesce(r.mom_meeting_id, requested_meeting);
  if meeting_id is null and coalesce(trim(r.mom_ref), '') <> '' then
    meeting_id := resolve_approved_ec_meeting(r.association_id, r.mom_ref);
  end if;
  if meeting_id is null then
    raise exception 'invalid: select the approved minutes (MOM) where the vote was taken';
  end if;
  select * into meeting from association_meetings
  where id = meeting_id and association_id = r.association_id
    and meeting_type = 'Executive Committee' and minutes_status = 'approved';
  if meeting.id is null then raise exception 'invalid: approved EC meeting minutes were not found'; end if;
  meeting_label := meeting.title || ' · ' || to_char(meeting.starts_at at time zone 'Asia/Kolkata', 'FMDD Mon YYYY');
  update approval_requests set mom_meeting_id = meeting.id, mom_ref = meeting_label where id = p_request;

  for e in select * from jsonb_array_elements(coalesce(p_votes, '[]'::jsonb)) loop
    if e->>'vote' not in ('yes','no') then continue; end if;
    if not exists (select 1 from ec_voter_ids(r.association_id, null) u where u = (e->>'voter')::uuid) then
      raise exception 'invalid: only EC members can be recorded';
    end if;
    insert into ec_votes (request_id, voter, voter_name, vote, comment, recorded_by, source)
    select p_request, p.id, coalesce(p.full_name, 'EC member'), e->>'vote',
      'Recorded from MOM: ' || meeting_label, me, 'meeting'
    from profiles p where p.id = (e->>'voter')::uuid
    on conflict (request_id, voter) do nothing;
    if found then added := added + 1; end if;
  end loop;
  if added = 0 then raise exception 'invalid: mark Yes or No for at least one member who has not voted yet'; end if;
  select count(*) into total from ec_voter_ids(r.association_id, null);
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
    jsonb_build_object('mom', meeting_label, 'recorded', added, 'yes', y, 'no', n, 'of', total, 'result', verdict));
end $$;

create or replace function request_fund(p_title text,p_type text,p_amount integer,p_basis text,p_due_day text,p_mom_ref text,p_ref text)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  a uuid := my_association();
  r uuid;
  fund_id uuid;
  actor_role app_role;
  meeting_id uuid;
  meeting association_meetings;
  meeting_label text;
begin
  if a is null or not has_role(a,array['secretary','joint_secretary','treasurer','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: Secretary or Treasurer role required to submit a fund request';
  end if;
  if coalesce(trim(p_title),'')='' or p_type not in ('recurring','ad_hoc') then raise exception 'invalid: enter a title and request type'; end if;
  if p_amount is not null and p_amount<=0 then raise exception 'invalid: amount must be greater than zero'; end if;
  if coalesce(trim(p_ref),'')='' then raise exception 'invalid: workflow reference is required'; end if;
  if trim(coalesce(p_mom_ref, '')) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'invalid: select approved EC meeting minutes (MOM)';
  end if;
  meeting_id := resolve_approved_ec_meeting(a, p_mom_ref);
  if meeting_id is null then raise exception 'invalid: select approved EC meeting minutes (MOM) for this association'; end if;
  select * into meeting from association_meetings
  where id = meeting_id and association_id = a and meeting_type = 'Executive Committee' and minutes_status = 'approved';
  if meeting.id is null then raise exception 'invalid: select approved EC meeting minutes (MOM) for this association'; end if;
  meeting_label := meeting.title || ' · ' || to_char(meeting.starts_at at time zone 'Asia/Kolkata', 'FMDD Mon YYYY');
  select role into actor_role from memberships where association_id=a and user_id=auth.uid() and ended_at is null
    and role in ('secretary','joint_secretary','treasurer','joint_treasurer') order by role limit 1;
  insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category,mom_required,mom_ref,mom_meeting_id)
  values (a,trim(p_ref),'W12','Fund request: '||trim(p_title),jsonb_build_object('Title',trim(p_title),'Amount',p_amount,'Basis',p_basis),
    auth.uid(),my_name(),actor_role,'Fund request',true,meeting_label,meeting.id) returning id into r;
  insert into approval_steps (request_id,seq,role,name,step_type) values (r,1,'ec_member','EC vote','ec_vote');
  insert into approval_steps (request_id,seq,role,name) values (r,2,'president','President');
  insert into fund_requests (association_id,title,request_type,amount,basis,due_day,mom_ref,mom_meeting_id,approval_request_id,created_by)
  values (a,trim(p_title),p_type,p_amount,trim(coalesce(p_basis,'')),nullif(trim(p_due_day),''),meeting_label,meeting.id,r,auth.uid())
  returning id into fund_id;
  insert into workflow_action_log (workflow_instance_id,actor_id,action,new_value)
  select workflow_instance_id,auth.uid(),'fund_request_submitted',jsonb_build_object('fund_request_id',fund_id)
  from approval_requests where id=r and workflow_instance_id is not null;
  return fund_id;
end $$;

create or replace function sync_fund_request_approval() returns trigger
language plpgsql security definer set search_path=public as $$
declare r approval_requests; s text;
begin
  if old.decision is not distinct from new.decision or new.decision='pending' then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  if r.code<>'W12' then return new; end if;
  if new.decision in ('rejected', 'sent_back') then
    s := case new.decision when 'rejected' then 'rejected' else 'sent_back' end;
  elsif exists(select 1 from approval_steps where request_id=new.request_id and decision='pending') then
    return new;
  else
    s := 'active';
  end if;
  update fund_requests set status=s,approved_by=case when s='active' then new.decided_by else null end,
    approved_at=case when s='active' then now() else null end where approval_request_id=new.request_id;
  return new;
end $$;

do $$
declare def text;
begin
  select pg_get_functiondef('public.decide_step_family_base(uuid,decision,text)'::regprocedure) into def;
  if position(
    'if exists (select 1 from approval_steps where request_id = req and decided_by = auth.uid()) and not repeated_president then'
    in def
  ) = 0 then
    raise exception 'decide_step_family_base duplicate-decision guard not found';
  end if;
  def := replace(
    def,
    'if exists (select 1 from approval_steps where request_id = req and decided_by = auth.uid()) and not repeated_president then',
    'if exists (select 1 from approval_steps where request_id = req and decided_by = auth.uid() and step_type <> ''ec_vote'') and not repeated_president then'
  );
  execute def;
end $$;

revoke all on function request_fund(text,text,integer,text,text,text,text) from public, anon;
grant execute on function request_fund(text,text,integer,text,text,text,text) to authenticated;
revoke all on function record_ec_meeting_votes(uuid,text,jsonb) from public, anon;
grant execute on function record_ec_meeting_votes(uuid,text,jsonb) to authenticated;
revoke all on function ec_meeting_voters(uuid) from public, anon;
grant execute on function ec_meeting_voters(uuid) to authenticated;
