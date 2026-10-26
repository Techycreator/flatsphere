alter table marketplace_posts add column removed_at timestamptz, add column archived_at timestamptz;

create function remove_marketplace_post(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  update marketplace_posts set status='removed', removed_at=now()
  where id=p_id and association_id=my_association() and status='active'
    and (created_by=auth.uid() or has_role(association_id,array['president','secretary']::app_role[]));
  if not found then raise exception 'not_allowed: only the author, President or Secretary can remove this post'; end if;
end $$;
revoke all on function remove_marketplace_post(uuid) from public;
grant execute on function remove_marketplace_post(uuid) to authenticated;

-- Removed or expired posts move to the archive three months after they ended.
create function archive_marketplace_posts() returns void
language sql security definer set search_path=public as $$
  update marketplace_posts set archived_at=now()
  where association_id=my_association() and archived_at is null
    and coalesce(removed_at,expires_at)<now()-interval '3 months';
$$;
revoke all on function archive_marketplace_posts() from public;
grant execute on function archive_marketplace_posts() to authenticated;
