create function create_association_for_admin(p_name text,p_state text,p_city text,p_brand_primary text) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  source_association uuid:=my_association();
  new_association uuid;
  brand text:=coalesce(nullif(trim(p_brand_primary),''),'#26746A');
begin
  if source_association is null or not has_role(source_association,array['admin']::app_role[]) then
    raise exception 'not_allowed: only an existing association Admin can create another association';
  end if;
  if coalesce(trim(p_name),'')='' or length(trim(p_name))>120 then raise exception 'invalid: enter an association name'; end if;
  if coalesce(trim(p_state),'')='' or length(trim(p_state))>80 then raise exception 'invalid: enter a state'; end if;
  if length(coalesce(trim(p_city),''))>80 then raise exception 'invalid: city is too long'; end if;
  if brand !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid: brand color must be a six-digit hex color'; end if;
  insert into associations(name,state,city,settings)
  values(trim(p_name),trim(p_state),nullif(trim(p_city),''),jsonb_build_object(
    'brand_primary',brand,'fiscal_year_start_month',4,'default_due_day',10
  )) returning id into new_association;
  insert into memberships(association_id,user_id,role)
  values(new_association,auth.uid(),'admin');
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(new_association,auth.uid(),'create_association','association',new_association::text,
    jsonb_build_object('name',trim(p_name),'state',trim(p_state),'city',nullif(trim(p_city),'')));
  return new_association;
end $$;
revoke all on function create_association_for_admin(text,text,text,text) from public;
grant execute on function create_association_for_admin(text,text,text,text) to authenticated;
