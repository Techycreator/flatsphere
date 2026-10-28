create or replace function retire_flat(p_flat uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  f flats;
  outstanding bigint;
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the Admin, President or Secretary can retire a flat';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'invalid: enter a reason of 3 to 300 characters';
  end if;
  select * into f from flats where id = p_flat and association_id = a for update;
  if f.id is null then raise exception 'not_found: flat not found'; end if;
  if f.retired_at is not null then raise exception 'invalid: flat is already retired'; end if;
  if exists (select 1 from memberships where flat_id = f.id and ended_at is null) then
    raise exception 'invalid: remove or transfer the flat''s owner and residents first';
  end if;
  if exists (select 1 from membership_changes c where c.flat_id = f.id and c.status <> 'applied') then
    raise exception 'invalid: finish the pending owner or resident change for this flat first';
  end if;
  select coalesce(sum(greatest(d.amount - coalesce(p.paid, 0), 0)), 0)::bigint into outstanding
  from dues d
  left join lateral (select sum(pay.amount)::bigint as paid from payments pay where pay.due_id = d.id and pay.flat_id = d.flat_id) p on true
  where d.flat_id = f.id;
  if outstanding > 0 then raise exception 'invalid: settle outstanding dues of % before retiring the flat', outstanding; end if;
  update flats set retired_at = now() where id = f.id;
  delete from flat_vehicles where flat_id = f.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'retire_flat', 'flat', f.id::text, jsonb_build_object('number', f.number, 'reason', trim(p_reason)));
end $$;
revoke all on function retire_flat(uuid, text) from public, anon;
grant execute on function retire_flat(uuid, text) to authenticated;
