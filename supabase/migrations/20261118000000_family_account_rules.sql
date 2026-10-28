-- Per-association family account policy and dependent records.

create or replace function family_member_min_login_age(p_association uuid)
returns integer language sql stable security definer set search_path=public as $$
  select coalesce((settings->>'family_min_login_age')::integer, 12)
  from associations where id=p_association
$$;

create or replace function family_member_limit(p_association uuid)
returns integer language sql stable security definer set search_path=public as $$
  select coalesce((settings->>'family_member_limit')::integer, 5)
  from associations where id=p_association
$$;
revoke all on function family_member_min_login_age(uuid) from public;
revoke all on function family_member_limit(uuid) from public;
grant execute on function family_member_min_login_age(uuid),family_member_limit(uuid) to authenticated;

create function update_family_account_rules(p_min_login_age integer, p_member_limit integer)
returns void language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin']::app_role[]) then
    raise exception 'not_allowed: association Admin access required';
  end if;
  if p_min_login_age not between 1 and 21 then
    raise exception 'invalid: minimum login age must be between 1 and 21';
  end if;
  if p_member_limit not between 0 and 30 then
    raise exception 'invalid: family member limit must be between 0 and 30';
  end if;
  update associations set settings=settings||jsonb_build_object(
    'family_min_login_age',p_min_login_age,
    'family_member_limit',p_member_limit
  ) where id=a;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'update_family_account_rules','association',a::text,jsonb_build_object(
    'family_min_login_age',p_min_login_age,'family_member_limit',p_member_limit
  ));
end $$;
revoke all on function update_family_account_rules(integer,integer) from public;
grant execute on function update_family_account_rules(integer,integer) to authenticated;

