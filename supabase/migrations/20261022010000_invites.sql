-- Invite-only sign-up: an email can log in only after an association invites it.
alter table profiles add column email text;

create table invites (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  email text not null,
  full_name text not null,
  role app_role not null,
  flat_id uuid references flats(id),
  designations text[] not null default '{}',
  monitor_categories text[] not null default '{}',
  invited_by uuid references profiles(id),
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
create index on invites (lower(email));
alter table invites enable row level security;
create policy invites_admin on invites for all
  using (has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[]))
  with check (has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[]));

create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare n text;
begin
  select full_name into n from invites where lower(email) = lower(new.email) and claimed_at is null limit 1;
  if n is null then raise exception 'not_invited: this email has not been invited by an association'; end if;
  insert into profiles (id, full_name, email) values (new.id, n, new.email);
  insert into memberships (association_id, user_id, role, flat_id, designations, monitor_categories)
    select association_id, new.id, role, flat_id, designations, monitor_categories
    from invites where lower(email) = lower(new.email) and claimed_at is null;
  update invites set claimed_at = now() where lower(email) = lower(new.email) and claimed_at is null;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();
