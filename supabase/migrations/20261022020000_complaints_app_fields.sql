-- Fields the app shows directly, plus defaults so clients never pick association or author themselves.
create function my_association() returns uuid
language sql stable security definer set search_path = public as $$
  select association_id from memberships where user_id = auth.uid() and ended_at is null order by started_at limit 1;
$$;

alter table complaints
  alter column association_id set default my_association(),
  alter column raised_by set default auth.uid(),
  add column ticket_type text not null default 'complaint',
  add column flat_number text,
  add column raised_by_name text,
  add column assignee_name text,
  add column photo_count int not null default 0,
  add column has_voice_note boolean not null default false;

alter table complaint_remarks
  alter column author set default auth.uid(),
  add column author_name text;

drop policy remarks_insert on complaint_remarks;
create policy remarks_insert on complaint_remarks for insert with check (
  author = auth.uid() and exists (select 1 from complaints c where c.id = complaint_id));
