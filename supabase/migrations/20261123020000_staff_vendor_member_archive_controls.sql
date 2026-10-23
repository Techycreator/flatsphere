create or replace function remove_member(p_kind text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); m memberships; i invites; e text;
begin
  if a is null or not has_role(a, array['president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can remove a member';
  end if;
  if p_kind = 'member' then
    select * into m from memberships where id = p_id and association_id = a and ended_at is null;
    if m.id is null then raise exception 'not_found'; end if;
    if m.user_id = auth.uid() then raise exception 'not_allowed: you cannot remove your own role'; end if;
    update memberships set ended_at = now() where id = m.id;
    select email into e from profiles where id = m.user_id;
    if m.flat_id is not null then
      update id_documents set archived_at = now()
        where association_id = a and lower(subject_email) = lower(e) and flat_id = m.flat_id and archived_at is null;
    end if;
  elsif p_kind = 'invited' then
    select * into i from invites where id = p_id and association_id = a and claimed_at is null;
    if i.id is null then raise exception 'not_found'; end if;
    delete from invites where id = i.id;
    e := i.email;
  else
    raise exception 'invalid: unsupported member record';
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'remove_member', p_kind, p_id::text, jsonb_build_object('email', e));
end $$;

create or replace function set_member_details(p_kind text, p_id uuid, p_designations text[], p_monitor_categories text[],
                                               p_from date default null, p_until date default null)
returns void language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); who text;
begin
  if a is null or not has_role(a, array['president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can change member details';
  end if;
  if p_until is not null and p_from is not null and p_until < p_from then
    raise exception 'invalid: the end date must be after the start date';
  end if;
  who := assigner_label(a);
  if p_kind = 'member' then
    update memberships set designations = coalesce(p_designations, '{}'),
      monitor_categories = coalesce(p_monitor_categories, '{}'), monitor_from = p_from, monitor_until = p_until,
      assigned_by = case when cardinality(coalesce(p_monitor_categories, '{}')) > 0 then who end
      where id = p_id and association_id = a and ended_at is null;
  elsif p_kind = 'invited' then
    update invites set designations = coalesce(p_designations, '{}'),
      monitor_categories = coalesce(p_monitor_categories, '{}'), monitor_from = p_from, monitor_until = p_until,
      assigned_by = case when cardinality(coalesce(p_monitor_categories, '{}')) > 0 then who end
      where id = p_id and association_id = a and claimed_at is null;
  else
    raise exception 'invalid: unsupported member record';
  end if;
  if not found then raise exception 'not_found'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'set_member_details', p_kind, p_id::text,
            jsonb_build_object('designations', p_designations, 'monitor_categories', p_monitor_categories,
                               'from', p_from, 'until', p_until));
end $$;

create or replace function set_member_birth_date(p_kind text, p_id uuid, p_birth_date date) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); member_role app_role;
begin
  if a is null or not has_role(a, array['president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can change a member date of birth';
  end if;
  if p_birth_date > current_date then raise exception 'invalid: date of birth cannot be in the future'; end if;
  if p_kind = 'member' then
    update memberships set date_of_birth = p_birth_date
    where id = p_id and association_id = a and ended_at is null and role in ('owner','resident')
    returning role into member_role;
  elsif p_kind = 'invited' then
    update invites set date_of_birth = p_birth_date
    where id = p_id and association_id = a and claimed_at is null and role in ('owner','resident')
    returning role into member_role;
  else
    raise exception 'invalid: unsupported member record';
  end if;
  if member_role is null then raise exception 'not_found: active owner/resident record not found'; end if;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
  values (a,auth.uid(),'set_member_birth_date','membership',p_id::text,jsonb_build_object('date_of_birth',p_birth_date));
end $$;

create function update_staff_member(
  p_staff uuid, p_name text, p_type text, p_area text, p_employer_type text,
  p_agency_name text, p_monthly_salary integer, p_active boolean
) returns void language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); s staff_members;
begin
  if a is null or not has_role(a, array['president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can edit staff';
  end if;
  if coalesce(trim(p_name), '') = '' or length(trim(p_name)) > 120 then raise exception 'invalid: enter a staff member name'; end if;
  if p_type not in ('housekeeping','stp_operator','security') then raise exception 'invalid: choose a staff type'; end if;
  if coalesce(trim(p_area), '') = '' or length(trim(p_area)) > 80 then raise exception 'invalid: choose an attendance area'; end if;
  if p_employer_type not in ('association','agency') then raise exception 'invalid: choose who employs this staff member'; end if;
  if p_employer_type = 'agency' and coalesce(trim(p_agency_name), '') = '' then raise exception 'invalid: enter the agency name'; end if;
  if p_monthly_salary is null or p_monthly_salary <= 0 then raise exception 'invalid: enter monthly salary'; end if;
  select * into s from staff_members where id = p_staff and association_id = a for update;
  if s.id is null then raise exception 'not_found: staff member not found'; end if;
  update staff_members set full_name = trim(p_name), staff_type = p_type, area = trim(p_area), active = p_active
    where id = p_staff and association_id = a;
  update staff_private_details set employer_type = p_employer_type,
    agency_name = case when p_employer_type = 'agency' then trim(p_agency_name) else null end,
    monthly_salary = p_monthly_salary
    where staff_id = p_staff and association_id = a;
  if not found then raise exception 'not_found: staff details not found'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
    values (a, auth.uid(), case when p_active then 'update_staff_member' else 'archive_staff_member' end,
      'staff_member', p_staff::text,
      jsonb_build_object('name', s.full_name, 'type', s.staff_type, 'area', s.area, 'active', s.active),
      jsonb_build_object('name', trim(p_name), 'type', p_type, 'area', trim(p_area), 'active', p_active,
        'employer_type', p_employer_type, 'agency_name', p_agency_name, 'monthly_salary', p_monthly_salary));
end $$;
revoke all on function update_staff_member(uuid,text,text,text,text,text,integer,boolean) from public;
grant execute on function update_staff_member(uuid,text,text,text,text,text,integer,boolean) to authenticated;

drop policy association_vendors_manage on association_vendors;
create policy association_vendors_insert on association_vendors for insert with check (
  association_id = my_association() and has_role(association_id,array['admin','president','secretary']::app_role[])
);
create policy association_vendors_update on association_vendors for update using (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
) with check (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
);
create policy association_vendors_delete on association_vendors for delete using (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
);

drop policy vendor_amc_manage on vendor_amc_contracts;
create policy vendor_amc_insert on vendor_amc_contracts for insert with check (
  association_id = my_association() and has_role(association_id,array['admin','president','secretary']::app_role[])
);
create policy vendor_amc_update on vendor_amc_contracts for update using (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
) with check (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
);
create policy vendor_amc_delete on vendor_amc_contracts for delete using (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
);

drop policy vendor_documents_manage on vendor_contract_documents;
create policy vendor_documents_insert on vendor_contract_documents for insert with check (
  association_id = my_association() and has_role(association_id,array['admin','president','secretary']::app_role[])
);
create policy vendor_documents_update on vendor_contract_documents for update using (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
) with check (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
);
create policy vendor_documents_delete on vendor_contract_documents for delete using (
  association_id = my_association() and has_role(association_id,array['president','secretary']::app_role[])
);

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
  row_data := case when tg_op = 'INSERT' then to_jsonb(new) else to_jsonb(old) end;
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
  elsif tg_table_name = 'association_vendors' then
    person_label := row_data->>'name';
  elsif tg_table_name = 'vendor_amc_contracts' then
    select coalesce(v.name, row_data->>'vendor_id') || ' · ' || coalesce(row_data->>'service_name', 'AMC')
      into person_label from association_vendors v
      where v.id = nullif(row_data->>'vendor_id', '')::uuid;
    person_label := coalesce(person_label, row_data->>'service_name');
  elsif tg_table_name = 'association_documents' then
    person_label := row_data->>'title';
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

drop trigger if exists archive_invite_changes on invites;
drop trigger if exists archive_flat_changes on flats;
drop trigger if exists archive_vehicle_changes on flat_vehicles;
drop trigger if exists archive_attendance_changes on staff_attendance;
drop trigger if exists archive_visitor_changes on visitor_requests;
drop trigger if exists archive_id_document_changes on id_documents;

create trigger archive_vendor_changes after update or delete on association_vendors
  for each row execute function archive_row_change('vendor');
create trigger archive_vendor_amc_changes after update or delete on vendor_amc_contracts
  for each row execute function archive_row_change('vendor_amc_contract');
create trigger archive_prior_association_documents after update of archived_at on association_documents
  for each row when (old.archived_at is null and new.archived_at is not null)
  execute function archive_row_change('association_document');

create or replace function notify_vendor_amc_renewals() returns void
language plpgsql security definer set search_path = public as $$
begin
  update vendor_amc_contracts set active = false
  where active and end_date < current_date;

  insert into app_notifications (association_id,user_id,event_key,title,body,action_path)
  select c.association_id,m.user_id,'vendor-amc-renewal:'||c.id::text||':'||c.end_date::text,
    'AMC renewal due',v.name||' · '||c.service_name||' expires '||to_char(c.end_date,'DD Mon YYYY'),'/registers'
  from vendor_amc_contracts c
  join association_vendors v on v.id=c.vendor_id and v.association_id=c.association_id
  join memberships m on m.association_id=c.association_id and m.ended_at is null and m.role='secretary'
  where c.active and v.active and c.end_date between current_date and current_date+c.renewal_notice_days
  on conflict (association_id,user_id,event_key) do nothing;
end $$;