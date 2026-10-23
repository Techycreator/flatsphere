create table association_vendors (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  service_category text not null check (length(trim(service_category)) between 1 and 80),
  contact_name text not null default '',
  phone text not null default '',
  email text not null default '',
  address text not null default '',
  security_deposit numeric(12,2) not null default 0 check (security_deposit >= 0),
  escalation_contacts jsonb not null default '[]'::jsonb check (jsonb_typeof(escalation_contacts) = 'array'),
  active boolean not null default true,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (association_id, id)
);
create index association_vendors_category_idx on association_vendors (association_id, service_category, name);

create table vendor_amc_contracts (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  vendor_id uuid not null,
  service_name text not null check (length(trim(service_name)) between 1 and 160),
  start_date date not null,
  end_date date not null check (end_date >= start_date),
  annual_cost numeric(12,2) check (annual_cost is null or annual_cost >= 0),
  renewal_notice_days smallint not null default 90 check (renewal_notice_days between 1 and 365),
  active boolean not null default true,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (association_id, vendor_id) references association_vendors(association_id, id) on delete cascade,
  unique (association_id, id),
  unique (association_id, vendor_id, id)
);
create index vendor_amc_expiry_idx on vendor_amc_contracts (association_id, end_date)
  where active;

create table vendor_contract_documents (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  vendor_id uuid not null,
  contract_id uuid,
  document_type text not null check (document_type in ('contract', 'insurance')),
  title text not null check (length(trim(title)) between 1 and 160),
  storage_path text not null unique,
  expires_on date,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  foreign key (association_id, vendor_id) references association_vendors(association_id, id) on delete cascade,
  foreign key (association_id, vendor_id, contract_id)
    references vendor_amc_contracts(association_id, vendor_id, id) on delete cascade
);
create index vendor_contract_documents_vendor_idx on vendor_contract_documents (association_id, vendor_id, created_at desc);

alter table complaints add column vendor_id uuid;
alter table complaints add constraint complaints_vendor_association_fk
  foreign key (association_id, vendor_id) references association_vendors(association_id, id) on delete set null (vendor_id);
create index complaints_vendor_idx on complaints (vendor_id) where vendor_id is not null;

alter table association_vendors enable row level security;
alter table vendor_amc_contracts enable row level security;
alter table vendor_contract_documents enable row level security;

create policy association_vendors_read on association_vendors for select using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','auditor']::app_role[])
);
create policy association_vendors_manage on association_vendors for all using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary']::app_role[])
) with check (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary']::app_role[])
);
create policy vendor_amc_read on vendor_amc_contracts for select using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','auditor']::app_role[])
);
create policy vendor_amc_manage on vendor_amc_contracts for all using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary']::app_role[])
) with check (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary']::app_role[])
);
create policy vendor_documents_read on vendor_contract_documents for select using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary','auditor']::app_role[])
);
create policy vendor_documents_manage on vendor_contract_documents for all using (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary']::app_role[])
) with check (
  association_id = my_association()
  and has_role(association_id,array['admin','president','secretary']::app_role[])
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('vendor-contracts','vendor-contracts',false,5242880,array['image/jpeg','application/pdf'])
on conflict (id) do nothing;
create policy vendor_contract_storage_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'vendor-contracts'
  and (storage.foldername(name))[1] = my_association()::text
  and has_role(my_association(),array['admin','president','secretary']::app_role[])
);
create policy vendor_contract_storage_read on storage.objects for select to authenticated using (
  bucket_id = 'vendor-contracts'
  and exists (
    select 1 from vendor_contract_documents d
    where d.storage_path = name and d.association_id = my_association()
      and has_role(d.association_id,array['admin','president','secretary','auditor']::app_role[])
  )
);

create function register_vendor_document(
  p_vendor uuid, p_contract uuid, p_type text, p_title text, p_storage_path text, p_expires_on date default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  document_id uuid;
begin
  if a is null or not has_role(a,array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: Admin, President, or Secretary access required';
  end if;
  if p_type not in ('contract','insurance') then raise exception 'invalid: unsupported document type'; end if;
  if coalesce(trim(p_title),'') = '' or length(trim(p_title)) > 160 then raise exception 'invalid: document title is required'; end if;
  if not exists (select 1 from association_vendors where id=p_vendor and association_id=a) then
    raise exception 'not_found: vendor not found';
  end if;
  if p_contract is not null and not exists (
    select 1 from vendor_amc_contracts where id=p_contract and vendor_id=p_vendor and association_id=a
  ) then raise exception 'invalid: contract does not belong to this vendor'; end if;
  if p_storage_path not like a::text||'/%' or not exists (
    select 1 from storage.objects where bucket_id='vendor-contracts' and name=p_storage_path
  ) then raise exception 'invalid: upload the document to this association first'; end if;
  insert into vendor_contract_documents (association_id,vendor_id,contract_id,document_type,title,storage_path,expires_on)
  values (a,p_vendor,p_contract,p_type,trim(p_title),p_storage_path,p_expires_on)
  returning id into document_id;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
  values (a,auth.uid(),'publish_vendor_document','vendor_contract_document',document_id::text,
    jsonb_build_object('vendor_id',p_vendor,'contract_id',p_contract,'type',p_type,'title',trim(p_title)));
  return document_id;
end $$;
revoke all on function register_vendor_document(uuid,uuid,text,text,text,date) from public;
grant execute on function register_vendor_document(uuid,uuid,text,text,text,date) to authenticated;

create function log_vendor_document_view(p_document uuid) returns text
language plpgsql security definer set search_path=public as $$
declare d vendor_contract_documents;
begin
  select * into d from vendor_contract_documents
  where id=p_document and association_id=my_association()
    and has_role(association_id,array['admin','president','secretary','auditor']::app_role[]);
  if d.id is null then raise exception 'not_found'; end if;
  insert into audit_log (association_id,actor,action,entity,entity_id)
  values (d.association_id,auth.uid(),'view','vendor_contract_document',d.id::text);
  return d.storage_path;
end $$;
revoke all on function log_vendor_document_view(uuid) from public;
grant execute on function log_vendor_document_view(uuid) to authenticated;

create function notify_vendor_amc_renewals() returns void
language plpgsql security definer set search_path=public as $$
begin
  insert into app_notifications (association_id,user_id,event_key,title,body,action_path)
  select c.association_id,m.user_id,'vendor-amc-renewal:'||c.id::text||':'||c.end_date::text,
    'AMC renewal due',v.name||' · '||c.service_name||' expires '||to_char(c.end_date,'DD Mon YYYY'),'/registers'
  from vendor_amc_contracts c
  join association_vendors v on v.id=c.vendor_id and v.association_id=c.association_id
  join memberships m on m.association_id=c.association_id and m.ended_at is null and m.role='secretary'
  where c.active and v.active and c.end_date between current_date and current_date+c.renewal_notice_days
  on conflict (association_id,user_id,event_key) do nothing;
end $$;
revoke all on function notify_vendor_amc_renewals() from public;

do $$
begin
  if exists (select 1 from pg_extension where extname='pg_cron') then
    execute $schedule$
      select cron.schedule(
        'flatsphere-vendor-amc-renewal-reminders',
        '0 8 * * *',
        'select public.notify_vendor_amc_renewals()'
      )
    $schedule$;
  end if;
end $$;
