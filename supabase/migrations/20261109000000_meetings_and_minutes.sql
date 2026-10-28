create table association_meetings (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  meeting_type text not null check (meeting_type in ('Executive Committee','Office bearers','Staff meeting','General Body')),
  title text not null check (length(trim(title)) between 1 and 180),
  starts_at timestamptz not null,
  meeting_mode text not null check (meeting_mode in ('inPerson','online','hybrid')),
  platform text,
  venue text,
  agenda jsonb not null default '[]'::jsonb check (jsonb_typeof(agenda)='array'),
  invited_count integer not null default 0 check (invited_count >= 0),
  minutes_text text,
  minutes_status text check (minutes_status in ('draft','pending_approval','approved')),
  minutes_updated_by uuid references profiles(id),
  minutes_approved_by uuid references profiles(id),
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index association_meetings_date_idx on association_meetings (association_id, starts_at);
alter table association_meetings enable row level security;
create policy association_meetings_read on association_meetings for select using (
  association_id=my_association() and is_member(association_id)
  and (meeting_type='General Body' or has_role(association_id,
    array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor']::app_role[]))
);

create table meeting_rsvps (
  meeting_id uuid not null references association_meetings(id) on delete cascade,
  association_id uuid not null references associations(id) on delete cascade,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  status text not null check (status in ('accepted','tentative','declined')),
  responded_at timestamptz not null default now(),
  primary key (meeting_id,user_id)
);
alter table meeting_rsvps enable row level security;
create policy meeting_rsvps_read on meeting_rsvps for select using (
  association_id=my_association() and (user_id=auth.uid() or has_role(association_id,
    array['admin','president','secretary','vice_president','joint_secretary','joint_treasurer','ec_member']::app_role[]))
);

create function create_association_meeting(
  p_type text,p_title text,p_starts_at timestamptz,p_mode text,p_platform text,p_venue text,p_agenda jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association(); meeting_id uuid; audience_count integer;
begin
  if a is null or not has_role(a,array['admin','president','secretary']::app_role[]) then
    raise exception 'not_allowed: Admin, President or Secretary access required';
  end if;
  if p_type not in ('Executive Committee','Office bearers','Staff meeting','General Body') then raise exception 'invalid: unsupported meeting type'; end if;
  if coalesce(trim(p_title),'')='' or p_starts_at is null or p_starts_at<now() then raise exception 'invalid: enter a title and a future date'; end if;
  if p_mode not in ('inPerson','online','hybrid') then raise exception 'invalid: unsupported meeting mode'; end if;
  if jsonb_typeof(coalesce(p_agenda,'[]'::jsonb))<>'array' then raise exception 'invalid: agenda must be a list'; end if;
  select count(*) into audience_count from memberships m where m.association_id=a and m.ended_at is null
    and case p_type
      when 'General Body' then m.role in ('owner','resident')
      when 'Staff meeting' then m.role in ('caretaker','security')
      when 'Office bearers' then m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer')
      else m.role in ('admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member')
    end;
  insert into association_meetings (association_id,meeting_type,title,starts_at,meeting_mode,platform,venue,agenda,invited_count,created_by)
  values (a,p_type,trim(p_title),p_starts_at,p_mode,nullif(trim(p_platform),''),nullif(trim(p_venue),''),coalesce(p_agenda,'[]'::jsonb),audience_count,auth.uid())
  returning id into meeting_id;
  insert into audit_log (association_id,actor,action,entity,entity_id,after)
  values (a,auth.uid(),'schedule_meeting','meeting',meeting_id::text,jsonb_build_object('type',p_type,'title',p_title,'starts_at',p_starts_at));
  return meeting_id;
end $$;

create function list_association_meetings()
returns table (
  id uuid,meeting_type text,title text,starts_at timestamptz,meeting_mode text,platform text,venue text,agenda jsonb,
  invited_count integer,accepted_count integer,tentative_count integer,declined_count integer,my_rsvp text,
  minutes_status text,minutes_text text
) language plpgsql stable security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not is_member(a) then raise exception 'not_allowed: association membership required'; end if;
  return query
  select m.id,m.meeting_type,m.title,m.starts_at,m.meeting_mode,m.platform,m.venue,m.agenda,m.invited_count,
    count(r.user_id) filter(where r.status='accepted')::integer,
    count(r.user_id) filter(where r.status='tentative')::integer,
    count(r.user_id) filter(where r.status='declined')::integer,
    coalesce(max(mine.status),'pending'),m.minutes_status,
    case when m.minutes_status='approved' or has_role(a,array['admin','president','secretary','joint_secretary']::app_role[])
      then m.minutes_text else null end
  from association_meetings m
  left join meeting_rsvps r on r.meeting_id=m.id and r.association_id=a
  left join meeting_rsvps mine on mine.meeting_id=m.id and mine.user_id=auth.uid()
  where m.association_id=a and (m.meeting_type='General Body' or has_role(a,
    array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor']::app_role[]))
  group by m.id
  order by m.starts_at;
end $$;

create function set_meeting_rsvp(p_meeting uuid,p_status text) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if p_status not in ('accepted','tentative','declined') then raise exception 'invalid: unsupported RSVP'; end if;
  if a is null or not exists(select 1 from association_meetings m where m.id=p_meeting and m.association_id=a) then
    raise exception 'not_found: meeting not found';
  end if;
  if not is_member(a) then raise exception 'not_allowed: association membership required'; end if;
  insert into meeting_rsvps(meeting_id,association_id,user_id,status,responded_at)
  values(p_meeting,a,auth.uid(),p_status,now())
  on conflict(meeting_id,user_id) do update set status=excluded.status,responded_at=now();
end $$;

create function save_meeting_minutes(p_meeting uuid,p_text text) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin','president','secretary']::app_role[]) then raise exception 'not_allowed'; end if;
  if coalesce(trim(p_text),'')='' or length(p_text)>30000 then raise exception 'invalid: minutes must contain text and be under 30000 characters'; end if;
  update association_meetings set minutes_text=p_text,minutes_status='draft',minutes_updated_by=auth.uid(),minutes_approved_by=null,updated_at=now()
  where id=p_meeting and association_id=a;
  if not found then raise exception 'not_found: meeting not found'; end if;
end $$;

create function submit_meeting_minutes(p_meeting uuid) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin','president','secretary']::app_role[]) then raise exception 'not_allowed'; end if;
  update association_meetings set minutes_status='pending_approval',updated_at=now()
  where id=p_meeting and association_id=a and minutes_status='draft' and minutes_text is not null;
  if not found then raise exception 'invalid: save a draft before submitting minutes'; end if;
end $$;

create function approve_meeting_minutes(p_meeting uuid) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['president']::app_role[]) then raise exception 'not_allowed: President approval required'; end if;
  update association_meetings set minutes_status='approved',minutes_approved_by=auth.uid(),updated_at=now()
  where id=p_meeting and association_id=a and minutes_status='pending_approval';
  if not found then raise exception 'invalid: minutes are not awaiting approval'; end if;
end $$;

create function reschedule_association_meeting(p_meeting uuid,p_starts_at timestamptz) returns void
language plpgsql security definer set search_path=public as $$
declare a uuid:=my_association();
begin
  if a is null or not has_role(a,array['admin','president','secretary']::app_role[]) then raise exception 'not_allowed'; end if;
  if p_starts_at is null or p_starts_at<now() then raise exception 'invalid: choose a future date'; end if;
  update association_meetings set starts_at=p_starts_at,updated_at=now() where id=p_meeting and association_id=a;
  if not found then raise exception 'not_found: meeting not found'; end if;
end $$;

revoke all on function create_association_meeting(text,text,timestamptz,text,text,text,jsonb) from public;
revoke all on function list_association_meetings() from public;
revoke all on function set_meeting_rsvp(uuid,text) from public;
revoke all on function save_meeting_minutes(uuid,text) from public;
revoke all on function submit_meeting_minutes(uuid) from public;
revoke all on function approve_meeting_minutes(uuid) from public;
revoke all on function reschedule_association_meeting(uuid,timestamptz) from public;
grant execute on function create_association_meeting(text,text,timestamptz,text,text,text,jsonb) to authenticated;
grant execute on function list_association_meetings() to authenticated;
grant execute on function set_meeting_rsvp(uuid,text) to authenticated;
grant execute on function save_meeting_minutes(uuid,text) to authenticated;
grant execute on function submit_meeting_minutes(uuid) to authenticated;
grant execute on function approve_meeting_minutes(uuid) to authenticated;
grant execute on function reschedule_association_meeting(uuid,timestamptz) to authenticated;
