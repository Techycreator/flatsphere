create table income_categories (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  status text not null default 'pending' check (status in ('pending', 'active', 'rejected', 'sent_back')),
  request_ref text not null,
  request_id uuid not null unique references approval_requests(id) on delete cascade,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  approved_by uuid references profiles(id),
  approved_at timestamptz
);
create unique index income_categories_name_active_key on income_categories (association_id, lower(name))
  where status in ('pending', 'active', 'sent_back');
alter table income_categories enable row level security;
create policy income_categories_read on income_categories for select using (
  association_id = my_association() and fin_reader(association_id)
);

create table income_entries (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  category_id uuid not null references income_categories(id),
  received_on date not null default current_date,
  amount integer not null check (amount > 0),
  source text,
  description text not null default '',
  recorded_by uuid not null default auth.uid() references profiles(id),
  recorded_by_name text not null default my_name(),
  created_at timestamptz not null default now(),
  constraint income_source_length check (source is null or length(source) <= 160),
  constraint income_description_length check (length(description) <= 500)
);
create index income_entries_association_date_idx on income_entries (association_id, received_on desc);
alter table income_entries enable row level security;
create policy income_entries_read on income_entries for select using (
  association_id = my_association() and fin_reader(association_id)
);

create function request_income_category(p_name text, p_ref text) returns text
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  request_id uuid;
  initiator_role app_role;
  cleaned_name text := trim(coalesce(p_name, ''));
  who text := my_name();
begin
  if a is null or not has_role(a, array['secretary', 'treasurer']::app_role[]) then
    raise exception 'not_allowed: only the Secretary or Treasurer can request an income category';
  end if;
  if cleaned_name = '' or length(cleaned_name) > 80 then
    raise exception 'invalid: category name must be between 1 and 80 characters';
  end if;
  if coalesce(trim(p_ref), '') = '' then raise exception 'invalid: request reference is required'; end if;
  if exists (select 1 from income_categories where association_id = a and lower(name) = lower(cleaned_name)
             and status in ('pending', 'active', 'sent_back')) then
    raise exception 'duplicate: this income category already exists or is awaiting approval';
  end if;
  select role into initiator_role from memberships
    where association_id = a and user_id = auth.uid() and ended_at is null and role in ('secretary', 'treasurer')
    order by case role when 'secretary' then 1 else 2 end limit 1;

  insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name,
    initiator_role, category, mom_required)
  values (a, trim(p_ref), 'W23', 'New income category: ' || cleaned_name,
    jsonb_build_object('Category', cleaned_name), auth.uid(), who, initiator_role, 'Income category', false)
  returning id into request_id;
  insert into approval_steps (request_id, seq, role, name) values (request_id, 1, 'president', 'President');
  insert into income_categories (association_id, name, request_ref, request_id, created_by)
  values (a, cleaned_name, trim(p_ref), request_id, auth.uid());
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'request_income_category', 'income_category', request_id::text,
    jsonb_build_object('name', cleaned_name));
  return trim(p_ref);
end $$;

create function sync_income_category_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r approval_requests;
  next_status text;
begin
  if new.decision = 'pending' then return new; end if;
  select * into r from approval_requests where id = new.request_id;
  if r.code <> 'W23' then return new; end if;
  if exists (select 1 from approval_steps where request_id = new.request_id and decision = 'pending') then
    return new;
  end if;
  next_status := case new.decision when 'approved' then 'active' when 'rejected' then 'rejected' else 'sent_back' end;
  update income_categories set status = next_status,
    approved_by = case when next_status = 'active' then new.decided_by else null end,
    approved_at = case when next_status = 'active' then coalesce(new.decided_at, now()) else null end
  where request_id = new.request_id and association_id = r.association_id;
  return new;
end $$;
create trigger income_category_approval_sync after update of decision on approval_steps
  for each row execute function sync_income_category_approval();

create function record_income(p_category uuid, p_received_on date, p_amount integer, p_source text, p_description text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  entry_id uuid;
  category_name text;
begin
  if a is null or not has_role(a, array['secretary', 'treasurer']::app_role[]) then
    raise exception 'not_allowed: only the Secretary or Treasurer can record income';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid: amount must be greater than zero'; end if;
  if coalesce(trim(p_source), '') <> '' and length(trim(p_source)) > 160 then
    raise exception 'invalid: source must be 160 characters or fewer';
  end if;
  if length(coalesce(p_description, '')) > 500 then raise exception 'invalid: description is too long'; end if;
  select name into category_name from income_categories
    where id = p_category and association_id = a and status = 'active';
  if category_name is null then raise exception 'invalid: choose an approved income category'; end if;
  insert into income_entries (association_id, category_id, received_on, amount, source, description)
  values (a, p_category, coalesce(p_received_on, current_date), p_amount, nullif(trim(p_source), ''), trim(coalesce(p_description, '')))
  returning id into entry_id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'record_income', 'income_entry', entry_id::text,
    jsonb_build_object('category', category_name, 'amount', p_amount, 'received_on', p_received_on));
  return entry_id;
end $$;