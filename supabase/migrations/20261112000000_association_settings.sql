create function update_active_association_settings(
  p_name text,p_state text,p_city text,p_brand_primary text,p_fiscal_year_start_month integer,p_default_due_day integer
) returns void language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin']::app_role[]) then raise exception 'not_allowed: association Admin access required'; end if;
  if coalesce(trim(p_name),'')='' or length(trim(p_name))>120 then raise exception 'invalid: enter an association name'; end if;
  if coalesce(trim(p_state),'')='' or length(trim(p_state))>80 then raise exception 'invalid: enter a state'; end if;
  if length(coalesce(trim(p_city),''))>80 then raise exception 'invalid: city is too long'; end if;
  if coalesce(p_brand_primary,'') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid: brand color must be a six-digit hex color'; end if;
  if p_fiscal_year_start_month not between 1 and 12 then raise exception 'invalid: fiscal-year start month must be 1 to 12'; end if;
  if p_default_due_day not between 1 and 28 then raise exception 'invalid: default due day must be 1 to 28'; end if;
  update associations set name=trim(p_name),state=trim(p_state),city=nullif(trim(p_city),''),settings=settings||jsonb_build_object(
    'brand_primary',p_brand_primary,
    'fiscal_year_start_month',p_fiscal_year_start_month,
    'default_due_day',p_default_due_day
  ) where id=a;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'update_association_settings','association',a::text,jsonb_build_object(
    'name',trim(p_name),'state',trim(p_state),'city',nullif(trim(p_city),''),'brand_primary',p_brand_primary,
    'fiscal_year_start_month',p_fiscal_year_start_month,'default_due_day',p_default_due_day
  ));
end $$;
revoke all on function update_active_association_settings(text,text,text,text,integer,integer) from public;
grant execute on function update_active_association_settings(text,text,text,text,integer,integer) to authenticated;
