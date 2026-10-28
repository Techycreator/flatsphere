-- People can belong to several associations. Every association-owned table now only returns rows of the
-- association currently open in the app (restrictive policy, ANDed with the existing read rules).
-- Memberships and the association-switch context stay readable across associations.
do $$
declare t text;
begin
  for t in
    select c.relname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    join information_schema.columns col on col.table_schema = 'public' and col.table_name = c.relname and col.column_name = 'association_id'
    where c.relkind = 'r' and c.relrowsecurity
      and c.relname not in ('memberships', 'user_association_context', 'associations', 'audit_log')
  loop
    execute format('drop policy if exists active_association_only on public.%I', t);
    execute format(
      'create policy active_association_only on public.%I as restrictive for select to authenticated using (association_id = my_association())', t);
  end loop;
end $$;
