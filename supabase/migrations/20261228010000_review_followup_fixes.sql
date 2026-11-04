create or replace function update_member_contact(p_kind text, p_id uuid, p_full_name text, p_mobile text, p_email text)
returns void language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  uid uuid;
  member_role app_role;
  n text := nullif(trim(coalesce(p_full_name, '')), '');
  m text := nullif(regexp_replace(coalesce(p_mobile, ''), '[^0-9+]', '', 'g'), '');
  e text := lower(nullif(trim(coalesce(p_email, '')), ''));
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can change member details';
  end if;
  if n is null then raise exception 'invalid: name is required'; end if;
  if p_kind = 'member' then
    select user_id, role into uid, member_role from memberships
      where id = p_id and association_id = a and ended_at is null;
    if not found then raise exception 'not_found: member not found'; end if;
    if member_role in ('owner', 'resident')
       and (coalesce(trim(p_mobile), '') !~ '^[+0-9() -]{5,24}$' or coalesce(m, '') !~ '^\+?[0-9]{5,24}$') then
      raise exception 'invalid: a valid owner/resident phone number is required';
    end if;
    if m is not null and m !~ '^\+?[0-9]{5,24}$' then raise exception 'invalid: enter a valid phone number'; end if;
    if m is not null and exists (select 1 from profiles where mobile = m and id <> uid) then
      raise exception 'invalid: this mobile number is already used by another member';
    end if;
    update profiles set full_name = n, mobile = m where id = uid;
    update memberships set contact_phone = m
      where id = p_id and association_id = a and role in ('owner', 'resident');
  elsif p_kind = 'invited' then
    if e is null or e !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'invalid: enter a valid email'; end if;
    select role into member_role from invites
      where id = p_id and association_id = a and claimed_at is null for update;
    if not found then raise exception 'not_found: invite not found'; end if;
    if member_role in ('owner', 'resident')
       and (coalesce(trim(p_mobile), '') !~ '^[+0-9() -]{5,24}$' or coalesce(m, '') !~ '^\+?[0-9]{5,24}$') then
      raise exception 'invalid: a valid owner/resident phone number is required';
    end if;
    if m is not null and m !~ '^\+?[0-9]{5,24}$' then raise exception 'invalid: enter a valid phone number'; end if;
    if exists (select 1 from profiles where lower(email) = e) then
      raise exception 'invalid: this email belongs to an existing account; add them through the directory';
    end if;
    update invites set full_name = n, mobile = m, email = e
      where id = p_id and association_id = a and claimed_at is null;
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
  a uuid := my_association();
  n text := nullif(trim(coalesce(p_full_name, '')), '');
  m text := nullif(regexp_replace(coalesce(p_mobile, ''), '[^0-9+]', '', 'g'), '');
  needs_phone boolean;
begin
  if auth.uid() is null then raise exception 'not_allowed'; end if;
  if n is null then raise exception 'invalid: name is required'; end if;
  select exists (
    select 1 from memberships
    where association_id = a and user_id = auth.uid() and ended_at is null and role in ('owner', 'resident')
  ) into needs_phone;
  if (needs_phone or nullif(trim(coalesce(p_mobile, '')), '') is not null)
     and (coalesce(trim(p_mobile), '') !~ '^[+0-9() -]{5,24}$' or coalesce(m, '') !~ '^\+?[0-9]{5,24}$') then
    raise exception 'invalid: a valid owner/resident phone number is required';
  end if;
  if m is not null and exists (select 1 from profiles where mobile = m and id <> auth.uid()) then
    raise exception 'invalid: this mobile number is already used by another member';
  end if;
  update profiles set full_name = n, mobile = m where id = auth.uid();
  update memberships set contact_phone = m
    where association_id = a and user_id = auth.uid() and ended_at is null and role in ('owner', 'resident');
end $$;
revoke all on function update_my_profile(text, text) from public, anon;
grant execute on function update_my_profile(text, text) to authenticated;

