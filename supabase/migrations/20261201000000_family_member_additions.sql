-- Owners/residents add family members after onboarding through a Secretary-approved request (workflow W30).
alter table family_members add column approval_request_id uuid references approval_requests(id) on delete set null;

create or replace function enforce_family_member_request_limit()
returns trigger language plpgsql security definer set search_path=public as $$
declare c membership_changes; max_members integer;
begin
  max_members:=family_member_limit(new.association_id);
  if new.approval_request_id is not null then
    if (select count(*) from family_members where flat_id=new.flat_id and archived_at is null)>=max_members then
      raise exception 'invalid: this flat already has the maximum of % family members',max_members;
    end if;
  else
    select * into c from membership_changes where request_id=new.request_id for update;
    if c.request_id is null or c.change_type<>'resident' or c.association_id<>new.association_id or c.flat_id<>new.flat_id then
      raise exception 'invalid: family members must belong to a resident change request';
    end if;
    max_members:=family_member_limit(c.association_id);
    if c.family_count>max_members then
      raise exception 'invalid: this association allows at most % family members',max_members;
    end if;
    if (select count(*) from family_members where request_id=new.request_id)>=max_members then
      raise exception 'invalid: this association allows at most % family members',max_members;
    end if;
  end if;
  if new.email is not null then new.email:=lower(trim(new.email)); end if;
  return new;
end $$;

create function request_family_member_addition(p_flat uuid,p_full_name text,p_date_of_birth date)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  flat_no text;
  actor_role app_role;
  approval_id uuid;
  member_id uuid;
  request_ref text:='APR-'||upper(substr(encode(gen_random_bytes(6),'hex'),1,10));
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
revoke all on function request_family_member_addition(uuid,text,date) from public, anon;
grant execute on function request_family_member_addition(uuid,text,date) to authenticated;

create function sync_family_addition_approval() returns trigger
language plpgsql security definer set search_path=public as $$
declare r approval_requests;
begin
  if old.decision is not distinct from new.decision or new.decision='pending' then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  if r.code<>'W30' then return new; end if;
  if new.decision='approved' then
    update family_members set approved_at=now() where approval_request_id=new.request_id and approved_at is null;
  elsif new.decision='rejected' then
    update family_members set archived_at=now() where approval_request_id=new.request_id;
  end if;
  return new;
end $$;
create trigger family_addition_approval_sync after update of decision on approval_steps
  for each row execute function sync_family_addition_approval();
