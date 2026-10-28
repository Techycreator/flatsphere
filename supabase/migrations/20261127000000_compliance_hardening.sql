-- 5-year lock on closed finance records, DPDP privacy-notice consent, audit log listing,
-- association data export, and a daily invite cap per association.

create function protect_closed_finance_records() returns trigger
language plpgsql as $$
begin
  if coalesce((to_jsonb(old)->>'created_at')::timestamptz, now()) > now() - interval '5 years' and (
       (tg_table_name = 'expenses' and old.status = 'approved')
    or (tg_table_name = 'monthly_statements' and old.status = 'published')) then
    raise exception 'not_allowed: approved or published finance records are kept for 5 years and cannot be changed or deleted';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger expenses_retention before update or delete on expenses
  for each row execute function protect_closed_finance_records();
create trigger monthly_statements_retention before update or delete on monthly_statements
  for each row execute function protect_closed_finance_records();

alter table profiles add column privacy_accepted_at timestamptz;
create function accept_privacy_notice() returns void
language sql security definer set search_path=public as $$
  update profiles set privacy_accepted_at = now() where id = auth.uid();
$$;
create function my_privacy_accepted() returns boolean
language sql stable security definer set search_path=public as $$
  select coalesce((select privacy_accepted_at is not null from profiles where id = auth.uid()), false);
$$;

create function list_audit_log(p_limit integer default 200)
returns table (at timestamptz, actor_name text, action text, entity text, entity_id text)
language plpgsql stable security definer set search_path=public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: President, Secretary or Admin only';
  end if;
  return query
    select l.at, coalesce(p.full_name, 'System'), l.action, l.entity, l.entity_id
    from audit_log l left join profiles p on p.id = l.actor
    where l.association_id = a
    order by l.at desc
    limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end $$;

-- Everything the association owns, as JSON (uploaded files and ID documents excluded).
create function export_association_data() returns jsonb
language plpgsql security definer set search_path=public as $$
declare a uuid := my_association(); r jsonb; t text; v jsonb;
begin
  if a is null or not has_role(a, array['admin','president']::app_role[]) then
    raise exception 'not_allowed: President or Admin only';
  end if;
  r := jsonb_build_object('association', (select to_jsonb(x) from associations x where x.id = a), 'exported_at', now());
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'association_id' and tb.table_type = 'BASE TABLE'
      and c.table_name not in ('audit_log','app_notifications','id_documents','invites','dues_reminders','memberships')
    order by 1
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x where x.association_id = $1', t)
      into v using a;
    r := r || jsonb_build_object(t, v);
  end loop;
  r := r || jsonb_build_object('members', (
    select coalesce(jsonb_agg((to_jsonb(m) - 'user_id') || jsonb_build_object('name', p.full_name, 'flat', f.number)), '[]'::jsonb)
    from memberships m join profiles p on p.id = m.user_id left join flats f on f.id = m.flat_id
    where m.association_id = a));
  insert into audit_log (association_id, actor, action, entity, entity_id) values (a, auth.uid(), 'export', 'association', a::text);
  return r;
end $$;

create function limit_invites_per_day() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if (select count(*) from invites where association_id = new.association_id and created_at > now() - interval '1 day') >= 100 then
    raise exception 'limit: at most 100 invites per day per association';
  end if;
  return new;
end $$;
create trigger invites_daily_limit before insert on invites for each row execute function limit_invites_per_day();

revoke execute on function accept_privacy_notice(), my_privacy_accepted(), list_audit_log(integer), export_association_data()
  from public, anon;
grant execute on function accept_privacy_notice(), my_privacy_accepted(), list_audit_log(integer), export_association_data()
  to authenticated;
