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
    update memberships set contact_phone = m
      where id = p_id and association_id = a and role in ('owner', 'resident');
  elsif p_kind = 'invited' then
    if e is null or e !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'invalid: enter a valid email'; end if;
    if exists (select 1 from profiles where lower(email) = e) then
      raise exception 'invalid: this email belongs to an existing account; add them through the directory';
    end if;
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
  v_late text;
  v_due date;
  v_period date;
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
      v_period := (date_trunc('month', p_today) - interval '2 months')::date;
      while v_period <= date_trunc('month', p_today)::date loop
        v_head := s.head_prefix || ' – ' || to_char(v_period, 'Mon YYYY');
        v_due := make_date(extract(year from v_period)::int, extract(month from v_period)::int, s.due_day);
        if p_today = v_due + s.late_fee_grace_days then
          v_late := 'Late fee – ' || v_head;
          insert into dues (association_id, flat_id, head, amount, due_date, created_by)
          select s.association_id, d.flat_id, v_late, s.late_fee_amount, p_today + 7, s.updated_by
          from dues d left join payments p on p.due_id = d.id and p.flat_id = d.flat_id
          where d.association_id = s.association_id and d.head = v_head
          group by d.flat_id, d.amount having d.amount > coalesce(sum(p.amount), 0)
          on conflict (flat_id, head) do nothing;
          get diagnostics n = row_count;
          total := total + n;
          insert into audit_log (association_id, actor, action, entity, entity_id, after)
          values (s.association_id, null, 'auto_late_fee', 'dues', v_late,
                  jsonb_build_object('amount', s.late_fee_amount, 'flats', n));
        end if;
        v_period := (v_period + interval '1 month')::date;
      end loop;
    end if;
  end loop;
  return total;
end $$;
revoke all on function run_dues_schedules(date) from public, anon, authenticated;
