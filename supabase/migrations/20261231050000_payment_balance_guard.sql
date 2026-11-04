create function prevent_overpaid_due() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  due_amount integer;
  paid_amount bigint;
begin
  if new.due_id is null or new.amount <= 0 then return new; end if;

  select amount into due_amount
  from dues
  where id = new.due_id and flat_id = new.flat_id and association_id = new.association_id
  for update;
  if not found then raise exception 'not_found: due not found'; end if;

  select coalesce(sum(amount), 0) into paid_amount
  from payments
  where due_id = new.due_id and flat_id = new.flat_id and association_id = new.association_id;

  if new.amount > due_amount::bigint - paid_amount then
    raise exception 'invalid: this due balance changed; refresh the preview and try again';
  end if;
  return new;
end $$;

revoke all on function prevent_overpaid_due() from public, anon, authenticated;

create trigger payments_validate_due_balance
before insert on payments
for each row execute function prevent_overpaid_due();