create or replace function save_dues_schedule(
  p_enabled boolean, p_mode text, p_rates jsonb, p_rate_per_sqft numeric, p_head_prefix text,
  p_bill_day integer, p_due_day integer, p_late_fee_enabled boolean, p_late_fee_amount integer, p_late_fee_grace_days integer
) returns void language plpgsql security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: only the Treasurer or Joint Treasurer can set automatic bills'; end if;
  if coalesce(trim(p_head_prefix), '') = '' then raise exception 'invalid: enter a bill name, e.g. Maintenance'; end if;
  if p_due_day < p_bill_day then raise exception 'invalid: due day must be on or after the bill day'; end if;
  if jsonb_typeof(p_rates) is distinct from 'object' then raise exception 'invalid: rates must be an object of integer amounts'; end if;
  if exists (
    select 1 from jsonb_each(p_rates) r
    where not case
      when jsonb_typeof(r.value) = 'number' and r.value::text ~ '^(0|[1-9][0-9]{0,9})$'
        then r.value::text::numeric <= 2147483647
      else false
    end
  ) then raise exception 'invalid: every flat-type rate must be a non-negative 32-bit integer'; end if;
  if p_enabled and p_mode = 'flat_type'
     and not exists (select 1 from jsonb_each(p_rates) r where r.value::text::numeric > 0) then
    raise exception 'invalid: enter an amount for at least one flat type';
  end if;
  if p_enabled and p_mode = 'per_sqft' and coalesce(p_rate_per_sqft, 0) <= 0 then raise exception 'invalid: enter the rate per square foot'; end if;
  if p_late_fee_enabled and coalesce(p_late_fee_amount, 0) <= 0 then raise exception 'invalid: enter the late fee amount'; end if;
  insert into dues_schedules as s (association_id, enabled, mode, rates, rate_per_sqft, head_prefix, bill_day, due_day,
                                   late_fee_enabled, late_fee_amount, late_fee_grace_days, updated_by, updated_at)
  values (a, p_enabled, p_mode, p_rates, p_rate_per_sqft, trim(p_head_prefix), p_bill_day, p_due_day,
          p_late_fee_enabled, p_late_fee_amount, p_late_fee_grace_days, auth.uid(), now())
  on conflict (association_id) do update set enabled = excluded.enabled, mode = excluded.mode, rates = excluded.rates,
    rate_per_sqft = excluded.rate_per_sqft, head_prefix = excluded.head_prefix, bill_day = excluded.bill_day,
    due_day = excluded.due_day, late_fee_enabled = excluded.late_fee_enabled, late_fee_amount = excluded.late_fee_amount,
    late_fee_grace_days = excluded.late_fee_grace_days, updated_by = excluded.updated_by, updated_at = now();
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'save_dues_schedule', 'dues_schedules', a::text,
          jsonb_build_object('enabled', p_enabled, 'mode', p_mode, 'rates', p_rates, 'rate_per_sqft', p_rate_per_sqft,
                             'bill_day', p_bill_day, 'due_day', p_due_day, 'late_fee', p_late_fee_enabled,
                             'late_fee_amount', p_late_fee_amount, 'grace', p_late_fee_grace_days));
end $$;
revoke all on function save_dues_schedule(boolean, text, jsonb, numeric, text, integer, integer, boolean, integer, integer) from public, anon;
grant execute on function save_dues_schedule(boolean, text, jsonb, numeric, text, integer, integer, boolean, integer, integer) to authenticated;

create or replace function petty_cash_balance() returns integer
language sql stable security definer set search_path = public as $$
  select case when fin_reader(my_association()) or has_role(my_association(), array['caretaker']::app_role[]) then
    coalesce((select sum(amount) from petty_cash_topups where association_id = my_association()), 0)
    - coalesce((select sum(amount) from expenses where association_id = my_association()
                and paid_from = 'petty_cash'), 0)
  end::integer;
$$;
grant execute on function petty_cash_balance() to authenticated;

create or replace function run_dues_schedules(p_today date default (now() at time zone 'Asia/Kolkata')::date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  s dues_schedules;
  v_head text;
  v_due date;
  n integer;
  total integer := 0;
begin
  for s in
    select d.* from dues_schedules d
    join associations a on a.id = d.association_id
    where d.enabled and a.closed_at is null
  loop
    v_head := s.head_prefix || ' – ' || to_char(p_today, 'Mon YYYY');
    v_due := make_date(extract(year from p_today)::int, extract(month from p_today)::int, s.due_day);
    if extract(day from p_today)::int = s.bill_day then
      insert into dues (association_id, flat_id, head, amount, due_date, created_by)
      select s.association_id, f.id, v_head,
             case when s.mode = 'per_sqft' then round(coalesce(f.sqft, 0) * s.rate_per_sqft)::int
                  else coalesce((s.rates->>f.flat_type)::int, 0) end,
             v_due, s.updated_by
      from flats f where f.association_id = s.association_id and f.retired_at is null
        and (case when s.mode = 'per_sqft' then round(coalesce(f.sqft, 0) * s.rate_per_sqft)
                  else coalesce((s.rates->>f.flat_type)::int, 0) end) > 0
      on conflict (flat_id, head) do nothing;
      get diagnostics n = row_count;
      total := total + n;
      insert into audit_log (association_id, actor, action, entity, entity_id, after)
      values (s.association_id, null, 'auto_raise_dues', 'dues', v_head, jsonb_build_object('due_date', v_due, 'flats', n));
    end if;
    if s.late_fee_enabled then
      insert into dues (association_id, flat_id, head, amount, due_date, created_by)
      select s.association_id, d.flat_id, 'Late fee – ' || d.head, s.late_fee_amount, p_today + 7, s.updated_by
      from dues d left join payments p on p.due_id = d.id and p.flat_id = d.flat_id
      where d.association_id = s.association_id
        and left(d.head, length(s.head_prefix || ' – ')) = s.head_prefix || ' – '
        and d.head not like 'Late fee – %'
        and p_today > d.due_date + s.late_fee_grace_days
      group by d.id, d.flat_id, d.head, d.amount
      having d.amount > coalesce(sum(p.amount), 0)
      on conflict (flat_id, head) do nothing;
      get diagnostics n = row_count;
      total := total + n;
      if n > 0 then
        insert into audit_log (association_id, actor, action, entity, entity_id, after)
        values (s.association_id, null, 'auto_late_fee', 'dues', s.head_prefix,
                jsonb_build_object('amount', s.late_fee_amount, 'flats', n));
      end if;
    end if;
  end loop;
  return total;
end $$;
revoke all on function run_dues_schedules(date) from public, anon, authenticated;
