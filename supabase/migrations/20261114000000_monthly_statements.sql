create table monthly_statements (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  snapshot jsonb not null,
  status text not null default 'awaiting_treasurer'
    check (status in ('awaiting_treasurer','awaiting_secretary','awaiting_president','published','rejected')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  treasurer_approved_by uuid references profiles(id),
  treasurer_approved_at timestamptz,
  secretary_approved_by uuid references profiles(id),
  secretary_approved_at timestamptz,
  president_approved_by uuid references profiles(id),
  president_approved_at timestamptz,
  rejection_note text,
  unique (association_id,period_start)
);
create index monthly_statements_period_idx on monthly_statements(association_id,period_start desc);
alter table monthly_statements enable row level security;
create policy monthly_statements_read on monthly_statements for select using (
  association_id=my_association() and fin_reader(association_id)
);

create function create_monthly_statement(p_period_start date) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  period_end date;
  statement_id uuid;
  data jsonb;
begin
  if a is null or not has_role(a,array['treasurer','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: Treasurer access required to create a statement';
  end if;
  if p_period_start is null or date_trunc('month',p_period_start)::date<>p_period_start or p_period_start>current_date then
    raise exception 'invalid: choose the first day of a completed or current month';
  end if;
  period_end := (p_period_start + interval '1 month - 1 day')::date;
  select jsonb_build_object(
    'income',coalesce((select jsonb_agg(jsonb_build_object('date',e.received_on,'category',c.name,'amount',e.amount,'source',e.source,'description',e.description))
      from income_entries e join income_categories c on c.id=e.category_id
      where e.association_id=a and e.received_on between p_period_start and period_end),'[]'::jsonb),
    'expenses',coalesce((select jsonb_agg(jsonb_build_object('date',e.spent_on,'reference',e.ref_no,'category',e.category,'vendor',e.vendor,'description',e.description,'amount',e.amount))
      from expenses e where e.association_id=a and e.status='approved' and e.spent_on between p_period_start and period_end),'[]'::jsonb),
    'dues',coalesce((select jsonb_agg(jsonb_build_object('flat',f.number,'head',d.head,'amount',d.amount,'paid',coalesce(p.paid,0),'pending',greatest(d.amount-coalesce(p.paid,0),0),'due_date',d.due_date))
      from dues d join flats f on f.id=d.flat_id
      left join lateral (select sum(pm.amount)::integer as paid from payments pm where pm.due_id=d.id and pm.flat_id=d.flat_id and pm.paid_on<=period_end) p on true
      where d.association_id=a and d.due_date between p_period_start and period_end),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(jsonb_build_object('date',p.paid_on,'flat',f.number,'amount',p.amount,'mode',p.mode,'receipt',p.receipt_no,'reference',p.reference))
      from payments p join flats f on f.id=p.flat_id where p.association_id=a and p.paid_on between p_period_start and period_end),'[]'::jsonb),
    'totals',jsonb_build_object(
      'income',coalesce((select sum(e.amount) from income_entries e where e.association_id=a and e.received_on between p_period_start and period_end),0),
      'approved_expenses',coalesce((select sum(e.amount) from expenses e where e.association_id=a and e.status='approved' and e.spent_on between p_period_start and period_end),0),
      'payments_received',coalesce((select sum(p.amount) from payments p where p.association_id=a and p.paid_on between p_period_start and period_end),0)
    )
  ) into data;
  insert into monthly_statements(association_id,period_start,period_end,snapshot,created_by)
  values(a,p_period_start,period_end,data,auth.uid())
  on conflict(association_id,period_start) do update set
    period_end=excluded.period_end,snapshot=excluded.snapshot,status='awaiting_treasurer',created_by=excluded.created_by,
    created_at=now(),treasurer_approved_by=null,treasurer_approved_at=null,
    secretary_approved_by=null,secretary_approved_at=null,president_approved_by=null,president_approved_at=null,
    rejection_note=null
  where monthly_statements.status='rejected'
  returning id into statement_id;
  if statement_id is null then raise exception 'duplicate: a statement already exists for that month'; end if;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'create_monthly_statement','monthly_statement',statement_id::text,jsonb_build_object('period_start',p_period_start,'period_end',period_end));
  insert into app_notifications(association_id,user_id,event_key,title,body,action_path)
  select a,m.user_id,'monthly-statement:'||statement_id::text||':treasurer','Monthly statement ready','Statement approval is waiting for the Treasurer.','/finance'
  from memberships m where m.association_id=a and m.ended_at is null and m.role in ('treasurer','joint_treasurer') and m.user_id<>auth.uid()
  on conflict(association_id,user_id,event_key) do nothing;
  return statement_id;
end $$;

create function list_monthly_statements()
returns setof monthly_statements language plpgsql stable security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not is_member(a) then raise exception 'not_allowed: association membership required'; end if;
  return query
  select s.id,s.association_id,s.period_start,s.period_end,
    case when fin_reader(a) then s.snapshot else jsonb_build_object('totals',s.snapshot->'totals') end,
    s.status,s.created_by,s.created_at,s.treasurer_approved_by,s.treasurer_approved_at,
    s.secretary_approved_by,s.secretary_approved_at,s.president_approved_by,s.president_approved_at,s.rejection_note
  from monthly_statements s where s.association_id=a and (s.status='published' or fin_reader(a))
  order by s.period_start desc;
end $$;

create function decide_monthly_statement(p_statement uuid,p_action text,p_note text default null) returns void
language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  s monthly_statements;
  required_role app_role;
  stage_allowed boolean;
  next_status text;
  event_title text;
begin
  select * into s from monthly_statements where id=p_statement and association_id=a for update;
  if s.id is null then raise exception 'not_found: statement not found'; end if;
  required_role := case s.status when 'awaiting_treasurer' then 'treasurer'::app_role when 'awaiting_secretary' then 'secretary'::app_role when 'awaiting_president' then 'president'::app_role else null end;
  if required_role is null then raise exception 'invalid: statement is not awaiting approval'; end if;
  stage_allowed := case when s.status='awaiting_treasurer'
    then has_role(a,array['treasurer','joint_treasurer']::app_role[])
    else has_role(a,array[required_role]) end;
  if not stage_allowed then raise exception 'not_allowed: this statement is awaiting the %',required_role; end if;
  if auth.uid()=s.created_by or auth.uid()=s.treasurer_approved_by or auth.uid()=s.secretary_approved_by then
    raise exception 'maker-checker: each statement approval must come from a different person';
  end if;
  if p_action='reject' then
    if coalesce(trim(p_note),'')='' then raise exception 'invalid: a rejection reason is required'; end if;
    update monthly_statements set status='rejected',rejection_note=trim(p_note) where id=s.id;
    insert into audit_log(association_id,actor,action,entity,entity_id,after)
    values(a,auth.uid(),'reject_monthly_statement','monthly_statement',s.id::text,jsonb_build_object('note',trim(p_note)));
    return;
  elsif p_action<>'approve' then
    raise exception 'invalid: unsupported statement decision';
  end if;
  next_status := case s.status when 'awaiting_treasurer' then 'awaiting_secretary' when 'awaiting_secretary' then 'awaiting_president' else 'published' end;
  update monthly_statements set status=next_status,
    treasurer_approved_by=case when s.status='awaiting_treasurer' then auth.uid() else treasurer_approved_by end,
    treasurer_approved_at=case when s.status='awaiting_treasurer' then now() else treasurer_approved_at end,
    secretary_approved_by=case when required_role='secretary' then auth.uid() else secretary_approved_by end,
    secretary_approved_at=case when required_role='secretary' then now() else secretary_approved_at end,
    president_approved_by=case when required_role='president' then auth.uid() else president_approved_by end,
    president_approved_at=case when required_role='president' then now() else president_approved_at end
  where id=s.id;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'approve_monthly_statement','monthly_statement',s.id::text,jsonb_build_object('stage',required_role,'status',next_status));
  if next_status<>'published' then
    event_title := 'monthly-statement:'||s.id::text||':'||next_status;
    insert into app_notifications(association_id,user_id,event_key,title,body,action_path)
    select a,m.user_id,event_title,'Monthly statement approval needed',
      'Statement approval is waiting for the '||case next_status when 'awaiting_secretary' then 'Secretary' else 'President' end||'.','/finance'
    from memberships m where m.association_id=a and m.ended_at is null
      and m.role=case next_status when 'awaiting_secretary' then 'secretary'::app_role else 'president'::app_role end
      and m.user_id<>auth.uid()
    on conflict(association_id,user_id,event_key) do nothing;
  end if;
end $$;

revoke all on function create_monthly_statement(date) from public;
revoke all on function list_monthly_statements() from public;
revoke all on function decide_monthly_statement(uuid,text,text) from public;
grant execute on function create_monthly_statement(date) to authenticated;
grant execute on function list_monthly_statements() to authenticated;
grant execute on function decide_monthly_statement(uuid,text,text) to authenticated;
