create or replace function can_update_complaint(assoc uuid, complaint_category text) returns boolean
language sql stable security definer set search_path = public as $$
  select assoc = my_association() and (
    has_role(assoc, array['president','secretary','joint_secretary','caretaker']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = assoc and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and complaint_category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  );
$$;

drop policy complaints_update_staff on complaints;
create policy complaints_update_staff on complaints for update using (
  association_id = my_association() and can_update_complaint(association_id, category)
) with check (
  association_id = my_association() and can_update_complaint(association_id, category)
);

create function guard_complaint_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and not (
    has_role(old.association_id, array['caretaker','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = old.association_id and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and old.category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  ) then
    raise exception 'not_allowed: status updates require caretaker, Secretary, Joint Secretary, or the assigned area monitor';
  end if;
  return new;
end $$;
create trigger complaints_guard_status before update of status on complaints
  for each row execute function guard_complaint_status_change();

create function set_complaint_status(p_ref text, p_status ticket_status, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  c complaints;
  who text := my_name();
begin
  if a is null then raise exception 'not_allowed: association session required'; end if;
  if p_status not in ('new','assigned','in_progress','on_hold','resolved','closed') then
    raise exception 'invalid: choose an operational complaint status';
  end if;
  select * into c from complaints where association_id = a and ref = p_ref for update;
  if c.id is null then raise exception 'not_found: complaint not found'; end if;
  if not (
    has_role(a, array['caretaker','secretary','joint_secretary']::app_role[])
    or exists (
      select 1 from memberships m
      where m.association_id = a and m.user_id = auth.uid() and m.ended_at is null
        and m.role = 'monitor' and c.category = any(m.monitor_categories)
        and (m.monitor_from is null or m.monitor_from <= current_date)
        and (m.monitor_until is null or m.monitor_until >= current_date)
    )
  ) then
    raise exception 'not_allowed: status updates require caretaker, Secretary, Joint Secretary, or the assigned area monitor';
  end if;
  if p_status = 'on_hold' and coalesce(trim(p_note), '') = '' then
    raise exception 'invalid: add a reason before putting a complaint on hold';
  end if;
  update complaints set status = p_status where id = c.id;
  insert into complaint_remarks (complaint_id, author, author_name, body)
  values (c.id, auth.uid(), who, '[' || p_status::text || '] ' || nullif(trim(coalesce(p_note, '')), ''));
  insert into audit_log (association_id, actor, action, entity, entity_id, before, after)
  values (a, auth.uid(), 'set_complaint_status', 'complaint', c.ref,
    jsonb_build_object('status', c.status), jsonb_build_object('status', p_status, 'note', p_note));
end $$;

revoke all on function set_complaint_status(text, ticket_status, text) from public;
grant execute on function set_complaint_status(text, ticket_status, text) to authenticated;