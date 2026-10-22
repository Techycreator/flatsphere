create function can_manage_flat_housekeeping(fid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m join flats f on f.id = m.flat_id
    where m.association_id = my_association() and f.association_id = m.association_id
      and m.flat_id = fid and m.user_id = auth.uid() and m.ended_at is null
      and m.role in ('owner','resident')
  );
$$;

create table flat_housekeeping_workers (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null default my_association() references associations(id) on delete cascade,
  flat_id uuid not null references flats(id),
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  id_proof_path text not null,
  usual_in time not null,
  usual_out time not null,
  resides_in_flat boolean not null default false,
  active boolean not null default true,
  created_by uuid not null default auth.uid() references profiles(id),
  created_at timestamptz not null default now()
);
create index flat_housekeeping_workers_flat_idx on flat_housekeeping_workers (association_id, flat_id) where active;
alter table flat_housekeeping_workers enable row level security;
create policy flat_housekeeping_workers_read on flat_housekeeping_workers for select using (
  association_id = my_association() and can_manage_flat_housekeeping(flat_id)
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('housekeeping-proofs', 'housekeeping-proofs', false, 5242880, array['image/jpeg','application/pdf'])
on conflict (id) do nothing;
create policy housekeeping_proofs_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'housekeeping-proofs'
  and (storage.foldername(name))[1] = my_association()::text
  and can_manage_flat_housekeeping(((storage.foldername(name))[2])::uuid)
);
create policy housekeeping_proofs_read on storage.objects for select to authenticated using (
  bucket_id = 'housekeeping-proofs' and exists (
    select 1 from flat_housekeeping_workers w
    where w.id_proof_path = name and w.association_id = my_association()
      and can_manage_flat_housekeeping(w.flat_id)
  )
);

create function add_flat_housekeeping_worker(
  p_flat_id uuid,
  p_name text,
  p_usual_in time,
  p_usual_out time,
  p_resides_in_flat boolean,
  p_id_proof_path text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  a uuid := my_association();
  worker_id uuid;
begin
  if a is null or not can_manage_flat_housekeeping(p_flat_id) then
    raise exception 'not_allowed: only an owner or resident of this flat can add household staff';
  end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'invalid: enter the worker name'; end if;
  if p_usual_in is null or p_usual_out is null then raise exception 'invalid: enter usual arrival and departure times'; end if;
  if p_id_proof_path is null or p_id_proof_path not like a::text || '/' || p_flat_id::text || '/%' then
    raise exception 'invalid: upload the worker ID proof';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'housekeeping-proofs' and name = p_id_proof_path) then
    raise exception 'invalid: worker ID proof upload not found';
  end if;
  insert into flat_housekeeping_workers (
    association_id, flat_id, full_name, id_proof_path, usual_in, usual_out, resides_in_flat
  ) values (
    a, p_flat_id, trim(p_name), p_id_proof_path, p_usual_in, p_usual_out, coalesce(p_resides_in_flat, false)
  ) returning id into worker_id;
  insert into audit_log (association_id, actor, action, entity, entity_id, after)
  values (a, auth.uid(), 'add_housekeeping_worker', 'flat_housekeeping_worker', worker_id::text,
    jsonb_build_object('flat_id', p_flat_id, 'name', trim(p_name), 'resides_in_flat', p_resides_in_flat));
  return worker_id;
end $$;

revoke all on function add_flat_housekeeping_worker(uuid, text, time, time, boolean, text) from public;
grant execute on function add_flat_housekeeping_worker(uuid, text, time, time, boolean, text) to authenticated;