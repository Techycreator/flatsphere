-- Offboarding: retire a flat, and close an association. Records are kept (archived), never deleted.
alter table flats add column retired_at timestamptz;
alter table associations add column closed_at timestamptz;

create or replace function retire_flat(p_flat uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  f flats;
  outstanding bigint;
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the Admin, President or Secretary can retire a flat';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'invalid: enter a reason of 3 to 300 characters';
  end if;
  select * into f from flats where id = p_flat and association_id = a for update;
  if f.id is null then raise exception 'not_found: flat not found'; end if;
  if f.retired_at is not null then raise exception 'invalid: flat is already retired'; end if;
  if exists (select 1 from memberships where flat_id = f.id and ended_at is null) then
    raise exception 'invalid: remove or transfer the flat''s owner and residents first';
  end if;
  if exists (select 1 from approval_requests r join membership_changes c on c.request_id = r.id
             where c.flat_id = f.id and r.status = 'pending') then
    raise exception 'invalid: finish the pending owner or resident change for this flat first';
  end if;
  select coalesce(sum(greatest(d.amount - coalesce(p.paid, 0), 0)), 0)::bigint into outstanding
  from dues d
  left join lateral (select sum(pay.amount)::bigint as paid from payments pay where pay.due_id = d.id and pay.flat_id = d.flat_id) p on true
  where d.flat_id = f.id;
  if outstanding > 0 then raise exception 'invalid: settle outstanding dues of % before retiring the flat', outstanding; end if;
  update flats set retired_at = now() where id = f.id;
  delete from flat_vehicles where flat_id = f.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'retire_flat', 'flat', f.id::text, jsonb_build_object('number', f.number, 'reason', trim(p_reason)));
end $$;
revoke all on function retire_flat(uuid, text) from public, anon;
grant execute on function retire_flat(uuid, text) to authenticated;

-- Closing an association ends every membership (so nobody can sign in to it) and stamps closed_at.
-- Data stays in the database for retention and audit; export it first.
create or replace function offboard_association(p_confirm_name text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  assoc associations;
  ended integer;
begin
  if a is null or not has_role(a, array['admin']::app_role[]) then
    raise exception 'not_allowed: only the Admin can offboard an association';
  end if;
  select * into assoc from associations where id = a for update;
  if assoc.closed_at is not null then raise exception 'invalid: association is already closed'; end if;
  if lower(trim(coalesce(p_confirm_name, ''))) <> lower(assoc.name) then
    raise exception 'invalid: type the association name exactly to confirm';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'invalid: enter a reason of 3 to 300 characters';
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'offboard_association', 'association', a::text,
    jsonb_build_object('name', assoc.name, 'reason', trim(p_reason)));
  update associations set closed_at = now() where id = a;
  update memberships set ended_at = now() where association_id = a and ended_at is null;
  get diagnostics ended = row_count;
  delete from invites where association_id = a and claimed_at is null;
end $$;
revoke all on function offboard_association(text, text) from public, anon;
grant execute on function offboard_association(text, text) to authenticated;

-- remove_member: Admin may also offboard, and the last President/Secretary/Admin cannot be removed.
create or replace function remove_member(p_kind text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); m memberships; i invites; e text;
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only the Admin, President or Secretary can remove a member';
  end if;
  if p_kind = 'member' then
    select * into m from memberships where id = p_id and association_id = a and ended_at is null;
    if m.id is null then raise exception 'not_found'; end if;
    if m.user_id = auth.uid() then raise exception 'not_allowed: you cannot remove your own role'; end if;
    if m.role in ('president','secretary','admin') and not exists (
      select 1 from memberships o where o.association_id = a and o.role = m.role and o.ended_at is null and o.id <> m.id) then
      raise exception 'invalid: appoint another % before removing the only one', m.role;
    end if;
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
