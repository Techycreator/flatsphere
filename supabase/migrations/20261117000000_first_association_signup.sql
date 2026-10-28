create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  n text;
  mob text;
begin
  select full_name,mobile into n,mob
  from invites where lower(email)=lower(new.email) and claimed_at is null
  order by mobile nulls last limit 1;

  if n is null then
    n:=coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1));
    mob:=nullif(trim(new.raw_user_meta_data->>'mobile'),'');
  end if;
  if exists(select 1 from profiles where mobile=mob) then mob:=null; end if;
  insert into profiles(id,full_name,email,mobile)
  values(new.id,n,new.email,mob);

  if exists(select 1 from invites where lower(email)=lower(new.email) and claimed_at is null) then
    insert into memberships(association_id,user_id,role,flat_id,designations,monitor_categories,
      monitor_from,monitor_until,assigned_by,support_flags,contact_phone,date_of_birth)
    select association_id,new.id,role,flat_id,designations,monitor_categories,
      monitor_from,monitor_until,assigned_by,support_flags,mobile,date_of_birth
    from invites where lower(email)=lower(new.email) and claimed_at is null;
    update invites set claimed_at=now() where lower(email)=lower(new.email) and claimed_at is null;
  end if;
  return new;
end $$;

create function create_first_association(
  p_name text,p_state text,p_city text,p_brand_primary text,p_full_name text
) returns uuid language plpgsql security definer set search_path=public as $$
declare a uuid; brand text:=coalesce(nullif(trim(p_brand_primary),''),'#26746A');
begin
  if auth.uid() is null then
    raise exception 'not_allowed: authenticated user required';
  end if;
  if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then
    raise exception 'not_allowed: verified email required';
  end if;
  perform 1 from profiles where id=auth.uid() for update;
  if not found then
    raise exception 'not_allowed: verified user profile required';
  end if;
  if exists(select 1 from memberships where user_id=auth.uid()) then
    raise exception 'not_allowed: first-association signup is only for accounts with no membership history';
  end if;
  if coalesce(trim(p_name),'')='' or length(trim(p_name))>120 then raise exception 'invalid: enter an association name'; end if;
  if coalesce(trim(p_full_name),'')='' or length(trim(p_full_name))>120 then raise exception 'invalid: enter the Admin name'; end if;
  if coalesce(trim(p_state),'')='' or length(trim(p_state))>80 then raise exception 'invalid: enter a state'; end if;
  if length(coalesce(trim(p_city),''))>80 then raise exception 'invalid: city is too long'; end if;
  if brand !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid: brand color must be #RRGGBB'; end if;
  update profiles set full_name=trim(p_full_name) where id=auth.uid();
  insert into associations(name,state,city,settings)
  values(trim(p_name),trim(p_state),nullif(trim(p_city),''),jsonb_build_object(
    'brand_primary',brand,'fiscal_year_start_month',4,'default_due_day',10
  )) returning id into a;
  insert into memberships(association_id,user_id,role)
  values(a,auth.uid(),'admin');
  perform set_active_association(a);
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'self_service_association_signup','association',a::text,
    jsonb_build_object('name',trim(p_name),'state',trim(p_state),'city',nullif(trim(p_city),'')));
  return a;
end $$;
revoke all on function create_first_association(text,text,text,text,text) from public;
grant execute on function create_first_association(text,text,text,text,text) to authenticated;
