-- Flats & people admin (Secretary / President / Joint Secretary / Membership desk) and private ID proofs.
alter table invites add column mobile text;

create function can_manage_members(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role(assoc, array['admin','president','secretary','joint_secretary']::app_role[])
    or exists (select 1 from memberships m where m.association_id = assoc and m.user_id = auth.uid()
               and m.ended_at is null and m.role in ('ec_member','monitor') and 'Membership desk' = any(m.designations));
$$;

create function owns_flat(fid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m where m.user_id = auth.uid() and m.ended_at is null
                 and m.role = 'owner' and m.flat_id::text = fid);
$$;

create policy flats_admin_insert on flats for insert with check (can_manage_members(association_id));
create policy flats_admin_update on flats for update using (can_manage_members(association_id))
  with check (can_manage_members(association_id));

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare n text; mob text;
begin
  select full_name, mobile into n, mob from invites
    where lower(email) = lower(new.email) and claimed_at is null order by mobile nulls last limit 1;
  if n is null then raise exception 'not_invited: this email has not been invited by an association'; end if;
  if exists (select 1 from profiles where mobile = mob) then mob := null; end if;
  insert into profiles (id, full_name, email, mobile) values (new.id, n, new.email, mob);
  insert into memberships (association_id, user_id, role, flat_id, designations, monitor_categories)
    select association_id, new.id, role, flat_id, designations, monitor_categories
    from invites where lower(email) = lower(new.email) and claimed_at is null;
  update invites set claimed_at = now() where lower(email) = lower(new.email) and claimed_at is null;
  return new;
end $$;

-- Active members plus pending invites of the caller's association (managers only).
create function directory()
returns table (kind text, id uuid, full_name text, email text, mobile text, role app_role, flat_number text,
               designations text[], since timestamptz)
language sql stable security definer set search_path = public as $$
  select 'member', m.id, p.full_name, p.email, p.mobile, m.role, f.number, m.designations, m.started_at
  from memberships m join profiles p on p.id = m.user_id left join flats f on f.id = m.flat_id
  where m.association_id = my_association() and m.ended_at is null and can_manage_members(m.association_id)
  union all
  select 'invited', i.id, i.full_name, i.email, i.mobile, i.role, f.number, i.designations, i.created_at
  from invites i left join flats f on f.id = i.flat_id
  where i.association_id = my_association() and i.claimed_at is null and can_manage_members(i.association_id)
$$;

-- Existing account: role added at once. New email: invited (can log in with an email code).
create function add_member(p_full_name text, p_email text, p_mobile text, p_role app_role, p_flat text,
                           p_designations text[] default '{}')
returns text language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); fid uuid; uid uuid; e text := lower(trim(p_email)); res text;
begin
  if a is null or not can_manage_members(a) then raise exception 'not_allowed'; end if;
  if p_role not in ('owner','resident')
     and not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
    raise exception 'not_allowed: only the President or Secretary can assign committee or staff roles';
  end if;
  if coalesce(trim(p_full_name), '') = '' or e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid: name and a valid email are required';
  end if;
  if p_role in ('owner','resident') then
    select id into fid from flats where association_id = a and number = p_flat;
    if fid is null then raise exception 'invalid: choose a flat for an owner or resident'; end if;
  end if;
  select id into uid from profiles where lower(email) = e;
  if uid is not null then
    if exists (select 1 from memberships where association_id = a and user_id = uid and role = p_role
               and flat_id is not distinct from fid and ended_at is null) then
      raise exception 'duplicate: this person already has that role';
    end if;
    insert into memberships (association_id, user_id, role, flat_id, designations)
      values (a, uid, p_role, fid, coalesce(p_designations, '{}'));
    res := 'member';
  else
    if exists (select 1 from invites where association_id = a and lower(email) = e and role = p_role
               and flat_id is not distinct from fid and claimed_at is null) then
      raise exception 'duplicate: this person is already invited with that role';
    end if;
    insert into invites (association_id, email, full_name, mobile, role, flat_id, designations, invited_by)
      values (a, e, trim(p_full_name), nullif(trim(p_mobile), ''), p_role, fid, coalesce(p_designations, '{}'), auth.uid());
    res := 'invited';
  end if;
  if p_role = 'resident' then
    update flats set occupancy = 'rented' where id = fid and occupancy = 'vacant';
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'add_member', 'membership', e,
            jsonb_build_object('role', p_role, 'flat', p_flat, 'result', res));
  return res;
end $$;

-- Disables access immediately (membership ended) or withdraws an unclaimed invite; ID proofs are archived.
create function remove_member(p_kind text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); m memberships; i invites; e text;
begin
  if a is null or not can_manage_members(a) then raise exception 'not_allowed'; end if;
  if p_kind = 'member' then
    select * into m from memberships where id = p_id and association_id = a and ended_at is null;
    if m.id is null then raise exception 'not_found'; end if;
    if m.user_id = auth.uid() then raise exception 'not_allowed: you cannot remove your own role'; end if;
    if m.role not in ('owner','resident')
       and not has_role(a, array['admin','president','secretary','joint_secretary']::app_role[]) then
      raise exception 'not_allowed: only the President or Secretary can remove committee or staff roles';
    end if;
    update memberships set ended_at = now() where id = m.id;
    select email into e from profiles where id = m.user_id;
    if m.flat_id is not null then
      update id_documents set archived_at = now()
        where association_id = a and lower(subject_email) = lower(e) and flat_id = m.flat_id and archived_at is null;
    end if;
  else
    select * into i from invites where id = p_id and association_id = a and claimed_at is null;
    if i.id is null then raise exception 'not_found'; end if;
    delete from invites where id = i.id;
    e := i.email;
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, auth.uid(), 'remove_member', p_kind, p_id::text, jsonb_build_object('email', e));
end $$;

create table id_documents (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  subject_email text not null,
  subject_name text not null,
  flat_id uuid references flats(id),
  doc_type text not null,
  number_last4 text check (number_last4 ~ '^[0-9A-Za-z]{0,4}$'),
  storage_path text not null unique,
  uploaded_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create index on id_documents (association_id, lower(subject_email));
alter table id_documents enable row level security;

create policy id_docs_read on id_documents for select using (
  is_member(association_id) and (
    can_manage_members(association_id) or owns_flat(flat_id::text) or lower(subject_email) = lower(auth.email())));
create policy id_docs_insert on id_documents for insert with check (
  uploaded_by = auth.uid() and is_member(association_id)
  and (can_manage_members(association_id) or owns_flat(flat_id::text)));
create policy id_docs_archive on id_documents for update using (can_manage_members(association_id))
  with check (can_manage_members(association_id));

create function log_id_view(doc uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare d id_documents;
begin
  select * into d from id_documents where id = doc;  -- RLS: only viewers allowed to see it
  if d.id is null then raise exception 'not_found'; end if;
  insert into audit_log (association_id, actor, action, entity, entity_id)
    values (d.association_id, auth.uid(), 'view', 'id_document', doc::text);
end $$;
create policy audit_insert_view on audit_log for insert with check (actor = auth.uid() and action = 'view');

-- Private bucket; object path = <association>/<flat id or none>/<uuid>.<ext>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('id-proofs', 'id-proofs', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

create policy id_proofs_read on storage.objects for select to authenticated using (
  bucket_id = 'id-proofs' and exists (select 1 from id_documents d where d.storage_path = name));
create policy id_proofs_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'id-proofs' and (storage.foldername(name))[1] = my_association()::text
  and (can_manage_members(my_association()) or owns_flat((storage.foldername(name))[2])));
