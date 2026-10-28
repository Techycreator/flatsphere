-- Fields the app shows on approval requests/steps, owner-consent steps bound to a flat,
-- and stricter maker-checker rules in decide_step.
alter table approval_requests
  alter column association_id set default my_association(),
  alter column initiator set default auth.uid(),
  add column ref text,
  add column initiator_name text,
  add column initiator_role app_role,
  add column category text not null default 'General',
  add column mom_required boolean not null default false,
  add constraint approval_requests_ref_key unique (association_id, ref);

alter table approval_steps
  add column name text,
  add column on_behalf_of text,
  add column owner_flat text,
  add column decided_by_name text;

create function my_owned_flat_numbers(assoc uuid) returns setof text
language sql stable security definer set search_path = public as $$
  select f.number from memberships m join flats f on f.id = m.flat_id
  where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null and m.role = 'owner';
$$;

-- Security definer so approvals_read does not recurse through steps_read.
create function is_step_party(req uuid, assoc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from approval_steps s
    where s.request_id = req
      and (s.approver = auth.uid() or s.owner_flat in (select my_owned_flat_numbers(assoc))));
$$;

drop policy approvals_read on approval_requests;
create policy approvals_read on approval_requests for select using (
  has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[])
  or initiator = auth.uid()
  or is_step_party(id, association_id));

-- Only the initiator adds steps, only as pending, and only before any decision.
create policy steps_insert on approval_steps for insert with check (
  decision = 'pending' and decided_by is null and decided_at is null and decided_by_name is null
  and exists (select 1 from approval_requests r where r.id = request_id and r.initiator = auth.uid())
  and not exists (select 1 from approval_steps s where s.request_id = approval_steps.request_id and s.decision <> 'pending'));

create or replace function decide_step(req uuid, d decision, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r approval_requests; s approval_steps; who text;
begin
  select * into r from approval_requests where id = req;
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
  select full_name into who from profiles where id = auth.uid();
  update approval_steps set decision = d, decided_by = auth.uid(), decided_by_name = who, comment = note, decided_at = now()
  where id = s.id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, auth.uid(), 'decide:' || d, 'approval_request', req::text,
          jsonb_build_object('step', s.seq, 'comment', note));
end $$;

create function toggle_flag(req uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r approval_requests;
begin
  select * into r from approval_requests where id = req;
  if r.id is null or not has_role(r.association_id, array['president']::app_role[]) then
    raise exception 'only the President can flag requests';
  end if;
  update approval_requests set flagged = not flagged where id = req;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (r.association_id, auth.uid(), 'flag', 'approval_request', req::text, jsonb_build_object('flagged', not r.flagged));
end $$;
