-- Payment receipts are kept unchanged for at least 5 years (corrections are made with new entries).
create function protect_payment_records() returns trigger
language plpgsql as $$
begin
  if old.created_at > now() - interval '5 years' then
    raise exception 'not_allowed: payment receipts are kept for 5 years and cannot be changed or deleted';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger payments_retention before update or delete on payments
  for each row execute function protect_payment_records();
