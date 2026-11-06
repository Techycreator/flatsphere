-- Owners and residents see only their own complaints unless the Admin lets them see all; other roles are unchanged.
drop policy complaints_read on complaints;
create policy complaints_read on complaints for select using (
  association_id = my_association() and (
    has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor','caretaker']::app_role[])
    or raised_by = auth.uid()
    or (has_role(association_id, array['owner']::app_role[])
        and coalesce((select (a.settings->>'complaints_visible_to_owners')::boolean from associations a where a.id = complaints.association_id), false))
    or (has_role(association_id, array['resident']::app_role[])
        and coalesce((select (a.settings->>'complaints_visible_to_residents')::boolean from associations a where a.id = complaints.association_id), false))
  )
);

create or replace function update_complaint_visibility(p_owners boolean, p_residents boolean)
returns void language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin']::app_role[]) then
    raise exception 'not_allowed: association Admin access required';
  end if;
  update associations set settings=settings||jsonb_build_object(
    'complaints_visible_to_owners',coalesce(p_owners,false),
    'complaints_visible_to_residents',coalesce(p_residents,false)
  ) where id=a;
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'update_complaint_visibility','association',a::text,jsonb_build_object(
    'complaints_visible_to_owners',coalesce(p_owners,false),'complaints_visible_to_residents',coalesce(p_residents,false)
  ));
end $$;
revoke all on function update_complaint_visibility(boolean,boolean) from public;
grant execute on function update_complaint_visibility(boolean,boolean) to authenticated;
