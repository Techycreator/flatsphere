create table membership_transition_items (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  request_id uuid not null references approval_requests(id) on delete cascade,
  item_key text not null,
  phase text not null check (phase in ('move_out','move_in')),
  label text not null,
  required boolean not null default true,
  completed boolean not null default false,
  completed_by uuid references profiles(id),
  completed_at timestamptz,
  note text not null default '',
  created_at timestamptz not null default now(),
  unique (request_id,item_key)
);
alter table membership_transition_items enable row level security;
create policy membership_transition_items_read on membership_transition_items for select using (
  association_id=my_association() and exists (
    select 1 from membership_changes c join approval_requests r on r.id=c.request_id
    where c.request_id=membership_transition_items.request_id and c.association_id=membership_transition_items.association_id
      and (r.initiator=auth.uid() or can_manage_members(c.association_id) or owns_flat(c.flat_id::text))
  )
);

create function seed_membership_transition_items() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.change_type='resident' then
    insert into membership_transition_items (association_id,request_id,item_key,phase,label,required) values
      (new.association_id,new.request_id,'out_keys','move_out','Collect outgoing resident keys',false),
      (new.association_id,new.request_id,'out_meter','move_out','Record outgoing meter readings',false),
      (new.association_id,new.request_id,'out_access','move_out','Confirm the outgoing access transfer plan',false),
      (new.association_id,new.request_id,'in_lease','move_in','Verify lease / occupancy document',true),
      (new.association_id,new.request_id,'in_id','move_in','Verify incoming resident identity proof',true),
      (new.association_id,new.request_id,'in_contacts','move_in','Share emergency and caretaker contact details',false),
      (new.association_id,new.request_id,'in_rules','move_in','Share association rules and move-in guidance',false);
  elsif new.change_type='owner' then
    insert into membership_transition_items (association_id,request_id,item_key,phase,label,required) values
      (new.association_id,new.request_id,'owner_deed','move_in','Verify registered ownership document',true),
      (new.association_id,new.request_id,'owner_dues','move_out','Confirm outstanding dues are settled',true),
      (new.association_id,new.request_id,'owner_keys','move_in','Record key handover',false),
      (new.association_id,new.request_id,'owner_meter','move_out','Record meter readings at transfer',false);
  end if;
  return new;
end $$;
create trigger membership_change_seed_checklist after insert on membership_changes
  for each row execute function seed_membership_transition_items();

create function update_membership_transition_item(p_item uuid,p_completed boolean,p_note text default '') returns void
language plpgsql security definer set search_path=public as $$
declare
  a uuid:=my_association();
  item membership_transition_items;
  change membership_changes;
begin
  select * into item from membership_transition_items where id=p_item and association_id=a for update;
  if item.id is null then raise exception 'not_found: checklist item not found'; end if;
  select * into change from membership_changes where request_id=item.request_id and association_id=a;
  if change.request_id is null or not (
    change.created_by=auth.uid() or can_manage_members(a) or owns_flat(change.flat_id::text)
  ) then raise exception 'not_allowed: you cannot update this transition checklist'; end if;
  if exists (select 1 from approval_steps where request_id=item.request_id and decision='approved') then
    raise exception 'invalid: transition checklist is locked after approval';
  end if;
  if length(coalesce(p_note,''))>240 then raise exception 'invalid: note is too long'; end if;
  update membership_transition_items set completed=coalesce(p_completed,false),
    completed_by=case when p_completed then auth.uid() else null end,
    completed_at=case when p_completed then now() else null end,
    note=trim(coalesce(p_note,'')) where id=p_item;
  insert into audit_log (association_id,actor,action,entity,entity_id,before,after)
  values (a,auth.uid(),'update_transition_item','membership_transition_item',p_item::text,
    jsonb_build_object('completed',item.completed,'note',item.note),
    jsonb_build_object('completed',p_completed,'note',p_note));
end $$;

create function require_transition_checklist_before_final_approval() returns trigger
language plpgsql security definer set search_path=public as $$
declare request_code text;
begin
  if old.decision<>'pending' or new.decision<>'approved' then return new; end if;
  select code into request_code from approval_requests where id=new.request_id;
  if request_code not in ('W20','W21') then return new; end if;
  if exists (select 1 from approval_steps where request_id=new.request_id and id<>new.id and decision='pending') then
    return new;
  end if;
  if exists (select 1 from membership_transition_items where request_id=new.request_id and required and not completed) then
    raise exception 'invalid: complete all required move-in/move-out checklist items before final approval';
  end if;
  return new;
end $$;
create trigger membership_transition_checklist_gate before update of decision on approval_steps
  for each row execute function require_transition_checklist_before_final_approval();

create trigger archive_transition_checklist_changes after update or delete on membership_transition_items
  for each row execute function archive_row_change('membership_transition_item');