-- Pass codes: secure random and unique among a association's expected visitors. Gate: owner/resident contacts for calling a flat.
create or replace function set_visitor_pass_code() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c text;
  tries int := 0;
begin
  if new.approval = 'pre_approved' and new.pass_code is null then
    loop
      c := lpad(((('x' || lpad(encode(extensions.gen_random_bytes(4), 'hex'), 16, '0'))::bit(64)::bigint) % 1000000)::text, 6, '0');
      exit when not exists (select 1 from visitor_requests v
                            where v.association_id = new.association_id and v.pass_code = c and v.status = 'expected');
      tries := tries + 1;
      if tries > 20 then raise exception 'could not generate a pass code, try again'; end if;
    end loop;
    new.pass_code := c;
  end if;
  return new;
end $$;
revoke all on function set_visitor_pass_code() from public, anon, authenticated;

create unique index visitor_requests_active_pass_code on visitor_requests (association_id, pass_code)
  where status = 'expected' and pass_code is not null;

create function gate_flat_contacts(p_flat text) returns table (name text, role text, mobile text)
language plpgsql stable security definer set search_path = public as $$
declare a uuid := my_association();
begin
  if a is null or not has_role(a, array['security','caretaker','admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: gate staff only';
  end if;
  return query
    select distinct p.full_name, m.role::text, p.mobile
    from memberships m join flats f on f.id = m.flat_id join profiles p on p.id = m.user_id
    where m.association_id = a and f.association_id = a and upper(f.number) = upper(trim(p_flat))
      and m.ended_at is null and m.role in ('owner', 'resident') and p.mobile is not null
    order by 2, 1;
end $$;
revoke all on function gate_flat_contacts(text) from public, anon;
grant execute on function gate_flat_contacts(text) to authenticated;
