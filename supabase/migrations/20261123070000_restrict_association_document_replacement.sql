create or replace function add_association_document(
  p_type text,p_title text,p_storage_path text,p_issue_date date default null,p_expiry_date date default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  next_version integer;
  document_id uuid;
begin
  if a is null or not has_role(a,array['president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can replace association documents';
  end if;
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
