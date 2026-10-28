-- SOS / panic button: alerts security and committee in the open association (in-app + push via existing trigger).
create function raise_sos(p_note text default '') returns int
language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  n int;
begin
  if a is null or not is_member(a) then raise exception 'not_allowed: members only'; end if;
  if exists (select 1 from app_notifications where association_id = a and event_key like 'sos:' || auth.uid() || ':%'
             and created_at > now() - interval '2 minutes') then
    raise exception 'invalid: SOS already sent, help has been alerted';
  end if;
  insert into app_notifications (association_id, user_id, event_key, title, body, action_path)
  select distinct a, m.user_id, 'sos:' || auth.uid() || ':' || gen_random_uuid(), 'SOS – emergency alert',
         left(coalesce(auth.jwt()->>'email', 'A member') || ' needs help now. '
              || coalesce((select string_agg(f.number, ', ') from memberships mm join flats f on f.id = mm.flat_id
                           where mm.association_id = a and mm.user_id = auth.uid() and mm.ended_at is null), '')
              || ' ' || coalesce(trim(p_note), ''), 1000), '/visitors'
  from memberships m
  where m.association_id = a and m.ended_at is null and m.user_id <> auth.uid()
    and m.role = any(array['security','caretaker','admin','president','secretary']::app_role[]);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function raise_sos(text) from public, anon;
grant execute on function raise_sos(text) to authenticated;
