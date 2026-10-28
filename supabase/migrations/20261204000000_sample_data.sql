-- Sample records for the demo association so every area has data. Safe to re-run; each section is skipped independently if it cannot apply.
do $$
declare
  a constant uuid := '00000000-0000-0000-0000-000000000001';
  uid uuid;
begin
  select id into uid from profiles order by created_at limit 1;
  if uid is null or not exists (select 1 from associations where id = a) then
    raise notice 'sample data skipped: sign in once and create the association first';
    return;
  end if;

  begin -- dues: September and October maintenance
    insert into dues (association_id, flat_id, head, amount, due_date, created_by)
    select f.association_id, f.id, h.head, round(f.sqft * 3.0)::int, h.due_date, uid
    from flats f
    cross join (values ('Maintenance Sep 2026', date '2026-09-10'), ('Maintenance Oct 2026', date '2026-10-10')) as h(head, due_date)
    where f.association_id = a and f.sqft is not null
    on conflict (flat_id, head) do nothing;
  exception when others then raise notice 'dues skipped: %', sqlerrm; end;

  begin -- payments: September collected except A-204 and C-302; October paid by A-101, B-102 and half by A-203
    insert into payments (association_id, flat_id, due_id, amount, paid_on, mode, reference, recorded_by)
    select d.association_id, d.flat_id, d.id,
      case when d.head = 'Maintenance Oct 2026' and f.number = 'A-203' then d.amount / 2 else d.amount end,
      case when d.head = 'Maintenance Sep 2026' then date '2026-09-08' else date '2026-10-08' end,
      case when f.number in ('A-101', 'B-102', 'C-401') then 'upi' else 'cash' end,
      'SAMPLE-' || d.id, uid
    from dues d join flats f on f.id = d.flat_id
    where d.association_id = a
      and ((d.head = 'Maintenance Sep 2026' and f.number not in ('A-204', 'C-302'))
        or (d.head = 'Maintenance Oct 2026' and f.number in ('A-101', 'B-102', 'A-203')))
      and not exists (select 1 from payments x where x.reference = 'SAMPLE-' || d.id);
  exception when others then raise notice 'payments skipped: %', sqlerrm; end;

  begin -- marketplace
    insert into marketplace_posts (association_id, post_type, title, description, price, contact, created_by, created_by_name)
    select a, v.t, v.title, v.d, v.price, v.c, uid, 'Sample owner'
    from (values
      ('for_sale', 'Dining table with 6 chairs', 'Teak, 3 years old, good condition.', 18000, '98470 00001'),
      ('wanted', 'Looking for a used treadmill', 'Preferably foldable.', null, '98470 00002'),
      ('service_recommendation', 'Reliable AC service technician', 'Prompt and fairly priced.', null, '98470 00003')
    ) as v(t, title, d, price, c)
    where not exists (select 1 from marketplace_posts m where m.association_id = a and m.title = v.title);
  exception when others then raise notice 'marketplace skipped: %', sqlerrm; end;

  begin -- emergency contacts
    insert into emergency_contacts (association_id, label, contact_name, phone, category, notes, created_by)
    select a, v.label, v.name, v.phone, 'Emergency', v.notes, uid
    from (values
      ('Ambulance', 'Emergency ambulance', '108', 'Free, 24 hours'),
      ('Police', 'Local police', '112', 'Emergency helpline'),
      ('Fire', 'Fire and rescue', '101', 'Emergency helpline'),
      ('Caretaker', 'Association caretaker', '98470 77777', 'Day and night shift'),
      ('Lift service', 'Lift maintenance desk', '98470 55555', 'Breakdown calls')
    ) as v(label, name, phone, notes)
    where not exists (select 1 from emergency_contacts e where e.association_id = a and e.label = v.label);
  exception when others then raise notice 'emergency contacts skipped: %', sqlerrm; end;

  begin -- community events
    insert into community_events (association_id, title, event_type, starts_at, ends_at, location, budget, description, status, created_by)
    select a, v.title, v.etype, v.s, v.s + interval '3 hours', v.loc, v.budget, v.d, 'scheduled', uid
    from (values
      ('Onam celebration', 'Festival', now() + interval '20 days', 'Clubhouse lawn', 25000, 'Pookalam, sadya and games for all families.'),
      ('Annual sports day', 'Sports', now() + interval '45 days', 'Parking court', 15000, 'Races and tug of war for children and adults.')
    ) as v(title, etype, s, loc, budget, d)
    where not exists (select 1 from community_events e where e.association_id = a and e.title = v.title);
  exception when others then raise notice 'community events skipped: %', sqlerrm; end;

  begin -- MOM action tracker
    insert into meeting_actions (association_id, mom_ref, title, owner_name, due_date, status, created_by)
    select a, v.mom, v.title, v.owner, v.due, v.status, uid
    from (values
      ('EC-2026-09', 'Replace corridor lights on floors 2 and 3', 'Secretary', current_date + 10, 'in_progress'),
      ('EC-2026-09', 'Collect three quotes for terrace waterproofing', 'Treasurer', current_date + 20, 'open'),
      ('EC-2026-08', 'Renew fire extinguisher AMC', 'Joint Secretary', current_date - 5, 'done')
    ) as v(mom, title, owner, due, status)
    where not exists (select 1 from meeting_actions m where m.association_id = a and m.title = v.title);
  exception when others then raise notice 'MOM actions skipped: %', sqlerrm; end;

  begin -- amenities
    insert into amenities (association_id, name, rules, fee, requires_approval, active)
    select a, v.name, v.rules, v.fee, v.appr, true
    from (values
      ('Clubhouse', 'Up to 40 guests. Clean up after use.', 500, true),
      ('Party hall', 'Music off by 10 pm.', 1000, true),
      ('Badminton court', 'Slots of one hour. Carry your own racquets.', 0, false),
      ('Gym', 'Residents above 16 years only.', 0, false)
    ) as v(name, rules, fee, appr)
    where not exists (select 1 from amenities x where x.association_id = a and x.name = v.name);
  exception when others then raise notice 'amenities skipped: %', sqlerrm; end;

  begin -- income categories and entries
    insert into income_categories (association_id, name, status, created_by, approved_by, approved_at)
    select a, v.name, 'active', uid, uid, now()
    from (values ('Parking fee'), ('Clubhouse rental'), ('Interest income')) as v(name)
    where not exists (select 1 from income_categories c where c.association_id = a and lower(c.name) = lower(v.name));

    insert into income_entries (association_id, category_id, received_on, amount, source, description, recorded_by, recorded_by_name)
    select a, c.id, v.received, v.amount, v.source, v.descr, uid, 'Treasurer'
    from (values
      ('Parking fee', date '2026-10-05', 6000, 'Visitor parking', 'October visitor parking collection'),
      ('Clubhouse rental', date '2026-10-12', 1500, 'Flat B-102', 'Birthday party booking'),
      ('Interest income', date '2026-09-30', 4200, 'Bank', 'Quarterly savings interest')
    ) as v(cat, received, amount, source, descr)
    join income_categories c on c.association_id = a and lower(c.name) = lower(v.cat)
    where not exists (select 1 from income_entries e where e.association_id = a and e.description = v.descr);
  exception when others then raise notice 'income skipped: %', sqlerrm; end;

  begin -- assets, insurance and compliance records with upcoming expiries
    insert into association_register_items (association_id, record_type, name, category, vendor, purchase_date,
      warranty_end, amc_end, expires_on, status, created_by, approved_by, approved_at)
    select a, v.rt, v.name, v.cat, v.vendor, v.pd, v.we, v.ae, v.ex, 'active', uid, uid, now()
    from (values
      ('asset', 'Passenger lift - Block A', 'Lift', 'Kone Elevators', date '2023-05-01', current_date + 40, current_date + 55, null::date),
      ('asset', 'Diesel generator 125 kVA', 'Power', 'Kirloskar', date '2022-02-10', null::date, current_date + 75, null::date),
      ('insurance', 'Building fire insurance', 'Insurance', 'National Insurance', date '2025-12-01', null::date, null::date, current_date + 60),
      ('compliance', 'Fire NOC renewal', 'Safety', 'Fire and Rescue', date '2025-11-15', null::date, null::date, current_date + 30)
    ) as v(rt, name, cat, vendor, pd, we, ae, ex)
    where not exists (select 1 from association_register_items r where r.association_id = a and r.name = v.name);
  exception when others then raise notice 'register items skipped: %', sqlerrm; end;

  begin -- complaints
    insert into complaints (association_id, ref, flat_id, category, title, description, criticality, status, raised_by, raised_by_name, flat_number)
    select a, v.ref, f.id, v.cat, v.title, v.descr, v.crit::criticality, v.status::ticket_status, uid, 'Sample owner', f.number
    from (values
      ('CMP-2026-9001', 'A-101', 'Plumbing', 'Water leakage in bathroom ceiling', 'Seepage from the flat above since two days.', 'high', 'assigned'),
      ('CMP-2026-9002', 'B-102', 'Electrical', 'Corridor light not working', 'Third floor corridor light is out.', 'medium', 'new'),
      ('CMP-2026-9003', 'C-401', 'Lift', 'Lift stops between floors', 'Happens mostly in the evening.', 'critical', 'in_progress'),
      ('CMP-2026-9004', 'A-203', 'Housekeeping', 'Staircase not cleaned', 'Needs cleaning on weekends.', 'low', 'resolved')
    ) as v(ref, flat, cat, title, descr, crit, status)
    join flats f on f.association_id = a and f.number = v.flat
    where not exists (select 1 from complaints c where c.association_id = a and c.ref = v.ref);
  exception when others then raise notice 'complaints skipped: %', sqlerrm; end;

  begin -- meetings
    insert into association_meetings (association_id, meeting_type, title, starts_at, meeting_mode, platform, venue, agenda, invited_count, created_by)
    select a, v.mt, v.title, v.s, v.mode, v.platform, v.venue, v.agenda::jsonb, v.inv, uid
    from (values
      ('Executive Committee', 'Monthly EC meeting', now() + interval '6 days', 'hybrid', 'Google Meet', 'Clubhouse', '["Minutes of last meeting","Finance review","Pending complaints"]', 12),
      ('General Body', 'Annual General Body meeting', now() + interval '40 days', 'inPerson', null, 'Clubhouse hall', '["Annual accounts","Budget 2026-27","Elections"]', 80)
    ) as v(mt, title, s, mode, platform, venue, agenda, inv)
    where not exists (select 1 from association_meetings m where m.association_id = a and m.title = v.title);
  exception when others then raise notice 'meetings skipped: %', sqlerrm; end;
end $$;
