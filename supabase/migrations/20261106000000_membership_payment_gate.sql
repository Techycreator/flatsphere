alter table memberships
  add column contact_phone text check (contact_phone is null or contact_phone ~ '^[+0-9() -]{5,24}$'),
  add column date_of_birth date;
alter table invites add column date_of_birth date;
alter table membership_changes add column incoming_birth_date date;

create function validate_membership_change_birth_date() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.incoming_birth_date > current_date then
    raise exception 'invalid: date of birth cannot be in the future';
  end if;
  return new;
end $$;
create trigger membership_changes_validate_birth_date before insert or update of incoming_birth_date
  on membership_changes for each row execute function validate_membership_change_birth_date();

create function require_membership_birth_date() returns trigger
language plpgsql security definer set search_path = public as $$
declare invited_birth_date date;
begin
  if new.role in ('owner','resident') then
    if new.date_of_birth is null then
      select i.date_of_birth into invited_birth_date
      from invites i join profiles p on lower(p.email) = lower(i.email)
      where i.association_id = new.association_id and i.flat_id is not distinct from new.flat_id
        and i.role = new.role and p.id = new.user_id and i.claimed_at is null
      order by i.created_at desc limit 1;
      new.date_of_birth := invited_birth_date;
    end if;
    if new.date_of_birth > current_date then
      raise exception 'invalid: date of birth cannot be in the future';
    end if;
  end if;
  return new;
end $$;
create trigger memberships_require_birth_date before insert on memberships
  for each row execute function require_membership_birth_date();

alter table membership_changes
  add column status text not null default 'pending_first_approval'
    check (status in ('pending_first_approval','pending_payment_due','pending_final_approval','applied')),
  add column outstanding_due bigint not null default 0 check (outstanding_due >= 0),
  add column first_approved_at timestamptz,
  add column outgoing_archived_at timestamptz;

create function can_request_flat_membership_change(assoc uuid, target_flat uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and (
    can_manage_members(assoc)
    or exists (
      select 1 from memberships m
      where m.association_id = assoc and m.flat_id = target_flat and m.user_id = auth.uid()
        and m.ended_at is null and m.role in ('owner','resident')
    )
  );
$$;

drop policy membership_changes_insert on membership_changes;
create policy membership_changes_insert on membership_changes for insert with check (
  association_id = my_association() and created_by = auth.uid()
  and exists (
    select 1 from approval_requests r
    where r.id = request_id and r.association_id = membership_changes.association_id and r.initiator = auth.uid()
      and r.code = case when change_type = 'owner' then 'W20' else 'W21' end
  )
  and can_request_flat_membership_change(association_id, flat_id)
);

create function set_member_birth_date(p_kind text, p_id uuid, p_birth_date date) returns void
language plpgsql security definer set search_path = public as $$
declare a uuid := my_association(); member_role app_role;
begin
  if a is null or not can_manage_members(a) then raise exception 'not_allowed'; end if;
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
revoke all on function set_member_birth_date(text,uuid,date) from public;
grant execute on function set_member_birth_date(text,uuid,date) to authenticated;

drop policy id_docs_insert on id_documents;
create policy id_docs_insert on id_documents for insert with check (
  uploaded_by = auth.uid() and is_member(association_id)
  and can_request_flat_membership_change(association_id, flat_id)
  and (request_id is null or exists (
    select 1 from membership_changes c
    where c.request_id = id_documents.request_id and c.association_id = id_documents.association_id
      and c.flat_id = id_documents.flat_id and c.created_by = auth.uid()
  ))
);

drop policy id_proofs_upload on storage.objects;
create policy id_proofs_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'id-proofs' and (storage.foldername(name))[1] = my_association()::text
  and (
    can_manage_members(my_association())
    or owns_flat((storage.foldername(name))[2])
    or exists (
      select 1 from membership_changes c
      where c.association_id = my_association()
        and c.flat_id::text = (storage.foldername(name))[2]
        and c.request_id::text = (storage.foldername(name))[3]
        and c.created_by = auth.uid()
    )
  )
);