create table family_members (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  flat_id uuid not null references flats(id) on delete cascade,
  request_id uuid references membership_changes(request_id) on delete set null,
  full_name text not null check(length(trim(full_name)) between 1 and 120),
  date_of_birth date not null check(date_of_birth <= current_date),
  email text check(email is null or (email=lower(email) and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  archived_at timestamptz
);
alter table membership_changes add column family_details_required boolean not null default false;
create index family_members_household_idx on family_members(association_id,flat_id) where archived_at is null;
create index family_members_email_idx on family_members(lower(email)) where email is not null and archived_at is null;
create unique index family_members_association_email_idx
  on family_members(association_id,lower(email)) where email is not null and archived_at is null;
alter table family_members enable row level security;
create policy family_members_read on family_members for select using (
  association_id=my_association() and archived_at is null and created_by=auth.uid() and (
    owns_flat(flat_id::text)
    or exists(select 1 from memberships m where m.association_id=family_members.association_id
      and m.flat_id=family_members.flat_id and m.user_id=auth.uid() and m.role='resident' and m.ended_at is null)
  )
);
create policy family_members_insert on family_members for insert with check (
  association_id=my_association() and created_by=auth.uid()
  and exists (
    select 1 from membership_changes c
    where c.request_id=request_id and c.association_id=family_members.association_id
      and c.flat_id=family_members.flat_id and c.change_type='resident' and c.created_by=auth.uid()
  )
  and (owns_flat(flat_id::text) or exists(select 1 from memberships m where m.association_id=family_members.association_id
    and m.flat_id=family_members.flat_id and m.user_id=auth.uid() and m.role='resident' and m.ended_at is null))
);

create function enforce_family_member_request_limit()
returns trigger language plpgsql security definer set search_path=public as $$
declare c membership_changes; max_members integer;
begin
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
  if new.email is not null then new.email:=lower(trim(new.email)); end if;
  return new;
end $$;
create trigger family_member_request_limit before insert on family_members
for each row execute function enforce_family_member_request_limit();

create function create_membership_change_with_family(
  p_request uuid,p_flat uuid,p_type text,p_name text,p_email text,p_mobile text,p_lease text,p_family jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); request_code text; expected_code text; family_count integer; family_row record;
begin
  if a is null or auth.uid() is null then raise exception 'not_allowed: authenticated association member required'; end if;
  if p_type not in ('owner','resident') then raise exception 'invalid: membership change type is invalid'; end if;
  if coalesce(trim(p_name),'')='' or length(trim(p_name))>120 then raise exception 'invalid: enter a name'; end if;
  if coalesce(trim(p_email),'') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid: enter a valid email'; end if;
  if jsonb_typeof(coalesce(p_family,'[]'::jsonb))<>'array' then raise exception 'invalid: family members must be a list'; end if;
  family_count:=jsonb_array_length(coalesce(p_family,'[]'::jsonb));
  if family_count>family_member_limit(a) then
    raise exception 'invalid: this association allows at most % family members',family_member_limit(a);
  end if;
  if not can_manage_members(a) and not owns_flat(p_flat::text) and not exists(
    select 1 from memberships where association_id=a and flat_id=p_flat and user_id=auth.uid()
      and role='resident' and ended_at is null
  ) then raise exception 'not_allowed: membership management access required'; end if;
  if family_count>0 and not owns_flat(p_flat::text) and not exists(
    select 1 from memberships where association_id=a and flat_id=p_flat and user_id=auth.uid()
      and role='resident' and ended_at is null
  ) then raise exception 'not_allowed: only the associated owner or resident may share family DOBs'; end if;

  select code into request_code from approval_requests
  where id=p_request and association_id=a and initiator=auth.uid() for update;
  expected_code:=case when p_type='owner' then 'W20' else 'W21' end;
  if request_code is distinct from expected_code then
    raise exception 'not_allowed: request type or initiator does not match';
  end if;
  if not exists(select 1 from flats where id=p_flat and association_id=a) then
    raise exception 'invalid: selected flat is not in this association';
  end if;

  insert into membership_changes(request_id,association_id,flat_id,change_type,incoming_name,incoming_email,
    incoming_mobile,lease_period,family_count,family_details_required)
  values(p_request,a,p_flat,p_type,trim(p_name),lower(trim(p_email)),nullif(trim(p_mobile),''),
    nullif(trim(p_lease),''),family_count,true);

  for family_row in select * from jsonb_to_recordset(coalesce(p_family,'[]'::jsonb))
    as x(full_name text,date_of_birth date,email text)
  loop
    if coalesce(trim(family_row.full_name),'')='' or family_row.date_of_birth is null
      or family_row.date_of_birth>current_date then
      raise exception 'invalid: every family member needs a name and valid date of birth';
    end if;
    if family_row.email is not null and trim(family_row.email)<>''
      and trim(family_row.email) !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'invalid: enter a valid family-member email';
    end if;
    if lower(trim(coalesce(family_row.email,'')))=lower(trim(p_email)) then
      raise exception 'invalid: each family member needs a separate email from the incoming resident';
    end if;
    insert into family_members(association_id,flat_id,request_id,full_name,date_of_birth,email,created_by)
    values(a,p_flat,p_request,trim(family_row.full_name),family_row.date_of_birth,
      nullif(lower(trim(family_row.email)),''),auth.uid());
  end loop;
end $$;
revoke all on function create_membership_change_with_family(uuid,uuid,text,text,text,text,text,jsonb) from public;
grant execute on function create_membership_change_with_family(uuid,uuid,text,text,text,text,text,jsonb) to authenticated;

create function enforce_family_count_limit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.change_type='resident' and new.family_count>family_member_limit(new.association_id) then
    raise exception 'invalid: this association allows at most % family members',family_member_limit(new.association_id);
  end if;
  return new;
end $$;
create trigger membership_change_family_count_limit before insert or update of family_count,association_id,change_type
on membership_changes for each row execute function enforce_family_count_limit();

create function enforce_additional_resident_family_rule()
returns trigger language plpgsql security definer set search_path=public as $$
declare person_email text; a uuid;
begin
  if new.role<>'resident' or new.flat_id is null then return new; end if;
  a:=new.association_id;
  perform 1 from flats where association_id=a and id=new.flat_id for update;
  if not exists(select 1 from memberships m where m.association_id=a and m.flat_id=new.flat_id
      and m.role='resident' and m.ended_at is null)
    and not exists(select 1 from invites i where i.association_id=a and i.flat_id=new.flat_id
      and i.role='resident' and i.claimed_at is null) then return new; end if;
  if tg_table_name='memberships' then
    select lower(email) into person_email from profiles where id=new.user_id;
  else
    person_email:=lower(new.email);
  end if;
    if tg_table_name='memberships' and exists(select 1 from invites i where i.association_id=a
      and i.flat_id=new.flat_id and i.role='resident' and i.claimed_at is null
      and lower(i.email)=person_email) then
    return new;
  end if;
  if not exists(select 1 from family_members fm where fm.association_id=a and fm.flat_id=new.flat_id
      and lower(fm.email)=person_email and fm.approved_at is not null and fm.archived_at is null
      and extract(year from age(current_date,fm.date_of_birth))>=family_member_min_login_age(a)) then
    raise exception 'not_allowed: additional resident accounts must be approved family members who meet the age rule';
  end if;
  return new;
end $$;
create trigger additional_resident_membership_rule before insert on memberships
for each row execute function enforce_additional_resident_family_rule();
create trigger additional_resident_invite_rule before insert on invites
for each row execute function enforce_additional_resident_family_rule();

create function update_family_member_email(p_member uuid,p_email text)
returns void language plpgsql security definer set search_path=public as $$
declare m family_members; age_limit integer; uid uuid;
begin
  select * into m from family_members where id=p_member and association_id=my_association() for update;
  if m.id is null or m.archived_at is not null then
    raise exception 'not_found: active family member not found';
  end if;
  if m.created_by<>auth.uid() or (not owns_flat(m.flat_id::text) and not exists(
    select 1 from memberships x where x.association_id=m.association_id
      and x.flat_id=m.flat_id and x.user_id=auth.uid() and x.role='resident' and x.ended_at is null
  )) then
    raise exception 'not_allowed: only the submitting owner or resident may update family account details';
  end if;
  if m.approved_at is null then raise exception 'not_allowed: family member approval is required before adding a login email'; end if;
  age_limit:=family_member_min_login_age(m.association_id);
  if extract(year from age(current_date,m.date_of_birth))<age_limit then
    raise exception 'not_allowed: this family member is not yet eligible for an account';
  end if;
  if m.email is not null then raise exception 'invalid: an email is already assigned to this family member'; end if;
  if coalesce(trim(p_email),'') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid: enter a valid email address';
  end if;
  if exists(select 1 from memberships x join profiles p on p.id=x.user_id
      where x.association_id=m.association_id and x.flat_id=m.flat_id and x.role='resident'
        and x.ended_at is null and lower(p.email)=lower(trim(p_email)))
    or exists(select 1 from invites i where i.association_id=m.association_id and i.flat_id=m.flat_id
      and i.role='resident' and i.claimed_at is null and lower(i.email)=lower(trim(p_email))) then
    raise exception 'invalid: a family member must use a separate email from the primary resident';
  end if;
  update family_members set email=lower(trim(p_email)) where id=p_member;
  select id into uid from profiles where lower(email)=lower(trim(p_email)) limit 1;
  if uid is not null and not exists (
    select 1 from memberships where association_id=m.association_id and user_id=uid
      and role='resident' and flat_id=m.flat_id and ended_at is null
  ) then
    insert into memberships(association_id,user_id,role,flat_id)
    values(m.association_id,uid,'resident',m.flat_id);
  end if;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(m.association_id,auth.uid(),'set_family_member_email','family_member',m.id::text,
    jsonb_build_object('email',lower(trim(p_email))));
end $$;
revoke all on function update_family_member_email(uuid,text) from public;
grant execute on function update_family_member_email(uuid,text) to authenticated;

create function claim_eligible_family_members()
returns boolean language plpgsql security definer set search_path=public as $$
declare v_user_id uuid:=auth.uid(); user_email text; m record; claimed boolean:=false;
begin
  if v_user_id is null then return false; end if;
  select lower(email) into user_email from auth.users where id=v_user_id and email_confirmed_at is not null;
  if user_email is null then return false; end if;
  for m in
    select fm.association_id,fm.flat_id
    from family_members fm
    where lower(fm.email)=user_email and fm.approved_at is not null and fm.archived_at is null
      and extract(year from age(current_date,fm.date_of_birth))>=family_member_min_login_age(fm.association_id)
  loop
    if not exists(select 1 from memberships x where x.association_id=m.association_id and x.user_id=v_user_id
      and x.role='resident' and x.flat_id=m.flat_id and x.ended_at is null) then
      insert into memberships(association_id,user_id,role,flat_id)
      values(m.association_id,v_user_id,'resident',m.flat_id);
    end if;
    if not claimed then perform set_active_association(m.association_id); end if;
    claimed:=true;
  end loop;
  return claimed;
end $$;
revoke all on function claim_eligible_family_members() from public;
grant execute on function claim_eligible_family_members() to authenticated;

-- Extend the existing auth trigger without weakening invite-only membership in an association.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
declare n text; mob text; eligible_family boolean;
begin
  select full_name,mobile into n,mob
  from invites where lower(email)=lower(new.email) and claimed_at is null
  order by mobile nulls last limit 1;

  select exists(
    select 1 from family_members fm
    where lower(fm.email)=lower(new.email) and fm.approved_at is not null and fm.archived_at is null
      and new.email_confirmed_at is not null
      and extract(year from age(current_date,fm.date_of_birth))>=family_member_min_login_age(fm.association_id)
  ) into eligible_family;

  if exists(
    select 1 from family_members fm where lower(fm.email)=lower(new.email)
      and fm.approved_at is not null and fm.archived_at is null
      and extract(year from age(current_date,fm.date_of_birth))<family_member_min_login_age(fm.association_id)
      and not exists(select 1 from family_members eligible where lower(eligible.email)=lower(new.email)
        and eligible.approved_at is not null and eligible.archived_at is null
        and extract(year from age(current_date,eligible.date_of_birth))>=family_member_min_login_age(eligible.association_id))
      and not exists(select 1 from invites i where lower(i.email)=lower(new.email) and i.claimed_at is null)
  ) then
    raise exception 'not_allowed: this family member has not reached the account age';
  end if;

  if n is null and eligible_family then
    select full_name into n from family_members fm
    where lower(fm.email)=lower(new.email) and fm.approved_at is not null and fm.archived_at is null
      and extract(year from age(current_date,fm.date_of_birth))>=family_member_min_login_age(fm.association_id)
    order by fm.created_at limit 1;
  end if;
  if n is null then
    n:=coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1));
    mob:=nullif(trim(new.raw_user_meta_data->>'mobile'),'');
  end if;
  if exists(select 1 from profiles where mobile=mob) then mob:=null; end if;
  insert into profiles(id,full_name,email,mobile) values(new.id,n,new.email,mob);

  if exists(select 1 from invites where lower(email)=lower(new.email) and claimed_at is null) then
    insert into memberships(association_id,user_id,role,flat_id,designations,monitor_categories,
      monitor_from,monitor_until,assigned_by,support_flags,contact_phone,date_of_birth)
    select i.association_id,new.id,i.role,i.flat_id,i.designations,i.monitor_categories,
      i.monitor_from,i.monitor_until,i.assigned_by,i.support_flags,i.mobile,i.date_of_birth
    from invites i where lower(i.email)=lower(new.email) and i.claimed_at is null;
    update invites set claimed_at=now() where lower(email)=lower(new.email) and claimed_at is null;
  end if;

  insert into memberships(association_id,user_id,role,flat_id)
  select fm.association_id,new.id,'resident',fm.flat_id
  from family_members fm
  where lower(fm.email)=lower(new.email) and fm.approved_at is not null and fm.archived_at is null
    and new.email_confirmed_at is not null
    and extract(year from age(current_date,fm.date_of_birth))>=family_member_min_login_age(fm.association_id)
    and not exists(select 1 from memberships x where x.association_id=fm.association_id and x.user_id=new.id
      and x.role='resident' and x.flat_id=fm.flat_id and x.ended_at is null);
  return new;
