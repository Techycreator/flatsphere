create or replace function save_recurring_bill(
  p_head_prefix text, p_rates jsonb, p_start_month date, p_months integer, p_bill_day integer, p_due_day integer
) returns uuid language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); v_id uuid;
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: only the Treasurer or Joint Treasurer can set monthly bills'; end if;
  if coalesce(trim(p_head_prefix), '') = '' then raise exception 'invalid: enter a bill name, e.g. Painting contribution'; end if;
  if p_months not between 1 and 60 then raise exception 'invalid: months must be between 1 and 60'; end if;
  if p_due_day < p_bill_day then raise exception 'invalid: due day must be on or after the bill day'; end if;
  if date_trunc('month', p_start_month)::date < date_trunc('month', (now() at time zone 'Asia/Kolkata'))::date then
    raise exception 'invalid: the first month cannot be in the past';
  end if;
  if jsonb_typeof(p_rates) is distinct from 'object' or exists (
    select 1 from jsonb_each(p_rates) r
    where not (jsonb_typeof(r.value) = 'number' and r.value::text ~ '^(0|[1-9][0-9]{0,8})$')
  ) then raise exception 'invalid: every flat-type amount must be a whole number of rupees'; end if;
  if not exists (select 1 from jsonb_each(p_rates) r where r.value::text::int > 0) then
    raise exception 'invalid: enter an amount for at least one flat type';
  end if;
  perform pg_advisory_xact_lock(hashtext('recurring_bills:' || a::text));
  if exists (
    select 1 from dues_schedules s
    where s.association_id = a and (
      lower(trim(p_head_prefix)) = lower(s.head_prefix)
      or left(lower(trim(p_head_prefix)), length(lower(s.head_prefix || ' – '))) = lower(s.head_prefix || ' – ')
      or left(lower(s.head_prefix), length(lower(trim(p_head_prefix) || ' – '))) = lower(trim(p_head_prefix) || ' – ')
      or lower(trim(p_head_prefix)) = lower('Late fee – ' || s.head_prefix)
    )
  ) then
    raise exception 'invalid: this name overlaps the automatic maintenance bill or its late fees; choose a different name';
  end if;
  if exists (
    select 1 from recurring_bills r
    where r.association_id = a and r.active and lower(r.head_prefix) = lower(trim(p_head_prefix))
      and r.start_month <= (date_trunc('month', p_start_month) + make_interval(months => p_months - 1))::date
      and date_trunc('month', p_start_month)::date <= (r.start_month + make_interval(months => r.months - 1))::date
  ) then
    raise exception 'invalid: a running monthly bill already uses this name for some of these months; choose a different name';
  end if;
  if exists (
    select 1
    from generate_series(
      date_trunc('month', p_start_month)::date,
      (date_trunc('month', p_start_month) + make_interval(months => p_months - 1))::date,
      interval '1 month'
    ) as months(month_start)
    join dues d on d.association_id = a
      and lower(d.head) = lower(trim(p_head_prefix) || ' – ' || to_char(months.month_start, 'Mon YYYY'))
  ) then
    raise exception 'invalid: dues with this name have already been issued for one or more of these months; choose another name or a later month';
  end if;
  insert into recurring_bills (association_id, head_prefix, rates, start_month, months, bill_day, due_day, created_by)
  values (a, trim(p_head_prefix), p_rates, date_trunc('month', p_start_month)::date, p_months, p_bill_day, p_due_day, auth.uid())
  returning id into v_id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'save_recurring_bill', 'recurring_bills', v_id::text,
          jsonb_build_object('head', trim(p_head_prefix), 'rates', p_rates, 'start', p_start_month, 'months', p_months));
  perform run_recurring_bills(p_bill => v_id);
  return v_id;
end $$;
revoke all on function save_recurring_bill(text, jsonb, date, integer, integer, integer) from public, anon;
grant execute on function save_recurring_bill(text, jsonb, date, integer, integer, integer) to authenticated;

create or replace function save_dues_schedule(
  p_enabled boolean, p_mode text, p_rates jsonb, p_rate_per_sqft numeric, p_head_prefix text,
  p_bill_day integer, p_due_day integer, p_late_fee_enabled boolean, p_late_fee_amount integer, p_late_fee_grace_days integer
) returns void language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  v_month date := date_trunc('month', (now() at time zone 'Asia/Kolkata'))::date;
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
  perform pg_advisory_xact_lock(hashtext('recurring_bills:' || a::text));
  if exists (
    select 1 from recurring_bills r
    where r.association_id = a and r.active and (
      lower(r.head_prefix) = lower(trim(p_head_prefix))
      or left(lower(r.head_prefix), length(lower(trim(p_head_prefix) || ' – '))) = lower(trim(p_head_prefix) || ' – ')
      or left(lower(trim(p_head_prefix)), length(lower(r.head_prefix || ' – '))) = lower(r.head_prefix || ' – ')
      or lower(r.head_prefix) = lower('Late fee – ' || trim(p_head_prefix))
    )
  ) then
    raise exception 'invalid: this name overlaps an active custom bill or its generated late fees; choose a different name';
  end if;
  if exists (
    select 1
    from recurring_bills r
    where r.association_id = a and not r.active and (
      (
        lower(r.head_prefix) = lower(trim(p_head_prefix))
        and v_month between r.start_month and (r.start_month + make_interval(months => r.months - 1))::date
        and exists (
          select 1 from dues d
          where d.association_id = a
            and lower(d.head) = lower(trim(p_head_prefix) || ' – ' || to_char(v_month, 'Mon YYYY'))
        )
      )
      or (
        lower(r.head_prefix) = lower('Late fee – ' || trim(p_head_prefix))
        and v_month between r.start_month and (r.start_month + make_interval(months => r.months - 1))::date
        and exists (
          select 1 from dues d
          where d.association_id = a
            and lower(d.head) = lower(r.head_prefix || ' – ' || to_char(v_month, 'Mon YYYY'))
        )
      )
      or (
        lower(r.head_prefix) <> lower(trim(p_head_prefix))
        and left(lower(r.head_prefix), length(lower(trim(p_head_prefix) || ' – '))) = lower(trim(p_head_prefix) || ' – ')
        and exists (
          select 1 from dues d
          where d.association_id = a
            and left(lower(d.head), length(lower(r.head_prefix || ' – '))) = lower(r.head_prefix || ' – ')
        )
      )
    )
  ) then
    raise exception 'invalid: issued custom dues would collide with this maintenance bill or its late fees; choose a different name';
  end if;
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

create or replace function setup_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary','treasurer','joint_secretary','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: office bearer access required';
  end if;
  return jsonb_build_object('owners', not exists (
    select 1 from flats f
    where f.association_id = a and f.retired_at is null
      and not exists (
        select 1 from memberships m
        where m.association_id = a and m.flat_id = f.id and m.role = 'owner' and m.ended_at is null
      )
  ));
end $$;
revoke all on function setup_status() from public, anon;
grant execute on function setup_status() to authenticated;
