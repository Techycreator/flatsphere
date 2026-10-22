create table staff_members (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  staff_type text not null check (staff_type in ('housekeeping', 'stp_operator', 'security')),
  area text not null check (length(trim(area)) between 1 and 80),
  active boolean not null default true,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
create index staff_members_association_area_idx on staff_members (association_id, area) where active;
alter table staff_members enable row level security;

create function can_read_staff_area(assoc uuid, staff_area text) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and (
    has_role(assoc, array['admin','president','vice_president','secretary','joint_secretary','caretaker']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and staff_area = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= timezone('Asia/Kolkata', now())::date)
        and (m.monitor_until is null or m.monitor_until >= timezone('Asia/Kolkata', now())::date)
    )
  );
$$;

create policy staff_members_read on staff_members for select using (
  can_read_staff_area(association_id, area)
);

create table staff_private_details (
  staff_id uuid primary key references staff_members(id) on delete cascade,
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  employer_type text not null check (employer_type in ('association', 'agency')),
  agency_name text,
  monthly_salary integer not null check (monthly_salary > 0),
  id_proof_path text not null unique,
  constraint staff_agency_name_check check (
    (employer_type = 'agency' and length(trim(coalesce(agency_name, ''))) > 0)
    or (employer_type = 'association' and agency_name is null)
  ),
  check (id_proof_path like association_id::text || '/%')
);
alter table staff_private_details enable row level security;
create policy staff_private_details_read on staff_private_details for select using (
  association_id = my_association()
  and has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','auditor']::app_role[])
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('staff-proofs', 'staff-proofs', false, 5242880, array['image/jpeg','application/pdf'])
on conflict (id) do nothing;
create policy staff_proofs_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'staff-proofs'
  and (storage.foldername(name))[1] = my_association()::text
  and can_manage_members(my_association())
);
create policy staff_proofs_read on storage.objects for select to authenticated using (
  bucket_id = 'staff-proofs' and exists (
    select 1 from staff_private_details d
    where d.id_proof_path = name and d.association_id = my_association()
      and has_role(d.association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','auditor']::app_role[])
  )
);

create table staff_attendance (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  staff_id uuid not null references staff_members(id) on delete cascade,
  attendance_date date not null default (timezone('Asia/Kolkata', now())::date),
  status text not null check (status in ('present','absent','leave')),
  note text not null default '' check (length(note) <= 240),
  marked_by uuid not null default auth.uid() references profiles(id),
  marked_by_name text not null default my_name(),
  updated_at timestamptz not null default now(),
  unique (staff_id, attendance_date)
);
create index staff_attendance_association_date_idx on staff_attendance (association_id, attendance_date desc);
alter table staff_attendance enable row level security;
create policy staff_attendance_read on staff_attendance for select using (
  association_id = my_association() and exists (
    select 1 from staff_members s
    where s.id = staff_attendance.staff_id and s.association_id = staff_attendance.association_id
      and can_read_staff_area(s.association_id, s.area)
  )
);

create function add_staff_member(
  p_name text,
  p_type text,
  p_area text,
  p_employer_type text,
  p_agency_name text,
  p_monthly_salary integer,
  p_id_proof_path text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  staff_id uuid;
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only an Admin, President or Secretary can add staff';
  end if;
  if coalesce(trim(p_name), '') = '' or length(trim(p_name)) > 120 then
    raise exception 'invalid: enter a staff member name';
  end if;
  if p_type not in ('housekeeping','stp_operator','security') then
    raise exception 'invalid: choose Housekeeping, STP operator, or Security';
  end if;
  if coalesce(trim(p_area), '') = '' or length(trim(p_area)) > 80 then
    raise exception 'invalid: choose an attendance area';
  end if;
  if p_employer_type not in ('association','agency') then raise exception 'invalid: choose who employs this staff member'; end if;
  if p_employer_type = 'agency' and coalesce(trim(p_agency_name), '') = '' then
    raise exception 'invalid: enter the agency name';
  end if;
  if p_monthly_salary is null or p_monthly_salary <= 0 then raise exception 'invalid: enter monthly salary'; end if;
  if p_id_proof_path is null or p_id_proof_path not like a::text || '/%' then
    raise exception 'invalid: upload staff ID proof';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'staff-proofs' and name = p_id_proof_path) then
    raise exception 'invalid: staff ID proof upload not found';
  end if;
  insert into staff_members (association_id, full_name, staff_type, area)
  values (a, trim(p_name), p_type, trim(p_area)) returning id into staff_id;
  insert into staff_private_details (staff_id, association_id, employer_type, agency_name, monthly_salary, id_proof_path)
  values (staff_id, a, p_employer_type, case when p_employer_type = 'agency' then trim(p_agency_name) else null end,
    p_monthly_salary, p_id_proof_path);
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'add_staff_member', 'staff_member', staff_id::text,
    jsonb_build_object(
      'name', trim(p_name), 'type', p_type, 'area', trim(p_area),
      'employer_type', p_employer_type, 'agency_name', p_agency_name, 'monthly_salary', p_monthly_salary
    ));
  return staff_id;
end $$;

create function mark_staff_attendance(p_staff uuid, p_date date, p_status text, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  s staff_members;
  prior staff_attendance;
  who text := my_name();
begin
  if a is null or not has_role(a, array['caretaker']::app_role[]) then
    raise exception 'not_allowed: only the caretaker can mark staff attendance';
  end if;
  if p_date is distinct from timezone('Asia/Kolkata', now())::date then raise exception 'invalid: attendance can only be marked for today'; end if;
  if p_status not in ('present','absent','leave') then raise exception 'invalid: choose a valid attendance status'; end if;
  if length(coalesce(p_note, '')) > 240 then raise exception 'invalid: note must be 240 characters or fewer'; end if;
  select * into s from staff_members where id = p_staff and association_id = a and active for update;
  if s.id is null then raise exception 'not_found: active staff member not found'; end if;
  select * into prior from staff_attendance where staff_id = p_staff and attendance_date = p_date for update;
  insert into staff_attendance (association_id, staff_id, attendance_date, status, note, marked_by, marked_by_name, updated_at)
  values (a, p_staff, p_date, p_status, trim(coalesce(p_note, '')), auth.uid(), who, now())
  on conflict (staff_id, attendance_date) do update set
    status = excluded.status, note = excluded.note, marked_by = excluded.marked_by,
    marked_by_name = excluded.marked_by_name, updated_at = excluded.updated_at;
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (a, auth.uid(), 'mark_staff_attendance', 'staff_attendance', p_staff::text || ':' || p_date::text,
    case when prior.id is null then null else jsonb_build_object('status', prior.status, 'note', prior.note) end,
    jsonb_build_object('status', p_status, 'note', trim(coalesce(p_note, '')), 'staff_name', s.full_name));
end $$;

revoke all on function add_staff_member(text, text, text, text, text, integer, text) from public;
grant execute on function add_staff_member(text, text, text, text, text, integer, text) to authenticated;
revoke all on function mark_staff_attendance(uuid, date, text, text) from public;
grant execute on function mark_staff_attendance(uuid, date, text, text) to authenticated;