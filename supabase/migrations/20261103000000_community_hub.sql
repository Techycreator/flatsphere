create table emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  label text not null check (length(trim(label)) between 1 and 100),
  contact_name text not null check (length(trim(contact_name)) between 1 and 120),
  phone text not null check (length(trim(phone)) between 5 and 24),
  category text not null default 'Emergency',
  notes text not null default '',
  active boolean not null default true,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table emergency_contacts enable row level security;
create policy emergency_contacts_read on emergency_contacts for select using (is_member(association_id) and active);
create policy emergency_contacts_manage on emergency_contacts for all using (
  has_role(association_id,array['admin','president','secretary']::app_role[])
) with check (has_role(association_id,array['admin','president','secretary']::app_role[]));

create table fund_requests (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  request_type text not null check (request_type in ('recurring','ad_hoc')),
  amount integer check (amount is null or amount > 0),
  basis text not null default '',
  due_day text,
  mom_ref text not null check (length(trim(mom_ref)) > 0),
  approval_request_id uuid not null unique references approval_requests(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','active','rejected','sent_back')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  approved_by uuid references profiles(id),
  approved_at timestamptz
);
alter table fund_requests enable row level security;
create policy fund_requests_read on fund_requests for select using (
  association_id = my_association() and (has_role(association_id,
    array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','auditor']::app_role[])
    or status='active')
);

create function request_fund(p_title text,p_type text,p_amount integer,p_basis text,p_due_day text,p_mom_ref text,p_ref text)
returns uuid language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); r uuid; fund_id uuid; actor_role app_role;
begin
  if a is null or not has_role(a,array['secretary','joint_secretary','treasurer','joint_treasurer']::app_role[]) then
    raise exception 'not_allowed: Secretary or Treasurer role required to submit a fund request';
  end if;
  if coalesce(trim(p_title),'')='' or p_type not in ('recurring','ad_hoc') then raise exception 'invalid: enter a title and request type'; end if;
  if p_amount is not null and p_amount<=0 then raise exception 'invalid: amount must be greater than zero'; end if;
  if coalesce(trim(p_mom_ref),'')='' then raise exception 'invalid: EC MOM reference is required'; end if;
  if coalesce(trim(p_ref),'')='' then raise exception 'invalid: workflow reference is required'; end if;
  select role into actor_role from memberships where association_id=a and user_id=auth.uid() and ended_at is null
    and role in ('secretary','joint_secretary','treasurer','joint_treasurer') order by role limit 1;
  insert into approval_requests (association_id,ref,code,title,details,initiator,initiator_name,initiator_role,category,mom_required,mom_ref)
  values (a,trim(p_ref),'W12','Fund request: '||trim(p_title),jsonb_build_object('Title',trim(p_title),'Amount',p_amount,'Basis',p_basis),
    auth.uid(),my_name(),actor_role,'Fund request',true,trim(p_mom_ref)) returning id into r;
  insert into approval_steps (request_id,seq,role,name) values (r,1,'president','President');
  insert into fund_requests (association_id,title,request_type,amount,basis,due_day,mom_ref,approval_request_id,created_by)
  values (a,trim(p_title),p_type,p_amount,trim(coalesce(p_basis,'')),nullif(trim(p_due_day),''),trim(p_mom_ref),r,auth.uid())
  returning id into fund_id;
  insert into workflow_action_log (workflow_instance_id,actor_id,action,new_value)
  select workflow_instance_id,auth.uid(),'fund_request_submitted',jsonb_build_object('fund_request_id',fund_id)
  from approval_requests where id=r and workflow_instance_id is not null;
  return fund_id;
end $$;

create function sync_fund_request_approval() returns trigger
language plpgsql security definer set search_path=public as $$
declare r approval_requests; s text;
begin
  if old.decision is not distinct from new.decision or new.decision='pending' then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  if r.code<>'W12' then return new; end if;
  if exists(select 1 from approval_steps where request_id=new.request_id and decision='pending') then return new; end if;
  s:=case new.decision when 'approved' then 'active' when 'rejected' then 'rejected' else 'sent_back' end;
  update fund_requests set status=s,approved_by=case when s='active' then new.decided_by else null end,
    approved_at=case when s='active' then now() else null end where approval_request_id=new.request_id;
  return new;
end $$;
create trigger fund_request_approval_sync after update of decision on approval_steps
  for each row execute function sync_fund_request_approval();

create table community_events (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  event_type text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text not null default '',
  budget integer check (budget is null or budget >= 0),
  fund_request_id uuid references fund_requests(id),
  description text not null default '',
  status text not null default 'scheduled' check (status in ('draft','scheduled','cancelled','completed')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
alter table expenses add column event_id uuid references community_events(id) on delete set null;
create function validate_expense_event() returns trigger
language plpgsql set search_path=public as $$
begin
  if new.event_id is not null and not exists (
    select 1 from community_events e where e.id=new.event_id and e.association_id=new.association_id
  ) then raise exception 'invalid: event must belong to the active association'; end if;
  return new;
end $$;
create trigger expenses_validate_event before insert or update of event_id on expenses
  for each row execute function validate_expense_event();
alter table community_events enable row level security;
create policy community_events_read on community_events for select using (is_member(association_id));
create policy community_events_manage on community_events for all using (
  has_role(association_id,array['president','secretary','joint_secretary']::app_role[])
) with check (has_role(association_id,array['president','secretary','joint_secretary']::app_role[]));

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('community-event-photos','community-event-photos',false,5242880,array['image/jpeg'])
on conflict (id) do nothing;
create table community_event_photos (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  event_id uuid not null references community_events(id) on delete cascade,
  storage_path text not null unique,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table community_event_photos enable row level security;
create policy event_photos_read on community_event_photos for select using (is_member(association_id));
create policy event_photos_insert on community_event_photos for insert with check (
  association_id=my_association() and uploaded_by=auth.uid()
  and has_role(association_id,array['president','secretary','joint_secretary']::app_role[])
  and exists (select 1 from community_events e where e.id=event_id and e.association_id=association_id)
);
create policy event_photos_storage_read on storage.objects for select to authenticated using (
  bucket_id='community-event-photos'
  and exists(select 1 from community_event_photos p where p.storage_path=name and is_member(p.association_id))
);
create policy event_photos_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id='community-event-photos' and (storage.foldername(name))[1]=my_association()::text
  and has_role(my_association(),array['president','secretary','joint_secretary']::app_role[])
);

create table meeting_actions (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  event_id uuid references community_events(id) on delete set null,
  mom_ref text not null,
  title text not null check (length(trim(title)) between 1 and 240),
  owner_id uuid references profiles(id),
  owner_name text not null,
  due_date date,
  status text not null default 'open' check (status in ('open','in_progress','blocked','done','cancelled')),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table meeting_actions enable row level security;
create policy meeting_actions_read on meeting_actions for select using (
  association_id=my_association() and (owner_id=auth.uid() or has_role(association_id,
    array['admin','president','secretary','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[]))
);
create policy meeting_actions_manage on meeting_actions for all using (
  has_role(association_id,array['admin','president','secretary','joint_secretary']::app_role[])
) with check (has_role(association_id,array['admin','president','secretary','joint_secretary']::app_role[]));

create function add_meeting_action(p_mom_ref text,p_title text,p_due_date date default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); action_id uuid;
begin
  if a is null or not has_role(a,array['president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: President, Secretary or Joint Secretary required';
  end if;
  if coalesce(trim(p_mom_ref),'')='' or coalesce(trim(p_title),'')='' then
    raise exception 'invalid: MOM reference and action are required';
  end if;
  insert into meeting_actions (association_id,mom_ref,title,owner_id,owner_name,due_date)
  values (a,trim(p_mom_ref),trim(p_title),auth.uid(),my_name(),p_due_date)
  returning id into action_id;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
  values (a,auth.uid(),'add_meeting_action','meeting_action',action_id::text,
    jsonb_build_object('mom_ref',trim(p_mom_ref),'title',trim(p_title),'due_date',p_due_date));
  return action_id;
end $$;

create function update_meeting_action_status(p_action uuid,p_status text) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); action_row meeting_actions;
begin
  if p_status not in ('open','in_progress','blocked','done','cancelled') then
    raise exception 'invalid: unsupported action status';
  end if;
  select * into action_row from meeting_actions where id=p_action and association_id=a for update;
  if action_row.id is null then raise exception 'not_found'; end if;
  if action_row.owner_id <> auth.uid() and not has_role(a,array['president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the assignee or an office bearer can update this action';
  end if;
  update meeting_actions set status=p_status,completed_at=case when p_status='done' then now() else null end where id=p_action;
  insert into audit_log (association_id,actor,action,entity,entity_id,before,after)
  values (a,auth.uid(),'update_meeting_action','meeting_action',p_action::text,
    jsonb_build_object('status',action_row.status),jsonb_build_object('status',p_status));
end $$;

revoke all on function add_meeting_action(text,text,date) from public;
grant execute on function add_meeting_action(text,text,date) to authenticated;
revoke all on function update_meeting_action_status(uuid,text) from public;
grant execute on function update_meeting_action_status(uuid,text) to authenticated;

create table marketplace_posts (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  post_type text not null check (post_type in ('for_sale','wanted','service_recommendation')),
  title text not null check (length(trim(title)) between 1 and 120),
  description text not null check (length(trim(description)) between 1 and 1000),
  price integer check (price is null or price >= 0),
  contact text not null check (length(trim(contact)) between 1 and 120),
  created_by uuid not null default auth.uid() references profiles(id),
  created_by_name text not null default my_name(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '30 days',
  status text not null default 'active' check (status in ('active','removed','expired'))
);
create index marketplace_active_idx on marketplace_posts (association_id,expires_at desc) where status='active';
alter table marketplace_posts enable row level security;
create policy marketplace_read on marketplace_posts for select using (
  association_id=my_association() and status='active' and expires_at>now() and is_member(association_id)
);
create policy marketplace_insert on marketplace_posts for insert with check (
  association_id=my_association() and created_by=auth.uid() and has_role(association_id,array['owner']::app_role[])
);
create policy marketplace_update on marketplace_posts for update using (
  association_id=my_association() and (created_by=auth.uid() or has_role(association_id,array['president','secretary']::app_role[]))
) with check (association_id=my_association());

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('community-event-photos','community-event-photos',false,5242880,array['image/jpeg']) on conflict (id) do nothing;
create table community_event_photos (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  event_id uuid not null references community_events(id) on delete cascade,
  storage_path text not null unique,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table community_event_photos enable row level security;
create policy event_photos_read on community_event_photos for select using (is_member(association_id));
create policy event_photos_insert on community_event_photos for insert with check (
  association_id=my_association() and uploaded_by=auth.uid()
  and has_role(association_id,array['president','secretary','joint_secretary']::app_role[])
);
create policy event_photos_storage_read on storage.objects for select to authenticated using (
  bucket_id='community-event-photos' and exists(select 1 from community_event_photos p where p.storage_path=name and is_member(p.association_id))
);
create policy event_photos_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id='community-event-photos' and (storage.foldername(name))[1]=my_association()::text
  and has_role(my_association(),array['president','secretary','joint_secretary']::app_role[])
);