-- FlatSphere initial schema: multi-association, role-based access enforced with RLS.

create type app_role as enum ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor','owner','resident','caretaker','auditor');
create type occupancy as enum ('owner_occupied','rented','vacant');
create type criticality as enum ('critical','high','medium','low');
create type ticket_status as enum ('pending_review','new','assigned','in_progress','on_hold','planned','resolved','closed','rejected');
create type report_kind as enum ('complaint','enhancement_immediate','enhancement_future');
create type decision as enum ('pending','approved','rejected','sent_back');

create table associations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  state text not null default 'Kerala',
  city text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table flats (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  number text not null,
  block text,
  flat_type text not null,
  sqft int,
  occupancy occupancy not null default 'owner_occupied',
  unique (association_id, number)
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  mobile text unique,
  language text not null default 'en',
  created_at timestamptz not null default now()
);

-- A user's role in an association; flat_id set for owner/resident; ended_at = access disabled.
create table memberships (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role app_role not null,
  flat_id uuid references flats(id),
  designations text[] not null default '{}',
  monitor_categories text[] not null default '{}',
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index on memberships (user_id) where ended_at is null;

create table complaints (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  ref text not null,
  flat_id uuid references flats(id),
  kind report_kind not null default 'complaint',
  category text not null,
  title text not null,
  description text not null default '',
  location text,
  criticality criticality not null default 'medium',
  ai_suggested boolean not null default false,
  status ticket_status not null default 'new',
  is_private boolean not null default false,
  estimated_cost int,
  raised_by uuid not null references profiles(id),
  assignee uuid references profiles(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (association_id, ref)
);

create table complaint_remarks (
  id bigint generated always as identity primary key,
  complaint_id uuid not null references complaints(id) on delete cascade,
  author uuid not null references profiles(id),
  body text not null,
  created_at timestamptz not null default now()
);

create table approval_requests (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  code text not null,
  title text not null,
  details jsonb not null default '{}'::jsonb,
  initiator uuid not null references profiles(id),
  mom_ref text,
  high_risk boolean not null default false,
  flagged boolean not null default false,
  created_at timestamptz not null default now()
);

create table approval_steps (
  id bigint generated always as identity primary key,
  request_id uuid not null references approval_requests(id) on delete cascade,
  seq int not null,
  role app_role not null,
  alternate_role app_role,
  approver uuid references profiles(id),
  decision decision not null default 'pending',
  decided_by uuid references profiles(id),
  comment text,
  decided_at timestamptz,
  unique (request_id, seq)
);

-- Append-only audit log.
create table audit_log (
  id bigint generated always as identity primary key,
  association_id uuid references associations(id),
  actor uuid,
  action text not null,
  entity text not null,
  entity_id text,
  before jsonb,
  after jsonb,
  at timestamptz not null default now()
);

-- Helpers (security definer so RLS policies can call them without recursion).
create function has_role(assoc uuid, roles app_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m
    where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null and m.role = any(roles));
$$;

create function is_member(assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null);
$$;

create function my_flat_ids(assoc uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select m.flat_id from memberships m
  where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null and m.flat_id is not null;
$$;

alter table associations enable row level security;
alter table flats enable row level security;
alter table profiles enable row level security;
alter table memberships enable row level security;
alter table complaints enable row level security;
alter table complaint_remarks enable row level security;
alter table approval_requests enable row level security;
alter table approval_steps enable row level security;
alter table audit_log enable row level security;

create policy assoc_read on associations for select using (is_member(id));
create policy flats_read on flats for select using (is_member(association_id));
create policy profiles_self on profiles for select using (id = auth.uid());
create policy profiles_self_update on profiles for update using (id = auth.uid());
create policy memberships_read on memberships for select using (
  user_id = auth.uid() or has_role(association_id, array['admin','president','secretary','joint_secretary']::app_role[]));

-- Committee and caretaker see all complaints; owners/residents only their flat's or their own.
create policy complaints_read on complaints for select using (
  has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor','caretaker']::app_role[])
  or raised_by = auth.uid()
  or (flat_id in (select my_flat_ids(association_id)) and not is_private));
create policy complaints_insert on complaints for insert with check (raised_by = auth.uid() and is_member(association_id));
create policy complaints_update_staff on complaints for update using (
  has_role(association_id, array['president','secretary','joint_secretary','monitor','caretaker']::app_role[]));

create policy remarks_read on complaint_remarks for select using (
  exists (select 1 from complaints c where c.id = complaint_id));
create policy remarks_insert on complaint_remarks for insert with check (author = auth.uid());

create policy approvals_read on approval_requests for select using (
  has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[])
  or initiator = auth.uid()
  or exists (select 1 from approval_steps s where s.request_id = approval_requests.id and s.approver = auth.uid()));
create policy approvals_insert on approval_requests for insert with check (initiator = auth.uid() and is_member(association_id));
create policy steps_read on approval_steps for select using (
  exists (select 1 from approval_requests r where r.id = request_id));

-- Decisions go through this function: enforces current step, role match and maker-checker.
create function decide_step(req uuid, d decision, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r approval_requests; s approval_steps;
begin
  select * into r from approval_requests where id = req;
  if r.initiator = auth.uid() then raise exception 'maker-checker: initiator cannot decide'; end if;
  select * into s from approval_steps where request_id = req and decision = 'pending' order by seq limit 1;
  if s.id is null then raise exception 'no pending step'; end if;
  if not (has_role(r.association_id, array[s.role]) or (s.alternate_role is not null and has_role(r.association_id, array[s.alternate_role])))
     or (s.approver is not null and s.approver <> auth.uid()) then
    raise exception 'not your step';
  end if;
  if d <> 'approved' and coalesce(trim(note), '') = '' then raise exception 'comment required'; end if;
  update approval_steps set decision = d, decided_by = auth.uid(), comment = note, decided_at = now() where id = s.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, auth.uid(), 'decide:' || d, 'approval_request', req::text, jsonb_build_object('step', s.seq, 'comment', note));
end $$;

create policy audit_read on audit_log for select using (
  has_role(association_id, array['admin','president','secretary','treasurer','auditor']::app_role[]));
