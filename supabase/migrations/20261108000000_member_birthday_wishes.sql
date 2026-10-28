create table member_birthday_wishes (
  association_id uuid not null references associations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  birthday_year integer not null,
  claimed_at timestamptz not null default now(),
  primary key (association_id, user_id, birthday_year)
);
alter table member_birthday_wishes enable row level security;
create policy member_birthday_wishes_read_self on member_birthday_wishes for select using (
  user_id = auth.uid() and association_id = my_association()
);

create function claim_member_birthday_wish() returns boolean
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  dob date;
  today_local date := timezone('Asia/Kolkata', now())::date;
  claimed boolean := false;
begin
  if a is null or auth.uid() is null then return false; end if;
  select m.date_of_birth into dob
  from memberships m
  where m.association_id = a and m.user_id = auth.uid() and m.ended_at is null
    and m.role in ('owner','resident') and m.date_of_birth is not null
  order by m.date_of_birth
  limit 1;
  if dob is null or (extract(month from dob), extract(day from dob)) is distinct from
      (extract(month from today_local), extract(day from today_local)) then
    return false;
  end if;
  insert into member_birthday_wishes (association_id,user_id,birthday_year)
  values (a,auth.uid(),extract(year from today_local)::integer)
  on conflict do nothing
  returning true into claimed;
  return coalesce(claimed,false);
end $$;
revoke all on function claim_member_birthday_wish() from public;
grant execute on function claim_member_birthday_wish() to authenticated;