create function seed_membership_final_approval() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending_final_approval' and old.status is distinct from new.status
      and not exists (select 1 from approval_steps where request_id = new.request_id and role = 'secretary') then
    insert into approval_steps (request_id, seq, role, name)
    select new.request_id, coalesce(max(seq), 0) + 1, 'secretary', 'Secretary'
    from approval_steps where request_id = new.request_id;
  end if;
  return new;
end $$;
create trigger membership_final_approval_seed after update of status on membership_changes
  for each row execute function seed_membership_final_approval();

create function refresh_membership_payment_gate(p_flat uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update membership_changes c set
    outstanding_due = due_totals.amount,
    status = case when due_totals.amount > 0 then 'pending_payment_due' else 'pending_final_approval' end
  from (
    select d.flat_id, coalesce(sum(greatest(d.amount - coalesce(p.paid, 0), 0)), 0)::bigint as amount
    from dues d
    left join lateral (
      select sum(pay.amount)::bigint as paid from payments pay where pay.due_id = d.id and pay.flat_id = d.flat_id
    ) p on true
    where d.flat_id = p_flat
    group by d.flat_id
    union all
    select p_flat, 0::bigint where not exists (select 1 from dues where flat_id = p_flat)
  ) due_totals
  where c.flat_id = p_flat and c.first_approved_at is not null
    and c.status in ('pending_payment_due','pending_final_approval');
end $$;

create function refresh_membership_payment_gate_from_due() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    perform refresh_membership_payment_gate(old.flat_id);
    return old;
  end if;
  perform refresh_membership_payment_gate(new.flat_id);
  return new;
end $$;
create trigger membership_due_gate_refresh after insert or update or delete on dues
  for each row execute function refresh_membership_payment_gate_from_due();
create trigger membership_payment_gate_refresh after insert or update or delete on payments
  for each row execute function refresh_membership_payment_gate_from_due();

create function progress_membership_payment_gate() returns trigger
language plpgsql security definer set search_path = public as $$
declare c membership_changes; a uuid; old_emails text[]; due_total bigint; flat_no text;
begin
  if new.decision <> 'approved' or old.decision is not distinct from new.decision then return new; end if;
  select * into c from membership_changes where request_id = new.request_id for update;
  if c.request_id is null then return new; end if;
  a := c.association_id;

  if c.status = 'pending_first_approval' and new.role = 'president'
      and not exists (select 1 from approval_steps s where s.request_id = new.request_id and s.seq < new.seq and s.decision <> 'approved') then
    select coalesce(sum(greatest(d.amount - coalesce(p.paid, 0), 0)), 0)::bigint into due_total
    from dues d
    left join lateral (select sum(pay.amount)::bigint as paid from payments pay where pay.due_id = d.id and pay.flat_id = d.flat_id) p on true
    where d.flat_id = c.flat_id;

    select coalesce(array_agg(distinct lower(email)), '{}'::text[]) into old_emails
    from (
      select p.email from memberships m join profiles p on p.id = m.user_id
      where m.association_id = a and m.flat_id = c.flat_id
        and m.role = case when c.change_type = 'owner' then 'owner'::app_role else 'resident'::app_role end
        and m.ended_at is null
      union
      select i.email from invites i
      where i.association_id = a and i.flat_id = c.flat_id
        and i.role = case when c.change_type = 'owner' then 'owner'::app_role else 'resident'::app_role end
        and i.claimed_at is null
    ) outgoing;

    update id_documents set archived_at = now()
    where association_id = a and flat_id = c.flat_id and archived_at is null and lower(subject_email) = any(old_emails);
    update memberships set ended_at = now()
    where association_id = a and flat_id = c.flat_id
      and role = case when c.change_type = 'owner' then 'owner'::app_role else 'resident'::app_role end
      and ended_at is null;
    delete from invites
    where association_id = a and flat_id = c.flat_id
      and role = case when c.change_type = 'owner' then 'owner'::app_role else 'resident'::app_role end
      and claimed_at is null;

    update membership_changes set
      status = case when due_total > 0 then 'pending_payment_due' else 'pending_final_approval' end,
      outstanding_due = due_total, first_approved_at = now(), outgoing_archived_at = now()
    where request_id = c.request_id;
    select number into flat_no from flats where id = c.flat_id;
    insert into audit_log (association_id, actor, action, entity, entity_id, after)
    values (a, new.decided_by, 'membership_first_approval', 'membership_change', c.request_id::text,
      jsonb_build_object('flat', flat_no, 'status', case when due_total > 0 then 'pending_payment_due' else 'pending_final_approval' end,
        'outstanding_due', due_total, 'outgoing_archived', true));
  elsif c.status = 'pending_final_approval' and new.role = 'secretary'
      and not exists (select 1 from approval_steps s where s.request_id = new.request_id and s.id <> new.id and s.decision <> 'approved') then
    insert into approval_steps (request_id, seq, role, name)
    select new.request_id, coalesce(max(seq), 0) + 1, 'president', 'President'
    from approval_steps where request_id = new.request_id;
  end if;
  return new;
end $$;
create trigger membership_payment_gate_progress after update of decision on approval_steps
  for each row execute function progress_membership_payment_gate();

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
  outstanding bigint;
  repeated_president boolean := false;
begin
  select * into r from approval_requests where id = req for update;
  if r.id is null then raise exception 'request not found'; end if;
  if d = 'pending' then raise exception 'invalid decision'; end if;
  if r.initiator = auth.uid() then raise exception 'maker-checker: initiator cannot decide'; end if;
  if exists (select 1 from approval_steps where request_id = req and decision in ('rejected', 'sent_back')) then
    raise exception 'request is closed';
  end if;
  select * into s from approval_steps where request_id = req and decision = 'pending' order by seq limit 1 for update;
  if s.id is null then raise exception 'no pending step'; end if;
  if s.role = 'owner' and s.owner_flat is not null then
    if not exists (select 1 from my_owned_flat_numbers(r.association_id) n where n = s.owner_flat) then raise exception 'not your step'; end if;
  elsif not (has_role(r.association_id, array[s.role])
             or (s.alternate_role is not null and has_role(r.association_id, array[s.alternate_role])))
        or (s.approver is not null and s.approver <> auth.uid()) then
    raise exception 'not your step';
  end if;
  if r.code in ('W20','W21') then
    select * into c from membership_changes where request_id = req and association_id = r.association_id;
    if c.request_id is null then raise exception 'invalid: membership request data is missing'; end if;
    if s.role in ('secretary','president') and c.first_approved_at is not null and c.status = 'pending_payment_due' then
      raise exception 'pending_payment_due: clear all flat dues before the Secretary and President approval stage';
    end if;
    if c.status = 'pending_final_approval' and s.role = 'president'
        and exists (select 1 from approval_steps prior where prior.request_id = req and prior.role = 'president' and prior.decided_by = auth.uid()) then
      repeated_president := true;
    end if;
  end if;
  if d <> 'approved' and coalesce(trim(note), '') = '' then raise exception 'comment required'; end if;
  if exists (select 1 from approval_steps where request_id = req and decided_by = auth.uid()) and not repeated_president then
    raise exception 'maker-checker: one person cannot decide two steps';
  end if;

  update approval_steps set decision = d, decided_by = auth.uid(), decided_by_name = (select full_name from profiles where id = auth.uid()),
    comment = note, decided_at = now() where id = s.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, auth.uid(), 'decide:' || d, 'approval_request', req::text,
    jsonb_build_object('step', s.seq, 'comment', note));

  if d <> 'approved' or exists (select 1 from approval_steps where request_id = req and decision <> 'approved') then return; end if;
  if r.code not in ('W20','W21') then return; end if;

  if exists (
    select 1 from membership_changes
    where request_id = req and first_approved_at is not null and status = 'pending_payment_due'
  ) then
    return;
  end if;

  a := r.association_id;
  select * into c from membership_changes where request_id = req and association_id = a for update;
  if c.request_id is null or c.change_type <> (case when r.code = 'W20' then 'owner' else 'resident' end) then
    raise exception 'invalid: membership request data is missing or has the wrong type';
  end if;
  if c.status <> 'pending_final_approval' then raise exception 'invalid: membership change is not ready for final approval'; end if;
  fid := c.flat_id;
  full_name := c.incoming_name;
  e := lower(c.incoming_email);
  mob := nullif(trim(c.incoming_mobile), '');
  select number into flat_no from flats where id = fid and association_id = a for update;
  if flat_no is null then raise exception 'invalid: selected flat is not in this association'; end if;
  if not exists (select 1 from id_documents d where d.request_id = req and d.association_id = a
      and d.flat_id = fid and lower(d.subject_email) = e and d.archived_at is null) then
    raise exception 'invalid: upload an ID proof for the incoming person before final approval';
  end if;

  select coalesce(sum(greatest(d.amount - coalesce(p.paid, 0), 0)), 0)::bigint into outstanding
  from dues d left join lateral (select sum(pay.amount)::bigint as paid from payments pay where pay.due_id = d.id and pay.flat_id = d.flat_id) p on true
  where d.flat_id = fid;
  if outstanding > 0 then raise exception 'pending_payment_due: clear all outstanding dues before final approval'; end if;

  if r.code = 'W21' then
    if not exists (select 1 from approval_steps where request_id = req and role = 'owner'
        and owner_flat = flat_no and decision = 'approved')
      and not exists (select 1 from memberships where association_id = a and user_id = r.initiator
        and role = 'owner' and flat_id = fid and ended_at is null) then
      raise exception 'invalid: current flat-owner consent is required';
    end if;
  end if;

  select coalesce(array_agg(distinct lower(email)), '{}'::text[]) into old_emails
  from (
    select p.email from memberships m join profiles p on p.id = m.user_id
    where m.association_id = a and m.flat_id = fid
      and m.role = case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end and m.ended_at is null
    union
    select i.email from invites i where i.association_id = a and i.flat_id = fid
      and i.role = case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end and i.claimed_at is null
  ) outgoing;
  update id_documents set archived_at = now() where association_id = a and flat_id = fid and archived_at is null
    and request_id is distinct from req and lower(subject_email) = any(old_emails);
  update memberships set ended_at = now() where association_id = a and flat_id = fid
    and role = case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end and ended_at is null;
  delete from invites where association_id = a and flat_id = fid
    and role = case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end and claimed_at is null;

  select id into uid from profiles where lower(email) = e limit 1;
  if uid is not null then
    insert into memberships (association_id, user_id, role, flat_id, contact_phone, date_of_birth)
    values (a, uid, case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end, fid, mob, c.incoming_birth_date);
  else
    insert into invites (association_id, email, full_name, mobile, role, flat_id, invited_by, date_of_birth)
    values (a, e, full_name, mob, case when r.code = 'W20' then 'owner'::app_role else 'resident'::app_role end, fid, auth.uid(), c.incoming_birth_date);
  end if;
  if r.code = 'W21' then update flats set occupancy = 'rented' where id = fid; end if;
  update membership_changes set status = 'applied', outstanding_due = 0 where request_id = req;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'apply_membership_change', case when r.code = 'W20' then 'owner' else 'resident' end, req::text,
    jsonb_build_object('flat', flat_no, 'incoming_email', e, 'incoming_name', full_name, 'status', 'applied'));
end $$;

revoke all on function can_request_flat_membership_change(uuid, uuid) from public;
revoke all on function refresh_membership_payment_gate(uuid) from public;
revoke all on function refresh_membership_payment_gate_from_due() from public;
revoke all on function progress_membership_payment_gate() from public;
grant execute on function decide_step(uuid, decision, text) to authenticated;
