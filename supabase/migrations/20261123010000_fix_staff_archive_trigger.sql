create or replace function archive_row_change() returns trigger
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
    flat_label := row_data->>'area';
  elsif tg_table_name = 'staff_private_details' then
    select s.full_name, s.area into person_label, flat_label from staff_members s
      where s.id = nullif(row_data->>'staff_id', '')::uuid;
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