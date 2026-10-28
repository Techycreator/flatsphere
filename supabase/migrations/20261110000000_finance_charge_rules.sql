create function raise_dues_per_sqft(p_head text,p_due_date date,p_rate_per_sqft numeric) returns integer
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); n integer;
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: Treasurer access required'; end if;
  if coalesce(trim(p_head),'')='' or p_due_date is null then raise exception 'invalid: enter a dues name and due date'; end if;
  if p_rate_per_sqft is null or p_rate_per_sqft<=0 or p_rate_per_sqft>10000 then raise exception 'invalid: rate per square foot must be positive'; end if;
  insert into dues (association_id,flat_id,head,amount,due_date,created_by)
  select a,f.id,trim(p_head),round(f.sqft*p_rate_per_sqft)::integer,p_due_date,auth.uid()
  from flats f where f.association_id=a and f.sqft is not null and f.sqft>0
    and round(f.sqft*p_rate_per_sqft)>0
  on conflict(flat_id,head) do nothing;
  get diagnostics n=row_count;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'raise_dues_per_sqft','dues',trim(p_head),jsonb_build_object('due_date',p_due_date,'rate_per_sqft',p_rate_per_sqft,'flats',n));
  return n;
end $$;

create function apply_fixed_late_fee(p_head text,p_due_date date,p_amount integer) returns integer
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); n integer;
begin
  if a is null or not fin_recorder(a) then raise exception 'not_allowed: Treasurer access required'; end if;
  if coalesce(trim(p_head),'')='' or p_due_date is null or p_amount is null or p_amount<=0 then
    raise exception 'invalid: enter a fee name, due date and positive fixed amount';
  end if;
  insert into dues(association_id,flat_id,head,amount,due_date,created_by)
  select a,f.id,trim(p_head),p_amount,p_due_date,auth.uid()
  from flats f
  where f.association_id=a and exists(
    select 1 from dues d left join payments p on p.due_id=d.id and p.flat_id=d.flat_id
    where d.association_id=a and d.flat_id=f.id and d.due_date<current_date
    group by d.id,d.amount
    having d.amount>coalesce(sum(p.amount),0)
  )
  on conflict(flat_id,head) do nothing;
  get diagnostics n=row_count;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'apply_fixed_late_fee','dues',trim(p_head),jsonb_build_object('due_date',p_due_date,'amount',p_amount,'flats',n));
  return n;
end $$;
revoke all on function raise_dues_per_sqft(text,date,numeric) from public;
revoke all on function apply_fixed_late_fee(text,date,integer) from public;
grant execute on function raise_dues_per_sqft(text,date,numeric) to authenticated;
grant execute on function apply_fixed_late_fee(text,date,integer) to authenticated;
