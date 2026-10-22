create table association_register_items (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  record_type text not null check (record_type in ('asset','insurance','compliance','conflict')),
  name text not null check (length(trim(name)) between 1 and 160),
  category text not null default '',
  vendor text,
  purchase_date date,
  warranty_end date,
  amc_end date,
  expires_on date,
  expected_life_years smallint check (expected_life_years is null or expected_life_years between 1 and 100),
  replacement_cost bigint check (replacement_cost is null or replacement_cost >= 0),
  details jsonb not null default '{}'::jsonb,
  approval_request_id uuid not null unique references approval_requests(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','active','rejected','retired')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  approved_by uuid references profiles(id),
  approved_at timestamptz
);
create index association_register_expiry_idx on association_register_items (association_id, expires_on)
  where status = 'active' and expires_on is not null;
alter table association_register_items enable row level security;
create policy association_register_read on association_register_items for select using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer']::app_role[])
);

insert into workflow_types (association_id,code,version,name,description,requires_mom)
select id,'W24',1,'Association register change','Add or update an asset, insurance, compliance or conflict record',false
from associations
on conflict (association_id,code,version) do nothing;
insert into workflow_type_steps (workflow_type_id,step_no,label,role_required,action_type)
select id,1,'President approval','president','approval' from workflow_types where code='W24' and version=1
on conflict (workflow_type_id,step_no) do nothing;
insert into workflow_type_steps (workflow_type_id,step_no,label,action_type)
select id,2,'Publish approved register entry','execute' from workflow_types where code='W24' and version=1
on conflict (workflow_type_id,step_no) do nothing;

create function submit_association_register_item(
  p_type text,
  p_name text,
  p_category text,
  p_vendor text,
  p_purchase_date date,
  p_warranty_end date,
  p_amc_end date,
  p_expires_on date,
  p_expected_life_years smallint,
  p_replacement_cost bigint,
  p_details jsonb,
  p_ref text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  r uuid;
  item_id uuid;
  initiator_role app_role;
  approval_role app_role;
  who text := my_name();
begin
  if a is null or not has_role(a,array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: an Admin or office bearer is required to submit register changes';
  end if;
  if p_type not in ('asset','insurance','compliance','conflict') then raise exception 'invalid: unsupported register type'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'invalid: enter a name'; end if;
  if p_type in ('insurance','compliance') and p_expires_on is null then
    raise exception 'invalid: expiry date is required for insurance and compliance records';
  end if;
  if coalesce(trim(p_ref),'') = '' then raise exception 'invalid: request reference is required'; end if;
  select role into initiator_role from memberships where association_id=a and user_id=auth.uid() and ended_at is null
    and role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer')
    order by case role when 'secretary' then 1 when 'treasurer' then 2 else 3 end limit 1;
  approval_role := case when initiator_role='president' then 'vice_president'::app_role else 'president'::app_role end;
  insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category)
  values (a,trim(p_ref),'W24','Register change: '||trim(p_name),
    jsonb_build_object('Type',p_type,'Name',trim(p_name),'Category',p_category),auth.uid(),who,initiator_role,'Association register')
  returning id into r;
  insert into approval_steps (request_id,seq,role,name,on_behalf_of)
  values (r,1,approval_role,case when approval_role='president' then 'President' else 'Vice President' end,
    case when initiator_role='president' then 'President' else null end);
  insert into association_register_items (association_id,record_type,name,category,vendor,purchase_date,warranty_end,amc_end,
    expires_on,expected_life_years,replacement_cost,details,approval_request_id,created_by)
  values (a,p_type,trim(p_name),trim(coalesce(p_category,'')),nullif(trim(p_vendor),''),p_purchase_date,p_warranty_end,p_amc_end,
    p_expires_on,p_expected_life_years,p_replacement_cost,coalesce(p_details,'{}'::jsonb),r,auth.uid())
  returning id into item_id;
  insert into workflow_action_log (workflow_instance_id,actor_id,action,new_value)
  select workflow_instance_id,auth.uid(),'register_submitted',jsonb_build_object('item_id',item_id,'type',p_type)
  from approval_requests where id=r and workflow_instance_id is not null;
  return item_id;
end $$;

create function sync_association_register_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; new_status text;
begin
  if new.decision='pending' or old.decision is not distinct from new.decision then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  if r.code<>'W24' then return new; end if;
  if exists (select 1 from approval_steps where request_id=new.request_id and decision='pending') then return new; end if;
  new_status := case when new.decision='approved' then 'active' when new.decision='rejected' then 'rejected' else 'pending' end;
  update association_register_items set status=new_status,
    approved_by=case when new_status='active' then new.decided_by else null end,
    approved_at=case when new_status='active' then coalesce(new.decided_at,now()) else null end
    where approval_request_id=new.request_id and association_id=r.association_id;
  return new;
end $$;
create trigger association_register_approval_sync after update of decision on approval_steps
  for each row execute function sync_association_register_approval();

create trigger archive_association_register_changes after update or delete on association_register_items
  for each row execute function archive_row_change('association_register_item');

create function expiring_association_records(p_days integer default 90)
returns setof association_register_items language plpgsql stable security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','auditor']::app_role[]) then
    raise exception 'not_allowed: finance or office-bearer access is required';
  end if;
  return query select i.* from association_register_items i
    where i.association_id=a and i.status='active'
      and greatest(coalesce(i.expires_on,'-infinity'),coalesce(i.amc_end,'-infinity'),coalesce(i.warranty_end,'-infinity'))
        between current_date and current_date + least(greatest(coalesce(p_days,90),1),365)
    order by least(coalesce(i.expires_on,'infinity'),coalesce(i.amc_end,'infinity'),coalesce(i.warranty_end,'infinity'));
end $$;