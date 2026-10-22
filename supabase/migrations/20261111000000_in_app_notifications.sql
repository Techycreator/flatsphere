create table app_notifications (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  event_key text not null,
  title text not null check (length(trim(title)) between 1 and 160),
  body text not null default '',
  action_path text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (association_id,user_id,event_key)
);
create index app_notifications_user_unread_idx on app_notifications (association_id,user_id,created_at desc) where read_at is null;
alter table app_notifications enable row level security;
create policy app_notifications_read_self on app_notifications for select using (
  association_id=my_association() and user_id=auth.uid()
);
create policy app_notifications_update_self on app_notifications for update using (
  association_id=my_association() and user_id=auth.uid()
) with check (association_id=my_association() and user_id=auth.uid());

grant select on app_notifications to authenticated;
grant update(read_at) on app_notifications to authenticated;

create function notify_approval_step_assignment() returns trigger
language plpgsql security definer set search_path=public as $$
declare r approval_requests;
begin
  select * into r from approval_requests where id=new.request_id;
  if r.id is null then return new; end if;
  insert into app_notifications (association_id,user_id,event_key,title,body,action_path)
  select r.association_id,m.user_id,'approval-step:'||new.id::text,'Approval requested',r.title,'/approvals/'||r.ref
  from memberships m left join flats f on f.id=m.flat_id
  where m.association_id=r.association_id and m.ended_at is null and m.role=new.role
    and (new.approver is null or new.approver=m.user_id)
    and (new.owner_flat is null or f.number=new.owner_flat)
    and m.user_id<>r.initiator
  on conflict (association_id,user_id,event_key) do nothing;
  return new;
end $$;
create trigger app_notify_approval_step_insert after insert on approval_steps
  for each row execute function notify_approval_step_assignment();

create function notify_approval_step_decision() returns trigger
language plpgsql security definer set search_path=public as $$
declare r approval_requests;
begin
  if old.decision is not distinct from new.decision or new.decision='pending' then return new; end if;
  select * into r from approval_requests where id=new.request_id;
  if r.id is null then return new; end if;
  insert into app_notifications (association_id,user_id,event_key,title,body,action_path)
  values (r.association_id,r.initiator,'approval-decision:'||new.id::text||':'||new.decision::text,
    'Approval updated',r.title||' · '||replace(new.decision::text,'_',' '),'/approvals/'||r.ref)
  on conflict (association_id,user_id,event_key) do nothing;
  return new;
end $$;
create trigger app_notify_approval_decision after update of decision on approval_steps
  for each row execute function notify_approval_step_decision();

create function notify_association_meeting_scheduled() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into app_notifications (association_id,user_id,event_key,title,body,action_path)
  select new.association_id,m.user_id,'meeting-scheduled:'||new.id::text,'Meeting scheduled',new.title,'/meetings'
  from memberships m
  where m.association_id=new.association_id and m.ended_at is null and m.user_id<>new.created_by
    and case new.meeting_type
      when 'General Body' then m.role in ('owner','resident')
      when 'Staff meeting' then m.role in ('caretaker','security')
      when 'Office bearers' then m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer')
      else m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member')
    end
  on conflict (association_id,user_id,event_key) do nothing;
  return new;
end $$;
create trigger app_notify_meeting_insert after insert on association_meetings
  for each row execute function notify_association_meeting_scheduled();

create function list_app_notifications(p_limit integer default 30)
returns setof app_notifications language plpgsql stable security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null then raise exception 'not_allowed: active association required'; end if;
  return query select n.* from app_notifications n where n.association_id=a and n.user_id=auth.uid()
    order by n.created_at desc limit least(greatest(coalesce(p_limit,30),1),100);
end $$;

create function mark_app_notification_read(p_notification uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  update app_notifications set read_at=coalesce(read_at,now())
  where id=p_notification and association_id=my_association() and user_id=auth.uid();
end $$;
revoke all on function list_app_notifications(integer) from public;
revoke all on function mark_app_notification_read(uuid) from public;
grant execute on function list_app_notifications(integer) to authenticated;
grant execute on function mark_app_notification_read(uuid) to authenticated;
