create table association_documents (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  document_type text not null check (document_type in (
    'sale_deed','building_plan','completion_certificate','occupancy_certificate','encumbrance_certificate',
    'noc','property_insurance','corpus_transfer','maintenance_agreement','other'
  )),
  title text not null check (length(trim(title)) between 1 and 160),
  storage_path text not null unique,
  issue_date date,
  expiry_date date,
  version integer not null default 1 check (version > 0),
  archived_at timestamptz,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
create index association_documents_type_version_idx on association_documents (association_id,document_type,version desc);
alter table association_documents enable row level security;
create policy association_documents_read on association_documents for select using (
  association_id=my_association() and is_member(association_id)
  and (archived_at is null or can_manage_members(association_id))
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('association-documents','association-documents',false,5242880,array['image/jpeg','application/pdf'])
on conflict (id) do nothing;
create policy association_documents_storage_upload on storage.objects for insert to authenticated with check (
  bucket_id='association-documents'
  and (storage.foldername(name))[1]=my_association()::text
  and can_manage_members(my_association())
);
create policy association_documents_storage_read on storage.objects for select to authenticated using (
  bucket_id='association-documents' and exists (
    select 1 from association_documents d where d.storage_path=name and d.association_id=my_association()
      and (d.archived_at is null or can_manage_members(d.association_id))
  )
);

create function add_association_document(
  p_type text,p_title text,p_storage_path text,p_issue_date date default null,p_expiry_date date default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  next_version integer;
  document_id uuid;
begin
  if a is null or not can_manage_members(a) then raise exception 'not_allowed: President or Secretary access required'; end if;
  if p_type not in ('sale_deed','building_plan','completion_certificate','occupancy_certificate','encumbrance_certificate',
    'noc','property_insurance','corpus_transfer','maintenance_agreement','other') then
    raise exception 'invalid: unsupported document type';
  end if;
  if coalesce(trim(p_title),'')='' or length(trim(p_title))>160 then raise exception 'invalid: document title is required'; end if;
  if p_expiry_date is not null and p_issue_date is not null and p_expiry_date<p_issue_date then
    raise exception 'invalid: expiry date cannot precede issue date';
  end if;
  if p_storage_path not like a::text||'/%' or not exists (
    select 1 from storage.objects where bucket_id='association-documents' and name=p_storage_path
  ) then raise exception 'invalid: upload the document to this association first'; end if;
  select coalesce(max(version),0)+1 into next_version from association_documents
    where association_id=a and document_type=p_type and archived_at is null;
  update association_documents set archived_at=now()
    where association_id=a and document_type=p_type and archived_at is null;
  insert into association_documents (association_id,document_type,title,storage_path,issue_date,expiry_date,version)
  values (a,p_type,trim(p_title),p_storage_path,p_issue_date,p_expiry_date,next_version)
  returning id into document_id;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
  values (a,auth.uid(),'publish_association_document','association_document',document_id::text,
    jsonb_build_object('type',p_type,'title',trim(p_title),'version',next_version));
  return document_id;
end $$;
revoke all on function add_association_document(text,text,text,date,date) from public;
grant execute on function add_association_document(text,text,text,date,date) to authenticated;

create function log_association_document_view(p_document uuid) returns void
language plpgsql security definer set search_path=public as $$
declare d association_documents;
begin
  select * into d from association_documents where id=p_document and association_id=my_association()
    and (archived_at is null or can_manage_members(association_id));
  if d.id is null or not is_member(d.association_id) then raise exception 'not_found'; end if;
  insert into audit_log (association_id,actor,action,entity,entity_id)
  values (d.association_id,auth.uid(),'view','association_document',d.id::text);
end $$;