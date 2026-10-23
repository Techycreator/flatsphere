create trigger archive_invite_changes after insert or update or delete on invites
  for each row execute function archive_row_change('invite');

create or replace function search_association_archive(
  p_year integer default null,
  p_flat text default null,
  p_person text default null,
  p_entity text default null,
  p_limit integer default 100
) returns setof association_archive
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: only an Admin, President or Secretary can search archived records';
  end if;
  return query
    select ar.* from association_archive ar
    where ar.association_id = a
      and ar.entity_type = any(array[
        'membership', 'invite', 'profile', 'staff', 'staff_private_details', 'household_housekeeping',
        'vendor', 'vendor_amc_contract', 'association_document'
      ])
      and (p_year is null or extract(year from ar.archived_at)::integer = p_year)
      and (nullif(trim(p_flat), '') is null or ar.flat_number ilike '%' || trim(p_flat) || '%')
      and (nullif(trim(p_person), '') is null or ar.person_name ilike '%' || trim(p_person) || '%')
      and (p_entity is null or ar.entity_type = p_entity)
    order by ar.archived_at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 250);
end $$;
