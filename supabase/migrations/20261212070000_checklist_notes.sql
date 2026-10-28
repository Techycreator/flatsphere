-- Persist caretaker checklist notes and voice notes (one row per item per day).
create table checklist_notes (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  checklist_date date not null default current_date,
  item_id text not null check (item_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  note text not null default '' check (length(note) <= 500),
  voice_path text,
  updated_by uuid not null default auth.uid() references profiles(id),
  updated_at timestamptz not null default now(),
  unique (association_id, checklist_date, item_id),
  constraint checklist_note_voice_scope check (voice_path is null or voice_path like association_id::text || '/%')
);
alter table checklist_notes enable row level security;
create policy checklist_notes_read on checklist_notes for select using (
  association_id = my_association()
  and has_role(association_id, array['caretaker','secretary','joint_secretary','monitor']::app_role[])
);
create policy checklist_notes_insert on checklist_notes for insert with check (
  association_id = my_association() and updated_by = auth.uid() and checklist_date = current_date
  and has_role(association_id, array['caretaker']::app_role[])
);
create policy checklist_notes_update on checklist_notes for update
  using (association_id = my_association() and checklist_date = current_date
    and has_role(association_id, array['caretaker']::app_role[]))
  with check (association_id = my_association() and updated_by = auth.uid() and checklist_date = current_date
    and has_role(association_id, array['caretaker']::app_role[]));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('checklist-notes', 'checklist-notes', false, 5242880, array['audio/wav','audio/webm','audio/mp4'])
on conflict (id) do nothing;

create policy checklist_notes_storage_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'checklist-notes'
  and (storage.foldername(name))[1] = my_association()::text
  and (storage.foldername(name))[2] = current_date::text
  and has_role(my_association(), array['caretaker']::app_role[])
);
create policy checklist_notes_storage_read on storage.objects for select to authenticated using (
  bucket_id = 'checklist-notes'
  and (storage.foldername(name))[1] = my_association()::text
  and has_role(my_association(), array['caretaker','secretary','joint_secretary','monitor']::app_role[])
);

create function log_checklist_note() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (new.association_id, new.updated_by, 'save', 'checklist_note', new.id::text,
    jsonb_build_object('date', new.checklist_date, 'item', new.item_id, 'voice', new.voice_path is not null));
  return new;
end $$;
create trigger checklist_note_audit after insert or update on checklist_notes
  for each row execute function log_checklist_note();
