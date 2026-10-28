create table checklist_proofs (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  checklist_date date not null default current_date,
  item_id text not null check (item_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  storage_path text not null unique,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  uploaded_by_name text not null default my_name(),
  created_at timestamptz not null default now(),
  constraint checklist_proof_path_scope check (storage_path like association_id::text || '/%')
);
create index checklist_proofs_item_date_idx on checklist_proofs (association_id, checklist_date, item_id);
alter table checklist_proofs enable row level security;
create policy checklist_proofs_read on checklist_proofs for select using (
  association_id = my_association()
  and has_role(association_id, array['caretaker','secretary','joint_secretary','monitor']::app_role[])
);
create policy checklist_proofs_insert on checklist_proofs for insert with check (
  association_id = my_association() and uploaded_by = auth.uid()
  and checklist_date = current_date
  and has_role(association_id, array['caretaker']::app_role[])
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('checklist-proofs', 'checklist-proofs', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create policy checklist_proofs_storage_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'checklist-proofs'
  and (storage.foldername(name))[1] = my_association()::text
  and (storage.foldername(name))[2] = current_date::text
  and has_role(my_association(), array['caretaker']::app_role[])
);
create policy checklist_proofs_storage_read on storage.objects for select to authenticated using (
  bucket_id = 'checklist-proofs'
  and exists (
    select 1 from checklist_proofs p
    where p.storage_path = name and p.association_id = my_association()
      and has_role(p.association_id, array['caretaker','secretary','joint_secretary','monitor']::app_role[])
  )
);

create function log_checklist_proof_upload() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (new.association_id, new.uploaded_by, 'upload', 'checklist_proof', new.id::text,
    jsonb_build_object('date', new.checklist_date, 'item', new.item_id));
  return new;
end $$;
create trigger checklist_proof_upload_audit after insert on checklist_proofs
  for each row execute function log_checklist_proof_upload();