-- President/Secretary edit an owner's or tenant's contact details; members edit their own profile.
create or replace function update_member_contact(p_kind text, p_id uuid, p_full_name text, p_mobile text, p_email text)
returns void language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  uid uuid;
  n text := nullif(trim(coalesce(p_full_name, '')), '');
  m text := nullif(regexp_replace(coalesce(p_mobile, ''), '[^0-9+]', '', 'g'), '');
  e text := lower(nullif(trim(coalesce(p_email, '')), ''));
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can change member details';
  end if;
  if n is null then raise exception 'invalid: name is required'; end if;
  if p_kind = 'member' then
    select user_id into uid from memberships where id = p_id and association_id = a and ended_at is null;
    if uid is null then raise exception 'not_found: member not found'; end if;
    if m is not null and exists (select 1 from profiles where mobile = m and id <> uid) then
      raise exception 'invalid: this mobile number is already used by another member';
    end if;
    update profiles set full_name = n, mobile = m where id = uid;
  elsif p_kind = 'invited' then
    if e is null or e !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'invalid: enter a valid email'; end if;
    update invites set full_name = n, mobile = m, email = e where id = p_id and association_id = a and claimed_at is null;
    if not found then raise exception 'not_found: invite not found'; end if;
  else
    raise exception 'invalid: unsupported member record';
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'update_member_contact', 'membership', p_id::text,
          jsonb_build_object('full_name', n, 'mobile', m, 'email', e));
end $$;
revoke all on function update_member_contact(text, uuid, text, text, text) from public, anon;
grant execute on function update_member_contact(text, uuid, text, text, text) to authenticated;

create or replace function update_my_profile(p_full_name text, p_mobile text) returns void
language plpgsql security definer set search_path = public as $$
declare
  n text := nullif(trim(coalesce(p_full_name, '')), '');
  m text := nullif(regexp_replace(coalesce(p_mobile, ''), '[^0-9+]', '', 'g'), '');
begin
  if auth.uid() is null then raise exception 'not_allowed'; end if;
  if n is null then raise exception 'invalid: name is required'; end if;
  if m is not null and exists (select 1 from profiles where mobile = m and id <> auth.uid()) then
    raise exception 'invalid: this mobile number is already used by another member';
  end if;
  update profiles set full_name = n, mobile = m where id = auth.uid();
end $$;
revoke all on function update_my_profile(text, text) from public, anon;
grant execute on function update_my_profile(text, text) to authenticated;

-- Caretaker petty cash: the Treasurer hands over cash; the caretaker records spends as expenses paid from it,
-- which still go through Treasurer verification and President approval.
alter table expenses add column if not exists paid_from text not null default 'association'
  check (paid_from in ('association', 'petty_cash'));

create table if not exists petty_cash_topups (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  amount integer not null check (amount > 0),
  given_on date not null default current_date,
  note text not null default '',
  entered_by uuid not null default auth.uid() references profiles(id),
  entered_by_name text default my_name(),
  created_at timestamptz not null default now()
);
alter table petty_cash_topups enable row level security;
create policy petty_topups_read on petty_cash_topups for select using (
  association_id = my_association()
  and (fin_reader(association_id) or has_role(association_id, array['caretaker']::app_role[])));
create policy petty_topups_insert on petty_cash_topups for insert with check (
  association_id = my_association() and entered_by = auth.uid() and entered_by_name is not distinct from my_name()
  and has_role(association_id, array['admin','treasurer','joint_treasurer']::app_role[]));

create or replace function petty_cash_balance() returns integer
language sql stable security definer set search_path = public as $$
  select case when fin_reader(my_association()) or has_role(my_association(), array['caretaker']::app_role[]) then
    coalesce((select sum(amount) from petty_cash_topups where association_id = my_association()), 0)
    - coalesce((select sum(amount) from expenses where association_id = my_association()
                and paid_from = 'petty_cash' and status <> 'sent_back'), 0)
  end::integer;
$$;
grant execute on function petty_cash_balance() to authenticated;

drop policy expenses_read on expenses;
create policy expenses_read on expenses for select using (
  fin_reader(association_id) or (association_id = my_association() and entered_by = auth.uid()));

drop policy expenses_insert on expenses;
create policy expenses_insert on expenses for insert with check (
  (expense_maker(association_id)
   or (paid_from = 'petty_cash' and association_id = my_association()
       and has_role(association_id, array['caretaker']::app_role[])))
  and entered_by = auth.uid() and status = 'awaiting_treasurer'
  and verified_by is null and approved_by is null and not flagged
  and entered_by_name is not distinct from my_name()
  and not exists (select 1 from unnest(bill_paths) p where p not like association_id::text || '/%'));

drop policy bills_upload on storage.objects;
create policy bills_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'bills' and (storage.foldername(name))[1] = my_association()::text
  and (expense_maker(my_association()) or has_role(my_association(), array['treasurer','caretaker']::app_role[])));
