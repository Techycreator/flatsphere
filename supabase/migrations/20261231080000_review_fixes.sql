-- Review fixes: private complaints stay private; custom bill names can't collide; saving runs only the new bill; setup status RPC.
drop policy complaints_read on complaints;
create policy complaints_read on complaints for select using (
  association_id = my_association() and (
    has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor','caretaker']::app_role[])
    or raised_by = auth.uid()
    or (has_role(association_id, array['owner']::app_role[])
        and coalesce((select (a.settings->>'complaints_visible_to_owners')::boolean from associations a where a.id = complaints.association_id), false)
        and not is_private)
    or (has_role(association_id, array['resident']::app_role[])
        and coalesce((select (a.settings->>'complaints_visible_to_residents')::boolean from associations a where a.id = complaints.association_id), false)
        and not is_private)
  )
);


drop function if exists run_recurring_bills(date);
create or replace function run_recurring_bills(p_today date default (now() at time zone 'Asia/Kolkata')::date, p_bill uuid default null)
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
    where r.active and a.closed_at is null and (p_bill is null or r.id = p_bill)
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
revoke all on function run_recurring_bills(date, uuid) from public, anon, authenticated;

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
  if exists (select 1 from dues_schedules s where s.association_id = a and lower(s.head_prefix) = lower(trim(p_head_prefix))) then
    raise exception 'invalid: this name is used by the automatic maintenance bill; choose a different name';
  end if;
  if exists (
    select 1 from recurring_bills r
    where r.association_id = a and r.active and lower(r.head_prefix) = lower(trim(p_head_prefix))
      and r.start_month <= (date_trunc('month', p_start_month) + make_interval(months => p_months - 1))::date
      and date_trunc('month', p_start_month)::date <= (r.start_month + make_interval(months => r.months - 1))::date
  ) then
    raise exception 'invalid: a running monthly bill already uses this name for some of these months; choose a different name';
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

-- Association-wide setup progress without exposing other members' rows.
create or replace function setup_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary','treasurer','joint_secretary','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: office bearer access required';
  end if;
  return jsonb_build_object('owners', exists (
    select 1 from memberships m where m.association_id = a and m.role = 'owner' and m.ended_at is null));
end $$;
revoke all on function setup_status() from public, anon;
grant execute on function setup_status() to authenticated;
