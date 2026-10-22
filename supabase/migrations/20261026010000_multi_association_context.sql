-- Persist each signed-in user's current tenant; never infer it from the oldest membership.
create table user_association_context (
  user_id uuid not null references profiles(id) on delete cascade,
  session_id uuid not null,
  association_id uuid not null references associations(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id)
);
alter table user_association_context enable row level security;
create policy association_context_read_self on user_association_context
  for select using (user_id = auth.uid());

create or replace function set_active_association(assoc uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or nullif(auth.jwt()->>'session_id', '') is null then
    raise exception 'not_allowed: authenticated session required';
  end if;
  if assoc is null or not exists (
    select 1 from memberships
    where association_id = assoc and user_id = auth.uid() and ended_at is null
  ) then
    raise exception 'not_allowed: you are not an active member of this association';
  end if;
  insert into user_association_context (user_id, session_id, association_id, updated_at)
  values (auth.uid(), (auth.jwt()->>'session_id')::uuid, assoc, now())
  on conflict (user_id, session_id) do update
    set association_id = excluded.association_id, updated_at = excluded.updated_at;
end $$;

create or replace function my_association() returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (
      select c.association_id from user_association_context c
      where c.user_id = auth.uid() and c.session_id = (auth.jwt()->>'session_id')::uuid
        and exists (
          select 1 from memberships m
          where m.user_id = auth.uid() and m.association_id = c.association_id and m.ended_at is null
        )
    ),
    (
      select min(m.association_id::text)::uuid from memberships m
      where m.user_id = auth.uid() and m.ended_at is null
      having count(distinct m.association_id) = 1
    )
  );
$$;

create or replace function my_associations()
returns table (id uuid, name text, state text, city text, settings jsonb)
language sql stable security definer set search_path = public as $$
  select a.id, a.name, a.state, a.city, a.settings
  from associations a join memberships m on m.association_id = a.id
  where m.user_id = auth.uid() and m.ended_at is null
  group by a.id
  order by a.name;
$$;

create or replace function has_role(assoc uuid, roles app_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and exists (
    select 1 from memberships m
    where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null and m.role = any(roles)
  );
$$;

create or replace function is_member(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and exists (
    select 1 from memberships m where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null
  );
$$;

create or replace function my_flat_ids(assoc uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select m.flat_id from memberships m
  where assoc = my_association() and m.association_id = assoc
    and m.user_id = auth.uid() and m.ended_at is null and m.flat_id is not null;
$$;

create or replace function my_owned_flat_numbers(assoc uuid) returns setof text
language sql stable security definer set search_path = public as $$
  select f.number from memberships m join flats f on f.id = m.flat_id
  where assoc = my_association() and m.association_id = assoc
    and m.user_id = auth.uid() and m.ended_at is null and m.role = 'owner';
$$;

create or replace function owns_flat(fid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m join flats f on f.id = m.flat_id
    where m.association_id = my_association() and f.association_id = m.association_id
      and m.user_id = auth.uid() and m.ended_at is null and m.role = 'owner' and m.flat_id::text = fid
  );
$$;

create or replace function can_manage_members(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and (
    has_role(assoc, array['admin','president','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null
        and m.role in ('ec_member','monitor') and 'Membership desk' = any(m.designations)
    )
  );
$$;

create or replace function is_step_party(req uuid, assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and exists (
    select 1 from approval_steps s
    where s.request_id = req
      and (s.approver = auth.uid() or s.owner_flat in (select my_owned_flat_numbers(assoc)))
  );
$$;

drop policy complaints_read on complaints;
create policy complaints_read on complaints for select using (
  association_id = my_association() and (
    has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor','caretaker']::app_role[])
    or raised_by = auth.uid()
    or (flat_id in (select my_flat_ids(association_id)) and not is_private)
  )
);

drop policy approvals_read on approval_requests;
create policy approvals_read on approval_requests for select using (
  association_id = my_association() and (
    has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[])
    or initiator = auth.uid()
    or is_step_party(id, association_id)
  )
);

revoke all on function set_active_association(uuid) from public;
grant execute on function set_active_association(uuid) to authenticated;
revoke all on function my_associations() from public;
grant execute on function my_associations() to authenticated;