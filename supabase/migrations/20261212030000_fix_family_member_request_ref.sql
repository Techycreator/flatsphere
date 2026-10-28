-- gen_random_bytes lives outside the function search path, so adding a family member failed.
-- Generate the request reference the same way as the amenity booking function.
create or replace function request_family_member_addition(p_flat uuid,p_full_name text,p_date_of_birth date)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  flat_no text;
  actor_role app_role;
  approval_id uuid;
  member_id uuid;
  request_ref text:='APR-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
begin
  if a is null or auth.uid() is null then raise exception 'not_allowed: authenticated association member required'; end if;
  select number into flat_no from flats where id=p_flat and association_id=a;
  if flat_no is null then raise exception 'invalid: selected flat is not in this association'; end if;
  if not owns_flat(p_flat::text) and not exists(
    select 1 from memberships where association_id=a and flat_id=p_flat and user_id=auth.uid()
      and role='resident' and ended_at is null
  ) then raise exception 'not_allowed: only an owner or resident of this flat can add family members'; end if;
  if coalesce(trim(p_full_name),'')='' or length(trim(p_full_name))>120 then raise exception 'invalid: enter a name'; end if;
  if p_date_of_birth is null or p_date_of_birth>current_date then raise exception 'invalid: enter a valid date of birth'; end if;

  select role into actor_role from memberships where association_id=a and user_id=auth.uid()
    and flat_id=p_flat and ended_at is null and role in ('owner','resident') order by role limit 1;
  insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category)
  values (a,request_ref,'W30','Add family member: '||trim(p_full_name),
    jsonb_build_object('Flat',flat_no,'Family member',trim(p_full_name)),
    auth.uid(),my_name(),coalesce(actor_role,'owner'),'Family member')
  returning id into approval_id;
  insert into approval_steps (request_id,seq,role,name) values (approval_id,1,'secretary','Secretary');

  insert into family_members (association_id,flat_id,approval_request_id,full_name,date_of_birth)
  values (a,p_flat,approval_id,trim(p_full_name),p_date_of_birth)
  returning id into member_id;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
  values (a,auth.uid(),'request_family_member','family_member',member_id::text,jsonb_build_object('flat',flat_no));
  return member_id;
end $$;
