-- Revoking a role records why; only that role ends, any other roles the person holds stay active.
create function revoke_member_role(p_kind text,p_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if length(trim(coalesce(p_reason,'')))<3 or length(trim(p_reason))>300 then
    raise exception 'invalid: enter a reason of 3 to 300 characters';
  end if;
  perform remove_member(p_kind,p_id);
  insert into audit_log(association_id,actor,action,entity,entity_id,after)
  values(a,auth.uid(),'revoke_role_reason','membership',p_id::text,
    jsonb_build_object('kind',p_kind,'reason',trim(p_reason)));
end $$;
revoke all on function revoke_member_role(text,uuid,text) from public, anon;
grant execute on function revoke_member_role(text,uuid,text) to authenticated;
