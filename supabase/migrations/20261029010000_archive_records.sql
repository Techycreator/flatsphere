create table association_archive (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  entity_type text not null,
  change_action text not null check (change_action in ('created','updated','deleted')),
  entity_id text,
  person_name text,
  flat_number text,
  archived_at timestamptz not null default now(),
  archived_by uuid references profiles(id),
  snapshot jsonb not null
);
create index association_archive_filter_idx on association_archive
  (association_id, archived_at desc, entity_type, flat_number);
create index association_archive_person_idx on association_archive (association_id, lower(person_name));
alter table association_archive enable row level security;
grant select on association_archive to authenticated;
create policy association_archive_read on association_archive for select using (
  association_id = my_association() and has_role(association_id, array['admin','president','secretary']::app_role[])
);

create function archive_row_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  row_data jsonb;
  a uuid;
  flat_id_value uuid;
  flat_label text;
  person_label text;
  record_id text;
begin
  if tg_op = 'UPDATE' and to_jsonb(old) = to_jsonb(new) then return new; end if;
  row_data := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  a := nullif(row_data->>'association_id', '')::uuid;
  flat_id_value := nullif(row_data->>'flat_id', '')::uuid;
  person_label := coalesce(row_data->>'full_name', row_data->>'subject_name', row_data->>'guest_name', row_data->>'name');
  record_id := coalesce(row_data->>'id', row_data->>'user_id', row_data->>'staff_id');
  if tg_table_name = 'flats' then
    flat_id_value := nullif(row_data->>'id', '')::uuid;
    flat_label := row_data->>'number';
  elsif tg_table_name = 'memberships' then
    select p.full_name, f.number into person_label, flat_label
      from profiles p left join flats f on f.id = flat_id_value
      where p.id = nullif(row_data->>'user_id', '')::uuid;
  elsif tg_table_name = 'invites' then
    select number into flat_label from flats where id = flat_id_value;
  elsif tg_table_name = 'flat_housekeeping_workers' then
    select number into flat_label from flats where id = flat_id_value;
  elsif tg_table_name = 'flat_vehicles' then
    select number into flat_label from flats where id = flat_id_value;
  elsif tg_table_name = 'visitor_requests' then
    select number into flat_label from flats where id = flat_id_value;
  elsif tg_table_name = 'id_documents' then
    select number into flat_label from flats where id = flat_id_value;
  elsif tg_table_name = 'staff_attendance' then
    select s.full_name, s.area into person_label, flat_label from staff_members s
      where s.id = nullif(row_data->>'staff_id', '')::uuid;
  elsif tg_table_name = 'staff_members' then
    flat_label := old_row->>'area';
  elsif tg_table_name = 'staff_private_details' then
    select s.full_name, s.area into person_label, flat_label from staff_members s
      where s.id = nullif(old_row->>'staff_id', '')::uuid;
  end if;
  insert into association_archive (
    association_id, entity_type, change_action, entity_id, person_name, flat_number, archived_by, snapshot
  ) values (
    a, tg_argv[0],
    case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    record_id, nullif(person_label, ''), flat_label, auth.uid(), row_data
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

create trigger archive_membership_changes after insert or update or delete on memberships
  for each row execute function archive_row_change('membership');
create trigger archive_invite_changes after insert or update or delete on invites
  for each row execute function archive_row_change('invite');
create trigger archive_flat_changes after insert or update or delete on flats
  for each row execute function archive_row_change('flat');
create trigger archive_staff_changes after insert or update or delete on staff_members
  for each row execute function archive_row_change('staff');
create trigger archive_staff_private_details_changes after insert or update or delete on staff_private_details
  for each row execute function archive_row_change('staff_private_details');
create trigger archive_housekeeping_changes after insert or update or delete on flat_housekeeping_workers
  for each row execute function archive_row_change('household_housekeeping');
create trigger archive_vehicle_changes after insert or update or delete on flat_vehicles
  for each row execute function archive_row_change('vehicle');
create trigger archive_attendance_changes after insert or update or delete on staff_attendance
  for each row execute function archive_row_change('staff_attendance');
create trigger archive_visitor_changes after insert or update or delete on visitor_requests
  for each row execute function archive_row_change('visitor_request');
create trigger archive_id_document_changes after insert or update or delete on id_documents
  for each row execute function archive_row_change('id_document');

create function search_association_archive(
  p_year integer default null,
  p_flat text default null,
  p_person text default null,
  p_entity text default null,
  p_limit integer default 100
) returns setof association_archive
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only an Admin, President or Secretary can search archived records';
  end if;
  return query
    select ar.* from association_archive ar
    where ar.association_id = a
      and (p_year is null or extract(year from ar.archived_at)::integer = p_year)
      and (nullif(trim(p_flat), '') is null or ar.flat_number ilike '%' || trim(p_flat) || '%')
      and (nullif(trim(p_person), '') is null or ar.person_name ilike '%' || trim(p_person) || '%')
      and (nullif(trim(p_entity), '') is null or ar.entity_type = p_entity)
    order by ar.archived_at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 250);
end $$;
revoke all on function search_association_archive(integer, text, text, text, integer) from public;
grant execute on function search_association_archive(integer, text, text, text, integer) to authenticated;