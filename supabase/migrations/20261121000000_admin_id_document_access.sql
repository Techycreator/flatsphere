-- Let association Admins manage broad ID-proof access for office bearers and Membership Desk POCs.
create table association_id_document_access (
  association_id uuid not null references associations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  can_view boolean not null,
  updated_by uuid not null default auth.uid() references profiles(id),
  updated_at timestamptz not null default now(),
  primary key (association_id,user_id)
);
alter table association_id_document_access enable row level security;

create function id_document_access_candidate(assoc uuid,target uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from memberships m where m.association_id=assoc and m.user_id=target and m.ended_at is null
    and m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer'))
  or exists(select 1 from memberships m where m.association_id=assoc and m.user_id=target and m.ended_at is null
    and m.role in ('ec_member','monitor') and 'Membership desk'=any(m.designations))
$$;
revoke all on function id_document_access_candidate(uuid,uuid) from public;

create function list_id_document_access()
returns table(user_id uuid,full_name text,role_labels text,can_view_all boolean,is_office_bearer boolean)
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin']::app_role[]) then
    raise exception 'not_allowed: association Admin access required';
  end if;
  return query
  select m.user_id,p.full_name,
    string_agg(distinct m.role::text,', ' order by m.role::text),
    coalesce(o.can_view,bool_or(m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer'))),
    bool_or(m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer'))
  from memberships m join profiles p on p.id=m.user_id
  left join association_id_document_access o on o.association_id=m.association_id and o.user_id=m.user_id
  where m.association_id=a and m.ended_at is null
    and id_document_access_candidate(a,m.user_id)
  group by m.user_id,p.full_name,o.can_view
  order by p.full_name;
end $$;
revoke all on function list_id_document_access() from public;
grant execute on function list_id_document_access() to authenticated;

create function set_id_document_access(p_user_id uuid,p_can_view boolean)
returns void language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin']::app_role[]) then
    raise exception 'not_allowed: association Admin access required';
  end if;
  if not id_document_access_candidate(a,p_user_id) then
    raise exception 'invalid: choose an active office bearer or Membership Desk POC';
  end if;
  insert into association_id_document_access(association_id,user_id,can_view,updated_by,updated_at)
  values(a,p_user_id,p_can_view,auth.uid(),now())
  on conflict(association_id,user_id) do update
    set can_view=excluded.can_view,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'set_id_document_access','member',p_user_id::text,jsonb_build_object('can_view',p_can_view));
end $$;
revoke all on function set_id_document_access(uuid,boolean) from public;
grant execute on function set_id_document_access(uuid,boolean) to authenticated;

create function can_view_id_documents(p_association uuid,p_request uuid)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); has_override boolean; explicit_access boolean;
begin
  if v_user is null then return false; end if;
  if p_association is distinct from my_association()
    or not id_document_access_candidate(p_association,v_user) then return false; end if;
  select true,o.can_view into has_override,explicit_access
  from association_id_document_access o
  where o.association_id=p_association and o.user_id=v_user;
  if has_override then return explicit_access; end if;
  if has_role(p_association,array[
    'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer'
  ]::app_role[]) then return true; end if;
  return p_request is not null and exists(
    select 1 from approval_steps s join approval_requests r on r.id=s.request_id
    where s.request_id=p_request and r.association_id=p_association and s.approver=v_user
  );
end $$;
revoke all on function can_view_id_documents(uuid,uuid) from public;
grant execute on function can_view_id_documents(uuid,uuid) to authenticated;

drop policy id_docs_read on id_documents;
create policy id_docs_read on id_documents for select using (
  is_member(association_id) and (
    owns_flat(flat_id::text)
    or uploaded_by=auth.uid()
    or exists(select 1 from approval_requests r where r.id=id_documents.request_id
      and r.association_id=id_documents.association_id and r.initiator=auth.uid())
    or can_view_id_documents(association_id,request_id)
  )
);
