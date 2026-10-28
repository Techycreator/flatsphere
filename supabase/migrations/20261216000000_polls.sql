-- Community polls: committee creates, every member votes once; results show counts only (votes are anonymous).
create table polls (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  question text not null check (length(trim(question)) between 3 and 300),
  options text[] not null check (array_length(options, 1) between 2 and 8),
  closes_at timestamptz not null,
  created_by uuid not null default auth.uid() references profiles(id),
  created_by_name text not null default coalesce(my_name(), ''),
  created_at timestamptz not null default now()
);
create table poll_votes (
  poll_id uuid not null references polls(id) on delete cascade,
  user_id uuid not null default auth.uid() references profiles(id),
  option_index int not null,
  voted_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);
alter table polls enable row level security;
alter table poll_votes enable row level security;
create policy polls_read on polls for select using (association_id = my_association() and is_member(association_id));
create policy polls_create on polls for insert with check (
  association_id = my_association() and created_by = auth.uid()
  and has_role(association_id, array['admin','president','vice_president','secretary','joint_secretary','ec_member']::app_role[]));
create policy polls_close on polls for update using (
  has_role(association_id, array['admin','president','secretary']::app_role[]) or created_by = auth.uid());
create policy poll_votes_own on poll_votes for select using (user_id = auth.uid());
grant select, insert, update on polls to authenticated;
grant select on poll_votes to authenticated;

create function cast_poll_vote(p_poll uuid, p_option int) returns void
language plpgsql security definer set search_path = public as $$
declare p polls;
begin
  select * into p from polls where id = p_poll and association_id = my_association();
  if p.id is null or not is_member(p.association_id) then raise exception 'not_found'; end if;
  if p.closes_at < now() then raise exception 'invalid: this poll has closed'; end if;
  if p_option < 0 or p_option >= array_length(p.options, 1) then raise exception 'invalid: unknown option'; end if;
  insert into poll_votes (poll_id, user_id, option_index) values (p_poll, auth.uid(), p_option);
exception when unique_violation then raise exception 'invalid: you have already voted';
end $$;

create function poll_results() returns table (poll_id uuid, option_index int, votes bigint)
language sql stable security definer set search_path = public as $$
  select v.poll_id, v.option_index, count(*) from poll_votes v join polls p on p.id = v.poll_id
  where p.association_id = my_association() and is_member(p.association_id)
  group by 1, 2;
$$;

create function notify_new_poll() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select distinct new.association_id, m.user_id, 'poll:' || new.id, 'New poll', left(new.question, 160), '/notices'
  from memberships m where m.association_id = new.association_id and m.ended_at is null and m.user_id <> new.created_by
  on conflict (association_id, user_id, event_key) do nothing;
  return new;
end $$;
create trigger polls_notify after insert on polls for each row execute function notify_new_poll();

revoke all on function cast_poll_vote(uuid, int), poll_results() from public, anon;
grant execute on function cast_poll_vote(uuid, int), poll_results() to authenticated;
