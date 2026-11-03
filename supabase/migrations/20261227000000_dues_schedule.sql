-- Automatic monthly maintenance bills and late fees, one schedule per association, run daily by pg_cron.
create table if not exists dues_schedules (
  association_id uuid primary key default my_association() references associations(id) on delete cascade,
  enabled boolean not null default false,
  mode text not null default 'flat_type' check (mode in ('flat_type', 'per_sqft')),
  rates jsonb not null default '{}',
  rate_per_sqft numeric check (rate_per_sqft is null or (rate_per_sqft > 0 and rate_per_sqft <= 10000)),
  head_prefix text not null default 'Maintenance',
  bill_day integer not null default 1 check (bill_day between 1 and 28),
  due_day integer not null default 10 check (due_day between 1 and 28),
  late_fee_enabled boolean not null default false,
  late_fee_amount integer check (late_fee_amount is null or late_fee_amount > 0),
  late_fee_grace_days integer not null default 5 check (late_fee_grace_days between 0 and 60),
  updated_by uuid not null references profiles(id),
  updated_at timestamptz not null default now()
);
alter table dues_schedules enable row level security;
create policy dues_schedules_read on dues_schedules for select using (association_id = my_association() and fin_reader(association_id));

create or replace function save_dues_schedule(
  p_enabled boolean, p_mode text, p_rates jsonb, p_rate_per_sqft numeric, p_head_prefix text,
  p_bill_day integer, p_due_day integer, p_late_fee_enabled boolean, p_late_fee_amount integer, p_late_fee_grace_days integer
) returns void language plpgsql security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: only the Treasurer or Joint Treasurer can set automatic bills'; end if;
  if coalesce(trim(p_head_prefix), '') = '' then raise exception 'invalid: enter a bill name, e.g. Maintenance'; end if;
  if p_due_day < p_bill_day then raise exception 'invalid: due day must be on or after the bill day'; end if;
  if p_enabled and p_mode = 'flat_type' and not exists (select 1 from jsonb_each_text(coalesce(p_rates, '{}')) where value ~ '^[0-9]+$' and value::int > 0) then
    raise exception 'invalid: enter an amount for at least one flat type';
  end if;
  if p_enabled and p_mode = 'per_sqft' and coalesce(p_rate_per_sqft, 0) <= 0 then raise exception 'invalid: enter the rate per square foot'; end if;
  if p_late_fee_enabled and coalesce(p_late_fee_amount, 0) <= 0 then raise exception 'invalid: enter the late fee amount'; end if;
  insert into dues_schedules as s (association_id, enabled, mode, rates, rate_per_sqft, head_prefix, bill_day, due_day,
                                   late_fee_enabled, late_fee_amount, late_fee_grace_days, updated_by, updated_at)
  values (a, p_enabled, p_mode, coalesce(p_rates, '{}'), p_rate_per_sqft, trim(p_head_prefix), p_bill_day, p_due_day,
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

-- Runs daily (India time). Safe to re-run: a flat never gets the same bill name twice.
create or replace function run_dues_schedules(p_today date default (now() at time zone 'Asia/Kolkata')::date)
returns integer language plpgsql security definer set search_path = public as $$
declare s dues_schedules; v_head text; v_late text; v_due date; n integer; total integer := 0;
begin
  for s in select * from dues_schedules where enabled loop
    v_head := s.head_prefix || ' – ' || to_char(p_today, 'Mon YYYY');
    v_due := make_date(extract(year from p_today)::int, extract(month from p_today)::int, s.due_day);
    if extract(day from p_today)::int = s.bill_day then
      insert into dues (association_id, flat_id, head, amount, due_date, created_by)
      select s.association_id, f.id, v_head,
             case when s.mode = 'per_sqft' then round(coalesce(f.sqft, 0) * s.rate_per_sqft)::int
                  else coalesce((s.rates->>f.flat_type)::int, 0) end,
             v_due, s.updated_by
      from flats f where f.association_id = s.association_id
        and (case when s.mode = 'per_sqft' then round(coalesce(f.sqft, 0) * s.rate_per_sqft)
                  else coalesce((s.rates->>f.flat_type)::int, 0) end) > 0
      on conflict (flat_id, head) do nothing;
      get diagnostics n = row_count;
      total := total + n;
      insert into audit_log (association_id, actor, action, entity, entity_id, after)
      values (s.association_id, null, 'auto_raise_dues', 'dues', v_head, jsonb_build_object('due_date', v_due, 'flats', n));
    end if;
    if s.late_fee_enabled and p_today = v_due + s.late_fee_grace_days then
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
      values (s.association_id, null, 'auto_late_fee', 'dues', v_late, jsonb_build_object('amount', s.late_fee_amount, 'flats', n));
    end if;
  end loop;
  return total;
end $$;
revoke all on function run_dues_schedules(date) from public, anon, authenticated;

select cron.unschedule('flatsphere-monthly-dues') where exists (select 1 from cron.job where jobname = 'flatsphere-monthly-dues');
select cron.schedule('flatsphere-monthly-dues', '30 0 * * *', 'select public.run_dues_schedules()');
