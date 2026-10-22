-- Keep incoming personal data separate from broadly readable approval summaries.
create table membership_changes (
  request_id uuid primary key references approval_requests(id) on delete cascade,
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  flat_id uuid not null references flats(id),
  change_type text not null check (change_type in ('owner', 'resident')),
  incoming_name text not null check (length(trim(incoming_name)) > 0),
  incoming_email text not null check (incoming_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  incoming_mobile text,
  lease_period text,
  family_count smallint not null default 1 check (family_count between 0 and 30),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
alter table membership_changes enable row level security;
create policy membership_changes_read on membership_changes for select using (
  association_id = my_association()
  and (created_by = auth.uid() or can_manage_members(association_id) or owns_flat(flat_id::text))
);
create policy membership_changes_insert on membership_changes for insert with check (
  association_id = my_association() and created_by = auth.uid()
  and exists (
    select 1 from approval_requests r
    where r.id = request_id and r.association_id = membership_changes.association_id and r.initiator = auth.uid()
      and r.code = case when change_type = 'owner' then 'W20' else 'W21' end
  )
  and (can_manage_members(association_id) or owns_flat(flat_id::text))
);

alter table id_documents
  add column request_id uuid references approval_requests(id) on delete set null;

create index id_documents_request_idx on id_documents (association_id, request_id);

drop policy id_docs_insert on id_documents;
create policy id_docs_insert on id_documents for insert with check (
  uploaded_by = auth.uid() and is_member(association_id)
  and (can_manage_members(association_id) or owns_flat(flat_id::text))
  and (request_id is null or exists (
    select 1 from membership_changes c
    where c.request_id = id_documents.request_id and c.association_id = id_documents.association_id
      and c.flat_id = id_documents.flat_id and c.created_by = auth.uid()
  ))
);

create or replace function decide_step(req uuid, d decision, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  r approval_requests;
  s approval_steps;
  c membership_changes;
  a uuid;
  fid uuid;
  flat_no text;
  full_name text;
  e text;
  mob text;
  uid uuid;
  old_emails text[];
begin
  select * into r from approval_requests where id = req for update;
  if r.id is null then raise exception 'request not found'; end if;
  if d = 'pending' then raise exception 'invalid decision'; end if;
  if r.initiator = auth.uid() then raise exception 'maker-checker: initiator cannot decide'; end if;
  if exists (select 1 from approval_steps where request_id = req and decision in ('rejected', 'sent_back')) then
    raise exception 'request is closed';
  end if;
  if exists (select 1 from approval_steps where request_id = req and decided_by = auth.uid()) then
    raise exception 'maker-checker: one person cannot decide two steps';
  end if;
  select * into s from approval_steps where request_id = req and decision = 'pending' order by seq limit 1 for update;
  if s.id is null then raise exception 'no pending step'; end if;
  if s.role = 'owner' and s.owner_flat is not null then
    if not exists (select 1 from my_owned_flat_numbers(r.association_id) n where n = s.owner_flat) then
      raise exception 'not your step';
    end if;
  elsif not (has_role(r.association_id, array[s.role])
             or (s.alternate_role is not null and has_role(r.association_id, array[s.alternate_role])))
        or (s.approver is not null and s.approver <> auth.uid()) then
    raise exception 'not your step';
  end if;
  if d <> 'approved' and coalesce(trim(note), '') = '' then raise exception 'comment required'; end if;

  update approval_steps set decision = d, decided_by = auth.uid(), decided_by_name = (select full_name from profiles where id = auth.uid()),
    comment = note, decided_at = now()
  where id = s.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, auth.uid(), 'decide:' || d, 'approval_request', req::text,
          jsonb_build_object('step', s.seq, 'comment', note));

  if d <> 'approved' or exists (select 1 from approval_steps where request_id = req and decision <> 'approved') then
    return;
  end if;

  if r.code not in ('W20', 'W21') then return; end if;

  a := r.association_id;
  select * into c from membership_changes where request_id = req and association_id = a for update;
  if c.request_id is null or c.change_type <> (case when r.code = 'W20' then 'owner' else 'resident' end) then
    raise exception 'invalid: membership request data is missing or has the wrong type';
  end if;
  fid := c.flat_id;
  full_name := c.incoming_name;
  e := lower(c.incoming_email);
  mob := nullif(trim(c.incoming_mobile), '');
  select number into flat_no from flats where id = fid and association_id = a for update;
  if flat_no is null then raise exception 'invalid: selected flat is not in this association'; end if;
  if not exists (
    select 1 from id_documents d
    where d.request_id = req and d.association_id = a and d.flat_id = fid and lower(d.subject_email) = e
  ) then
    raise exception 'invalid: upload an ID proof for the incoming person before final approval';
  end if;

  if r.code = 'W20' and exists (
    select 1 from dues d left join payments p on p.due_id = d.id
    where d.flat_id = fid
    group by d.id, d.amount
    having d.amount > coalesce(sum(p.amount), 0)
  ) then
    raise exception 'invalid: clear outstanding dues before approving an owner change';
  end if;

  if r.code = 'W21' then
    if not exists (
      select 1 from approval_steps
      where request_id = req and decision = 'approved'
        and (role in ('secretary', 'president') or alternate_role in ('secretary', 'president'))
    ) then
      raise exception 'invalid: Secretary or President approval is required';
    end if;
    if not exists (
      select 1 from approval_steps where request_id = req and role = 'owner'
        and owner_flat = flat_no and decision = 'approved'
    ) and not exists (
      select 1 from memberships where association_id = a and user_id = r.initiator
        and role = 'owner' and flat_id = fid and ended_at is null
    ) then
      raise exception 'invalid: current flat-owner consent is required';
    end if;
  else
    if not (
      (r.initiator_role = 'secretary' or exists (select 1 from approval_steps where request_id = req and decision = 'approved'
        and (role = 'secretary' or on_behalf_of = 'Secretary')))
      and
      (r.initiator_role = 'president' or exists (select 1 from approval_steps where request_id = req and decision = 'approved'
        and (role = 'president' or on_behalf_of = 'President')))
    ) then
      raise exception 'invalid: Secretary and President approvals are required';
    end if;
  end if;

  select coalesce(array_agg(distinct lower(email)), '{}'::text[]) into old_emails
  from (
    select p.email from memberships m join profiles p on p.id = m.user_id
    where m.association_id = a and m.flat_id = fid and m.role = (case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end)
      and m.ended_at is null
    union
    select i.email from invites i
    where i.association_id = a and i.flat_id = fid and i.role = (case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end)
      and i.claimed_at is null
  ) outgoing;

  update id_documents set archived_at = now()
  where association_id = a and flat_id = fid and archived_at is null and request_id is distinct from req
    and lower(subject_email) = any(old_emails);
  update memberships set ended_at = now()
  where association_id = a and flat_id = fid
    and role = (case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end)
    and ended_at is null;
  delete from invites
  where association_id = a and flat_id = fid
    and role = (case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end)
    and claimed_at is null;

  select id into uid from profiles where lower(email) = e limit 1;
  if uid is not null then
    insert into memberships (association_id, user_id, role, flat_id)
    values (a, uid, case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end, fid);
  else
    insert into invites (association_id, email, full_name, mobile, role, flat_id, invited_by)
    values (a, e, full_name, mob, case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end, fid, auth.uid());
  end if;

  if r.code = 'W21' then
    update flats set occupancy = 'rented' where id = fid;
  end if;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'apply_membership_change', case when r.code = 'W20' then 'owner' else 'resident' end, req::text,
          jsonb_build_object('flat', flat_no, 'incoming_email', e, 'incoming_name', full_name));
end $$;