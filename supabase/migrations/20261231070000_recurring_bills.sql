-- Custom monthly bills for a fixed number of months (e.g. Painting contribution ₹5,000 × 6), run daily with the dues schedule.
create table if not exists recurring_bills (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  head_prefix text not null check (length(trim(head_prefix)) between 1 and 80),
  rates jsonb not null default '{}',
  start_month date not null check (extract(day from start_month) = 1),
  months integer not null check (months between 1 and 60),
  bill_day integer not null default 1 check (bill_day between 1 and 28),
  due_day integer not null default 10 check (due_day between 1 and 28),
  active boolean not null default true,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);
alter table recurring_bills enable row level security;
create policy recurring_bills_read on recurring_bills for select using (association_id = my_association() and fin_reader(association_id));

create or replace function run_recurring_bills(p_today date default (now() at time zone 'Asia/Kolkata')::date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  b recurring_bills;
  v_month date := date_trunc('month', p_today)::date;
  v_head text;
  n integer;
  total integer := 0;
begin
  for b in
    select r.* from recurring_bills r join associations a on a.id = r.association_id
    where r.active and a.closed_at is null
      and v_month between r.start_month and (r.start_month + make_interval(months => r.months - 1))::date
      and extract(day from p_today)::int >= r.bill_day
  loop
    v_head := b.head_prefix || ' – ' || to_char(p_today, 'Mon YYYY');
    insert into dues (association_id, flat_id, head, amount, due_date, created_by)
    select b.association_id, f.id, v_head, (b.rates->>f.flat_type)::int,
           v_month + (b.due_day - 1), b.created_by
    from flats f
    where f.association_id = b.association_id and f.retired_at is null
      and coalesce((b.rates->>f.flat_type)::int, 0) > 0
    on conflict (flat_id, head) do nothing;
    get diagnostics n = row_count;
    total := total + n;
    if n > 0 then
      insert into audit_log (association_id, actor, action, entity, entity_id, after)
      values (b.association_id, null, 'auto_raise_dues', 'dues', v_head, jsonb_build_object('recurring_bill', b.id, 'flats', n));
    end if;
  end loop;
  return total;
end $$;
revoke all on function run_recurring_bills(date) from public, anon, authenticated;

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
  insert into recurring_bills (association_id, head_prefix, rates, start_month, months, bill_day, due_day, created_by)
  values (a, trim(p_head_prefix), p_rates, date_trunc('month', p_start_month)::date, p_months, p_bill_day, p_due_day, auth.uid())
  returning id into v_id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'save_recurring_bill', 'recurring_bills', v_id::text,
          jsonb_build_object('head', trim(p_head_prefix), 'rates', p_rates, 'start', p_start_month, 'months', p_months));
  perform run_recurring_bills();
  return v_id;
end $$;
revoke all on function save_recurring_bill(text, jsonb, date, integer, integer, integer) from public, anon;
grant execute on function save_recurring_bill(text, jsonb, date, integer, integer, integer) to authenticated;

-- Stops future months only; bills already raised stay.
create or replace function stop_recurring_bill(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: only the Treasurer or Joint Treasurer can stop monthly bills'; end if;
  update recurring_bills set active = false where id = p_id and association_id = a and active;
  if not found then raise exception 'not_found: this monthly bill is not active'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id)
  values (a, auth.uid(), 'stop_recurring_bill', 'recurring_bills', p_id::text);
end $$;
revoke all on function stop_recurring_bill(uuid) from public, anon;
grant execute on function stop_recurring_bill(uuid) to authenticated;

select cron.unschedule('flatsphere-recurring-bills') where exists (select 1 from cron.job where jobname = 'flatsphere-recurring-bills');
select cron.schedule('flatsphere-recurring-bills', '35 0 * * *', 'select public.run_recurring_bills()');
