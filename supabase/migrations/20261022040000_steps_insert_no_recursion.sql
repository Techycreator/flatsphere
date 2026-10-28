-- A policy on approval_steps cannot query approval_steps itself (RLS recursion); check via security definer.
create function request_has_decisions(req uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from approval_steps where request_id = req and decision <> 'pending');
$$;

drop policy steps_insert on approval_steps;
create policy steps_insert on approval_steps for insert with check (
  decision = 'pending' and decided_by is null and decided_at is null and decided_by_name is null
  and exists (select 1 from approval_requests r where r.id = request_id and r.initiator = auth.uid())
  and not request_has_decisions(request_id));