end $$;

-- Keep the existing approval workflow; apply dependent memberships after its transaction succeeds.
alter function decide_step(uuid,decision,text) rename to decide_step_family_base;
revoke all on function decide_step_family_base(uuid,decision,text) from public,authenticated;
create function decide_step(req uuid,d decision,note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare r approval_requests; c membership_changes; a uuid; max_members integer; age_limit integer; dep record; uid uuid; dep_count integer;
begin
  select * into r from approval_requests where id=req;
  perform decide_step_family_base(req,d,note);
  if d<>'approved' or r.code<>'W21' then return; end if;
  if exists(select 1 from approval_steps where request_id=req and decision<>'approved') then return; end if;

  select * into c from membership_changes where request_id=req and association_id=r.association_id for update;
  if c.request_id is null then raise exception 'invalid: resident change data missing'; end if;
  a:=r.association_id;
  max_members:=family_member_limit(a);
  age_limit:=family_member_min_login_age(a);
  select count(*) into dep_count from family_members where request_id=req and association_id=a;
  if not c.family_details_required then return; end if;
  if dep_count<>c.family_count then
    raise exception 'invalid: enter details for every family member';
  end if;
  if dep_count>max_members then raise exception 'invalid: this association allows at most % family members',max_members; end if;
  if exists(select 1 from family_members fm where fm.request_id=req and lower(fm.email)=lower(c.incoming_email)) then
    raise exception 'invalid: a family member must use a separate email from the incoming resident';
  end if;

  update family_members set archived_at=now()
  where association_id=a and flat_id=c.flat_id and approved_at is not null and archived_at is null;
  update family_members set approved_at=now()
  where request_id=req and association_id=a and approved_at is null;

  for dep in
    select fm.* from family_members fm where fm.request_id=req and fm.association_id=a and fm.email is not null
      and extract(year from age(current_date,fm.date_of_birth))>=age_limit
  loop
    select id into uid from profiles where lower(email)=lower(dep.email) limit 1;
    if uid is not null and not exists(select 1 from memberships where association_id=a and user_id=uid
      and role='resident' and flat_id=c.flat_id and ended_at is null) then
      insert into memberships(association_id,user_id,role,flat_id) values(a,uid,'resident',c.flat_id);
    end if;
  end loop;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'apply_family_members','membership_change',req::text,
    jsonb_build_object('dependent_count',dep_count,'minimum_login_age',age_limit));
end $$;
revoke all on function decide_step(uuid,decision,text) from public;
grant execute on function decide_step(uuid,decision,text) to authenticated;
