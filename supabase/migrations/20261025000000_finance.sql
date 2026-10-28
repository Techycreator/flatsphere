-- Finance: opening balance, dues, payments received, and expenses with bill photos (maker-checker).
create function fin_reader(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role(assoc, array['admin','president','secretary','treasurer','vice_president','joint_secretary',
                               'joint_treasurer','ec_member','auditor']::app_role[]);
$$;
create function fin_recorder(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role(assoc, array['admin','treasurer','joint_treasurer']::app_role[]);
$$;
create function expense_maker(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role(assoc, array['admin','treasurer','joint_treasurer','secretary','joint_secretary']::app_role[]);
$$;
create function my_name() returns text
language sql stable security definer set search_path = public as $$
  select full_name from profiles where id = auth.uid();
$$;

create table opening_balances (
  association_id uuid primary key default my_association() references associations(id) on delete cascade,
  account_name text not null default 'Bank account',
  amount bigint not null,
  as_of date not null,
  entered_by uuid not null default auth.uid() references profiles(id),
  updated_at timestamptz not null default now()
);
alter table opening_balances enable row level security;
create policy ob_read on opening_balances for select using (fin_reader(association_id));
create policy ob_insert on opening_balances for insert
  with check (fin_recorder(association_id) and entered_by = auth.uid());
create policy ob_update on opening_balances for update using (fin_recorder(association_id))
  with check (fin_recorder(association_id) and entered_by = auth.uid());

create table dues (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  flat_id uuid not null references flats(id),
  head text not null,
  amount integer not null check (amount > 0),
  due_date date not null,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  unique (flat_id, head)
);
alter table dues enable row level security;
create policy dues_read on dues for select
  using (fin_reader(association_id) or flat_id in (select my_flat_ids(association_id)));
create policy dues_insert on dues for insert with check (
  fin_recorder(association_id) and created_by = auth.uid()
  and exists (select 1 from flats f where f.id = dues.flat_id and f.association_id = dues.association_id));

create sequence receipt_seq start 5001;
create table payments (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  flat_id uuid not null references flats(id),
  due_id uuid references dues(id),
  amount integer not null check (amount > 0),
  paid_on date not null default current_date,
  mode text not null check (mode in ('cash','upi','bank_transfer','cheque','online')),
  reference text,
  receipt_no text not null unique default ('RCT-' || nextval('receipt_seq')),
  recorded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table payments enable row level security;
create policy payments_read on payments for select
  using (fin_reader(association_id) or flat_id in (select my_flat_ids(association_id)));
create policy payments_insert on payments for insert with check (
  fin_recorder(association_id) and recorded_by = auth.uid()
  and exists (select 1 from flats f where f.id = payments.flat_id and f.association_id = payments.association_id)
  and (payments.due_id is null or exists (select 1 from dues d where d.id = payments.due_id and d.flat_id = payments.flat_id)));

create sequence expense_seq start 1001;
create table expenses (
  id uuid primary key default gen_random_uuid(),
  ref_no text not null unique default ('EXP-' || nextval('expense_seq')),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  spent_on date not null,
  category text not null,
  vendor text not null,
  description text not null default '',
  amount integer not null check (amount > 0),
  status text not null default 'awaiting_treasurer'
    check (status in ('awaiting_treasurer','awaiting_president','approved','sent_back')),
  bill_paths text[] not null default '{}',
  entered_by uuid not null default auth.uid() references profiles(id),
  entered_by_name text default my_name(),
  verified_by uuid references profiles(id),
  approved_by uuid references profiles(id),
  flagged boolean not null default false,
  comment text,
  created_at timestamptz not null default now()
);
alter table expenses enable row level security;
create policy expenses_read on expenses for select using (fin_reader(association_id));
create policy expenses_insert on expenses for insert with check (
  expense_maker(association_id) and entered_by = auth.uid() and status = 'awaiting_treasurer'
  and verified_by is null and approved_by is null and not flagged
  and entered_by_name is not distinct from my_name()
  and not exists (select 1 from unnest(bill_paths) p where p not like association_id::text || '/%'));

grant usage, select on sequence receipt_seq, expense_seq to authenticated;

create function raise_dues(p_head text, p_due_date date, p_rates jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); n integer;
begin
  if a is null or not fin_recorder(a) then
    raise exception 'not_allowed: only the Treasurer or Joint Treasurer can raise dues';
  end if;
  if coalesce(trim(p_head), '') = '' then raise exception 'invalid: enter a name, e.g. Maintenance – Nov 2026'; end if;
  insert into dues (association_id, flat_id, head, amount, due_date, created_by)
    select a, f.id, trim(p_head), (p_rates->>f.flat_type)::int, p_due_date, auth.uid()
    from flats f where f.association_id = a and coalesce((p_rates->>f.flat_type)::int, 0) > 0
    on conflict (flat_id, head) do nothing;
  get diagnostics n = row_count;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'raise_dues', 'dues', trim(p_head),
            jsonb_build_object('due_date', p_due_date, 'rates', p_rates, 'flats', n));
  return n;
end $$;

create function add_expense_bill(p_id uuid, p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); e expenses;
begin
  select * into e from expenses where id = p_id and association_id = a for update;
  if e.id is null then raise exception 'not_found'; end if;
  if e.status not in ('awaiting_treasurer','sent_back') then
    raise exception 'invalid: bills can only be added before the Treasurer verifies the expense';
  end if;
  if not (e.entered_by = auth.uid() or has_role(a, array['treasurer']::app_role[])) then
    raise exception 'not_allowed: only the person who entered it or the Treasurer can add bills';
  end if;
  if p_path not like a::text || '/%' then raise exception 'invalid: wrong file location'; end if;
  update expenses set bill_paths = bill_paths || p_path where id = e.id;
  insert into audit_log (association_id, actor, action, entity, entity_id)
    values (a, auth.uid(), 'expense_add_bill', 'expense', e.ref_no);
end $$;

-- verify (Treasurer) -> approve (President); the maker can't check their own entry, and one person can't do both steps.
create function decide_expense(p_id uuid, p_action text, p_comment text default null) returns void
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
    update expenses set flagged = not flagged where id = e.id;
  else
    raise exception 'invalid: unknown action %', p_action;
  end case;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
    values (a, me, 'expense_' || p_action, 'expense', e.ref_no, jsonb_build_object('status', e.status),
            jsonb_build_object('comment', p_comment));
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bills', 'bills', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;
create policy bills_read on storage.objects for select to authenticated using (
  bucket_id = 'bills' and (storage.foldername(name))[1] = my_association()::text and fin_reader(my_association()));
create policy bills_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'bills' and (storage.foldername(name))[1] = my_association()::text
  and (expense_maker(my_association()) or has_role(my_association(), array['treasurer']::app_role[])));
