create table workflow_types (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  code text not null,
  version integer not null default 1 check (version > 0),
  name text not null,
  description text not null default '',
  requires_mom boolean not null default false,
  active boolean not null default true,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  unique (association_id, code, version)
);
alter table workflow_types enable row level security;
create policy workflow_types_read on workflow_types for select using (is_member(association_id));

create table workflow_type_steps (
  id uuid primary key default gen_random_uuid(),
  workflow_type_id uuid not null references workflow_types(id) on delete cascade,
  step_no integer not null check (step_no > 0),
  label text not null,
  role_required app_role,
  alternate_role app_role,
  action_type text not null check (action_type in ('approval','cooling_period','execute','notification')),
  mandatory boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  unique (workflow_type_id, step_no)
);
alter table workflow_type_steps enable row level security;
create policy workflow_type_steps_read on workflow_type_steps for select using (
  exists (select 1 from workflow_types t where t.id = workflow_type_steps.workflow_type_id and is_member(t.association_id))
);

alter table approval_requests add column workflow_instance_id uuid;

create table workflow_instances (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  workflow_type_id uuid not null references workflow_types(id),
  workflow_version integer not null,
  approval_request_id uuid not null unique references approval_requests(id) on delete cascade,
  entity_type text not null,
  entity_id text,
  title text not null,
  initiated_by uuid not null references profiles(id),
  status text not null default 'pending' check (status in ('pending','approved','rejected','sent_back','completed')),
  current_step integer not null default 1,
  submitted_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table approval_requests add constraint approval_requests_workflow_instance_fk
  foreign key (workflow_instance_id) references workflow_instances(id) deferrable initially deferred;
alter table workflow_instances enable row level security;
create policy workflow_instances_read on workflow_instances for select using (
  association_id = my_association() and (
    initiated_by = auth.uid()
    or has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','auditor']::app_role[])
    or is_step_party(approval_request_id, association_id)
  )
);

create table workflow_instance_steps (
  id uuid primary key default gen_random_uuid(),
  workflow_instance_id uuid not null references workflow_instances(id) on delete cascade,
  approval_step_id bigint not null unique references approval_steps(id) on delete cascade,
  step_no integer not null,
  label text not null,
  role_required app_role not null,
  alternate_role app_role,
  assigned_user uuid references profiles(id),
  action_type text not null default 'approval',
  mandatory boolean not null default true,
  status decision not null default 'pending',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (workflow_instance_id, step_no)
);
alter table workflow_instance_steps enable row level security;
create policy workflow_instance_steps_read on workflow_instance_steps for select using (
  exists (select 1 from workflow_instances w where w.id = workflow_instance_steps.workflow_instance_id)
);

create table workflow_approvals (
  id uuid primary key default gen_random_uuid(),
  workflow_instance_id uuid not null references workflow_instances(id) on delete cascade,
  instance_step_id uuid not null references workflow_instance_steps(id) on delete cascade,
  approver_id uuid not null references profiles(id),
  action decision not null check (action <> 'pending'),
  comments text,
  approved_at timestamptz not null default now(),
  unique (instance_step_id)
);
alter table workflow_approvals enable row level security;
create policy workflow_approvals_read on workflow_approvals for select using (
  exists (select 1 from workflow_instances w where w.id = workflow_approvals.workflow_instance_id)
);

create table workflow_comments (
  id uuid primary key default gen_random_uuid(),
  workflow_instance_id uuid not null references workflow_instances(id) on delete cascade,
  user_id uuid not null default auth.uid() references profiles(id),
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table workflow_comments enable row level security;
create policy workflow_comments_read on workflow_comments for select using (
  exists (select 1 from workflow_instances w where w.id = workflow_comments.workflow_instance_id)
);
create policy workflow_comments_insert on workflow_comments for insert with check (
  user_id = auth.uid() and exists (
    select 1 from workflow_instances w join approval_requests r on r.id = w.approval_request_id
    where w.id = workflow_comments.workflow_instance_id
      and (r.initiator = auth.uid() or is_step_party(r.id,r.association_id)
        or has_role(r.association_id,array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[]))
  )
);

create table workflow_attachments (
  id uuid primary key default gen_random_uuid(),
  workflow_instance_id uuid not null references workflow_instances(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  document_type text not null,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table workflow_attachments enable row level security;
create policy workflow_attachments_read on workflow_attachments for select using (
  exists (select 1 from workflow_instances w where w.id = workflow_attachments.workflow_instance_id)
);

create table workflow_notifications (
  id uuid primary key default gen_random_uuid(),
  workflow_instance_id uuid not null references workflow_instances(id) on delete cascade,
  user_id uuid not null references profiles(id),
  channel text not null check (channel in ('in_app','email','sms','push')),
  status text not null default 'queued' check (status in ('queued','sent','failed')),
  sent_at timestamptz,
  error text,
  created_at timestamptz not null default now()
);
alter table workflow_notifications enable row level security;
create policy workflow_notifications_read_self on workflow_notifications for select using (user_id = auth.uid());

create table workflow_action_log (
  id bigint generated always as identity primary key,
  workflow_instance_id uuid not null references workflow_instances(id) on delete cascade,
  actor_id uuid references profiles(id),
  action text not null,
  old_value jsonb,
  new_value jsonb,
  at timestamptz not null default now()
);
alter table workflow_action_log enable row level security;
create policy workflow_action_log_read on workflow_action_log for select using (
  exists (select 1 from workflow_instances w where w.id = workflow_action_log.workflow_instance_id)
);

create function seed_workflow_catalog(p_assoc uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d record; wf_id uuid;
begin
  for d in select * from (values
    ('W1','Access change','Change a member role or access level',false),
    ('W2','Visibility template','Change role visibility after EC vote and MOM',true),
    ('W3','Bank change','Change association bank account details',true),
    ('W4','Category change','Approve a new income or expense category',false),
    ('W6','Monitor assignment','Assign monitor areas and duration',false),
    ('W12','Fund request','Approve recurring or ad hoc funds',true),
    ('W16','Late fee rule','Approve late fee policy',true),
    ('W20','Owner change','Transfer flat ownership',false),
    ('W21','Resident change','Tenant onboarding or offboarding',false),
    ('W22','Committee change','Change committee membership',true),
    ('W23','Income category','Approve an income category',false)
  ) as d(code,name,description,requires_mom)
  loop
    insert into workflow_types (association_id,code,version,name,description,requires_mom)
    values (p_assoc,d.code,1,d.name,d.description,d.requires_mom)
    on conflict (association_id,code,version) do nothing;
    select id into wf_id from workflow_types where association_id=p_assoc and code=d.code and version=1;
    if not exists (select 1 from workflow_type_steps where workflow_type_id=wf_id) then
      if d.code='W3' then
        insert into workflow_type_steps (workflow_type_id,step_no,label,role_required,action_type) values
          (wf_id,1,'Treasurer approval','treasurer','approval'),(wf_id,2,'Secretary approval','secretary','approval'),
          (wf_id,3,'President approval','president','approval'),(wf_id,4,'48-hour cooling period',null,'cooling_period'),
          (wf_id,5,'Activate bank details',null,'execute');
      elsif d.code='W20' then
        insert into workflow_type_steps (workflow_type_id,step_no,label,role_required,action_type) values
          (wf_id,1,'Secretary approval','secretary','approval'),(wf_id,2,'President approval','president','approval'),
          (wf_id,3,'Update owner records',null,'execute');
      elsif d.code='W21' then
        insert into workflow_type_steps (workflow_type_id,step_no,label,role_required,action_type) values
          (wf_id,1,'Owner consent','owner','approval'),(wf_id,2,'Secretary approval','secretary','approval'),
          (wf_id,3,'Update resident records',null,'execute');
      else
        insert into workflow_type_steps (workflow_type_id,step_no,label,role_required,action_type) values
          (wf_id,1,'President approval','president','approval'),(wf_id,2,'Execute approved change',null,'execute');
      end if;
    end if;
  end loop;
end $$;

create function seed_workflow_catalog_on_association() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform seed_workflow_catalog(new.id);
  return new;
end $$;
create trigger associations_seed_workflows after insert on associations
  for each row execute function seed_workflow_catalog_on_association();
select seed_workflow_catalog(id) from associations;

create function link_approval_workflow_instance() returns trigger
language plpgsql security definer set search_path = public as $$
declare type_id uuid; type_version integer; instance_id uuid; entity_label text; entity_value text;
begin
  select t.id,t.version into type_id,type_version from workflow_types t
    where t.association_id=new.association_id and t.code=new.code and t.active order by t.version desc limit 1;
  if type_id is null then return new; end if;
  entity_label := case when new.code in ('W20','W21') then 'flat' else lower(new.category) end;
  entity_value := coalesce(new.details->>'Flat',new.ref);
  insert into workflow_instances (association_id,workflow_type_id,workflow_version,approval_request_id,
    entity_type,entity_id,title,initiated_by,status)
  values (new.association_id,type_id,type_version,new.id,entity_label,entity_value,new.title,new.initiator,'pending')
  returning id into instance_id;
  update approval_requests set workflow_instance_id=instance_id where id=new.id;
  insert into workflow_action_log (workflow_instance_id,actor_id,action,new_value)
  values (instance_id,new.initiator,'submitted',jsonb_build_object('status','pending','ref',new.ref));
  insert into workflow_notifications (workflow_instance_id,user_id,channel) values (instance_id,new.initiator,'in_app');
  return new;
end $$;
create trigger approval_request_create_workflow after insert on approval_requests
  for each row execute function link_approval_workflow_instance();

do $$
declare
  r approval_requests;
  t workflow_types;
  instance_id uuid;
begin
  for r in select * from approval_requests where workflow_instance_id is null loop
    select * into t from workflow_types
      where association_id=r.association_id and code=r.code and active
      order by version desc limit 1;
    if t.id is null then continue; end if;
    insert into workflow_instances (association_id,workflow_type_id,workflow_version,approval_request_id,
      entity_type,entity_id,title,initiated_by,status)
    values (r.association_id,t.id,t.version,r.id,
      case when r.code in ('W20','W21') then 'flat' else lower(r.category) end,
      coalesce(r.details->>'Flat',r.ref),r.title,r.initiator,'pending')
    returning id into instance_id;
    update approval_requests set workflow_instance_id=instance_id where id=r.id;
    insert into workflow_action_log (workflow_instance_id,actor_id,action,new_value)
      values (instance_id,r.initiator,'submitted',jsonb_build_object('status','pending','ref',r.ref));
    insert into workflow_instance_steps (workflow_instance_id,approval_step_id,step_no,label,role_required,
      alternate_role,assigned_user,action_type,status,completed_at)
    select instance_id,s.id,s.seq,coalesce(s.name,initcap(replace(s.role::text,'_',' ')) || ' approval'),
      s.role,s.alternate_role,s.approver,'approval',s.decision,s.decided_at
    from approval_steps s where s.request_id=r.id order by s.seq;
    insert into workflow_approvals (workflow_instance_id,instance_step_id,approver_id,action,comments,approved_at)
    select instance_id,ws.id,s.decided_by,s.decision,s.comment,coalesce(s.decided_at,now())
    from approval_steps s join workflow_instance_steps ws on ws.approval_step_id=s.id
    where s.request_id=r.id and s.decision <> 'pending' and s.decided_by is not null;
    update workflow_instances set
      status=case
        when exists (select 1 from approval_steps where request_id=r.id and decision='rejected') then 'rejected'
        when exists (select 1 from approval_steps where request_id=r.id and decision='sent_back') then 'sent_back'
        when exists (select 1 from approval_steps where request_id=r.id and decision='pending') then 'pending'
        else 'completed' end,
      current_step=coalesce((select min(seq) from approval_steps where request_id=r.id and decision='pending'),
        (select max(seq) from approval_steps where request_id=r.id),1),
      completed_at=case when not exists (select 1 from approval_steps where request_id=r.id and decision='pending')
        then coalesce((select max(decided_at) from approval_steps where request_id=r.id),now()) else null end
    where id=instance_id;
  end loop;
end $$;

create function link_approval_step_to_workflow() returns trigger
language plpgsql security definer set search_path = public as $$
declare instance_id uuid; step_label text;
begin
  select w.id into instance_id from workflow_instances w where w.approval_request_id=new.request_id;
  if instance_id is null then return new; end if;
  step_label := coalesce(new.name, initcap(replace(new.role::text,'_',' ')) || ' approval');
  insert into workflow_instance_steps (workflow_instance_id,approval_step_id,step_no,label,role_required,
    alternate_role,assigned_user,action_type,status)
  values (instance_id,new.id,new.seq,step_label,new.role,new.alternate_role,new.approver,'approval',new.decision);
  return new;
end $$;
create trigger approval_step_link_workflow after insert on approval_steps
  for each row execute function link_approval_step_to_workflow();

create function record_workflow_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare r approval_requests; instance_id uuid; instance_step uuid; pending_step integer; next_status text;
begin
  if old.decision is not distinct from new.decision or new.decided_by is null then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  instance_id := r.workflow_instance_id;
  if instance_id is null then return new; end if;
  select id into instance_step from workflow_instance_steps where approval_step_id=new.id;
  if instance_step is not null then
    update workflow_instance_steps set status=new.decision,completed_at=coalesce(new.decided_at,now()) where id=instance_step;
    insert into workflow_approvals (workflow_instance_id,instance_step_id,approver_id,action,comments,approved_at)
      values (instance_id,instance_step,new.decided_by,new.decision,new.comment,coalesce(new.decided_at,now()));
  end if;
  if nullif(trim(new.comment),'') is not null then
    insert into workflow_comments (workflow_instance_id,user_id,body) values (instance_id,new.decided_by,new.comment);
  end if;
  insert into workflow_action_log (workflow_instance_id,actor_id,action,old_value,new_value)
    values (instance_id,new.decided_by,'approval_'||new.decision::text,
      jsonb_build_object('step',new.seq,'status',old.decision),jsonb_build_object('step',new.seq,'status',new.decision,'comment',new.comment));
  select min(seq) into pending_step from approval_steps where request_id=new.request_id and decision='pending';
  next_status := case
    when exists (select 1 from approval_steps where request_id=new.request_id and decision='rejected') then 'rejected'
    when exists (select 1 from approval_steps where request_id=new.request_id and decision='sent_back') then 'sent_back'
    when pending_step is not null then 'pending' else 'completed' end;
  update workflow_instances set current_step=coalesce(pending_step,new.seq),status=next_status,
    completed_at=case when next_status='completed' then coalesce(new.decided_at,now()) else null end
    where id=instance_id;
  insert into workflow_notifications (workflow_instance_id,user_id,channel) values (instance_id,r.initiator,'in_app');
  return new;
end $$;
create trigger approval_step_record_workflow after update of decision on approval_steps
  for each row execute function record_workflow_approval();