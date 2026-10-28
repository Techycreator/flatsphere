-- Prevent direct table reads from exposing member/invite dates of birth.
-- RLS continues to scope rows; column grants remove DOB from manager-readable rows.
revoke select on table public.memberships from authenticated;
grant select (
  association_id,
  user_id,
  role,
  flat_id,
  designations,
  monitor_categories,
  monitor_from,
  monitor_until,
  assigned_by,
  support_flags,
  started_at,
  ended_at
) on table public.memberships to authenticated;

-- Invite data is consumed through security-definer RPCs; clients do not query the table directly.
revoke select on table public.invites from authenticated;

create or replace function directory()
returns table (
  kind text, id uuid, full_name text, email text, mobile text, role app_role, flat_number text,
  designations text[], monitor_categories text[], monitor_from date, monitor_until date,
  assigned_by text, support_flags text[], since timestamptz, date_of_birth date
)
language sql stable security definer set search_path=public as $$
  select 'member',m.id,p.full_name,p.email,coalesce(m.contact_phone,p.mobile),m.role,f.number,
    m.designations,m.monitor_categories,m.monitor_from,m.monitor_until,m.assigned_by,
    case when has_role(m.association_id,array['president','secretary']::app_role[]) then m.support_flags else '{}'::text[] end,
    m.started_at,case when m.user_id=auth.uid() then m.date_of_birth else null::date end
  from memberships m join profiles p on p.id=m.user_id left join flats f on f.id=m.flat_id
  where m.association_id=my_association() and m.ended_at is null and can_manage_members(m.association_id)
  union all
  select 'invited',i.id,i.full_name,i.email,i.mobile,i.role,f.number,i.designations,i.monitor_categories,
    i.monitor_from,i.monitor_until,i.assigned_by,
    case when has_role(i.association_id,array['president','secretary']::app_role[]) then i.support_flags else '{}'::text[] end,
    i.created_at,null::date
  from invites i left join flats f on f.id=i.flat_id
  where i.association_id=my_association() and i.claimed_at is null and can_manage_members(i.association_id)
$$;
revoke all on function directory() from public;
grant execute on function directory() to authenticated;
