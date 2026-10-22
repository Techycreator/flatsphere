create table annual_budgets (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  fiscal_year_start date not null,
  fiscal_year_end date not null,
  category_amounts jsonb not null check (jsonb_typeof(category_amounts)='object'),
  gbm_resolution_ref text not null check (length(trim(gbm_resolution_ref)) between 1 and 160),
  gbm_resolution_date date not null,
  status text not null default 'awaiting_secretary'
    check (status in ('awaiting_secretary','awaiting_president','approved','rejected')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  secretary_approved_by uuid references profiles(id),
  secretary_approved_at timestamptz,
  president_approved_by uuid references profiles(id),
  president_approved_at timestamptz,
  rejection_note text,
  unique (association_id,fiscal_year_start),
  check (fiscal_year_end>=fiscal_year_start)
);
create index annual_budgets_association_year_idx on annual_budgets(association_id,fiscal_year_start desc);
alter table annual_budgets enable row level security;
create policy annual_budgets_read on annual_budgets for select using (
  association_id=my_association() and (status='approved' and is_member(association_id) or fin_reader(association_id))
);

create function submit_annual_budget(
  p_fiscal_year_start date,p_fiscal_year_end date,p_category_amounts jsonb,p_gbm_resolution_ref text,p_gbm_resolution_date date
) returns uuid language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); budget_id uuid; item record;
begin
  if a is null or not has_role(a,array['treasurer','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: Treasurer access required to submit an annual budget';
  end if;
  if p_fiscal_year_start is null or p_fiscal_year_end is null or p_fiscal_year_end<p_fiscal_year_start then
    raise exception 'invalid: choose a valid fiscal-year range';
  end if;
  if coalesce(trim(p_gbm_resolution_ref),'')='' or p_gbm_resolution_date is null then
    raise exception 'invalid: AGM/GBM resolution reference and date are required';
  end if;
  if p_category_amounts is null or jsonb_typeof(p_category_amounts)<>'object' or p_category_amounts='{}'::jsonb then
    raise exception 'invalid: enter at least one category budget';
  end if;
  for item in select key,value from jsonb_each(p_category_amounts) loop
    if length(trim(item.key))=0 or length(item.key)>120 or jsonb_typeof(item.value) is distinct from 'number'
        or (item.value#>>'{}') !~ '^\d+$' or (item.value#>>'{}')::numeric<=0 then
      raise exception 'invalid: each budget category must have a positive whole-rupee amount';
    end if;
  end loop;
  insert into annual_budgets(association_id,fiscal_year_start,fiscal_year_end,category_amounts,
    gbm_resolution_ref,gbm_resolution_date,created_by)
  values(a,p_fiscal_year_start,p_fiscal_year_end,p_category_amounts,trim(p_gbm_resolution_ref),p_gbm_resolution_date,auth.uid())
  on conflict(association_id,fiscal_year_start) do update set
    fiscal_year_end=excluded.fiscal_year_end,category_amounts=excluded.category_amounts,
    gbm_resolution_ref=excluded.gbm_resolution_ref,gbm_resolution_date=excluded.gbm_resolution_date,
    status='awaiting_secretary',created_by=excluded.created_by,created_at=now(),
    secretary_approved_by=null,secretary_approved_at=null,president_approved_by=null,president_approved_at=null,rejection_note=null
  where annual_budgets.status='rejected'
  returning id into budget_id;
  if budget_id is null then raise exception 'duplicate: a budget already exists for this fiscal year'; end if;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'submit_annual_budget','annual_budget',budget_id::text,
    jsonb_build_object('fiscal_year_start',p_fiscal_year_start,'fiscal_year_end',p_fiscal_year_end,'resolution',trim(p_gbm_resolution_ref)));
  insert into app_notifications(association_id,user_id,event_key,title,body,action_path)
  select a,m.user_id,'annual-budget:'||budget_id::text||':secretary','Annual budget review requested',
    'Review the annual budget and AGM/GBM resolution.','/finance'
  from memberships m where m.association_id=a and m.ended_at is null and m.role='secretary' and m.user_id<>auth.uid()
  on conflict(association_id,user_id,event_key) do nothing;
  return budget_id;
end $$;

create function list_annual_budgets()
returns setof annual_budgets language plpgsql stable security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not is_member(a) then raise exception 'not_allowed: association membership required'; end if;
  return query select b.* from annual_budgets b where b.association_id=a
    and (b.status='approved' or fin_reader(a)) order by b.fiscal_year_start desc;
end $$;

create function decide_annual_budget(p_budget uuid,p_action text,p_note text default null) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); b annual_budgets; next_status text;
begin
  select * into b from annual_budgets where id=p_budget and association_id=a for update;
  if b.id is null then raise exception 'not_found: budget not found'; end if;
  if p_action not in ('approve','reject') then raise exception 'invalid: unsupported budget decision'; end if;
  if b.status='awaiting_secretary' then
    if not has_role(a,array['secretary']::app_role[]) then raise exception 'not_allowed: Secretary approval required'; end if;
  elsif b.status='awaiting_president' then
    if not has_role(a,array['president']::app_role[]) then raise exception 'not_allowed: President approval required'; end if;
  else
    raise exception 'invalid: budget is not awaiting approval';
  end if;
  if auth.uid()=b.created_by or auth.uid()=b.secretary_approved_by then
    raise exception 'maker-checker: budget approvals must come from different people';
  end if;
  if p_action='reject' then
    if coalesce(trim(p_note),'')='' then raise exception 'invalid: rejection reason is required'; end if;
    update annual_budgets set status='rejected',rejection_note=trim(p_note) where id=b.id;
    next_status:='rejected';
  else
    next_status:=case b.status when 'awaiting_secretary' then 'awaiting_president' else 'approved' end;
    update annual_budgets set status=next_status,
      secretary_approved_by=case when b.status='awaiting_secretary' then auth.uid() else secretary_approved_by end,
      secretary_approved_at=case when b.status='awaiting_secretary' then now() else secretary_approved_at end,
      president_approved_by=case when b.status='awaiting_president' then auth.uid() else president_approved_by end,
      president_approved_at=case when b.status='awaiting_president' then now() else president_approved_at end
    where id=b.id;
    if next_status='awaiting_president' then
      insert into app_notifications(association_id,user_id,event_key,title,body,action_path)
      select a,m.user_id,'annual-budget:'||b.id::text||':president','Annual budget approval requested',
        'Approve the annual budget linked to its AGM/GBM resolution.','/finance'
      from memberships m where m.association_id=a and m.ended_at is null and m.role='president' and m.user_id<>auth.uid()
      on conflict(association_id,user_id,event_key) do nothing;
    end if;
  end if;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),case when p_action='approve' then 'approve_annual_budget' else 'reject_annual_budget' end,
    'annual_budget',b.id::text,jsonb_build_object('status',next_status,'note',nullif(trim(coalesce(p_note,'')),'')));
end $$;

revoke all on function submit_annual_budget(date,date,jsonb,text,date) from public;
revoke all on function list_annual_budgets() from public;
revoke all on function decide_annual_budget(uuid,text,text) from public;
grant execute on function submit_annual_budget(date,date,jsonb,text,date) to authenticated;
grant execute on function list_annual_budgets() to authenticated;
grant execute on function decide_annual_budget(uuid,text,text) to authenticated;
