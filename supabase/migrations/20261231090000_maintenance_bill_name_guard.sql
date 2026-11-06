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
  perform pg_advisory_xact_lock(hashtext('recurring_bills:' || a::text));
  if exists (
    select 1 from recurring_bills r
    where r.association_id = a and r.active and lower(r.head_prefix) = lower(trim(p_head_prefix))
  ) then
    raise exception 'invalid: this name is used by an active custom monthly bill; choose a different name';
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
