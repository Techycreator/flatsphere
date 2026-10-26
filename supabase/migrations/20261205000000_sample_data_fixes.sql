-- Completes the sample data: emergency contacts, income, and register items that the first sample migration could not insert.
do $$
declare
  a constant uuid := '00000000-0000-0000-0000-000000000001';
  uid uuid;
  rid uuid;
  v record;
begin
  select id into uid from profiles order by created_at limit 1;
  if uid is null or not exists (select 1 from associations where id = a) then return; end if;

  begin
    insert into emergency_contacts (association_id, label, contact_name, phone, category, notes, created_by)
    select a, x.label, x.name, x.phone, 'Emergency', x.notes, uid
    from (values
      ('Ambulance', 'Emergency ambulance', 'Dial 108', 'Free, 24 hours'),
      ('Police', 'Local police', 'Dial 112', 'Emergency helpline'),
      ('Fire', 'Fire and rescue', 'Dial 101', 'Emergency helpline'),
      ('Caretaker', 'Association caretaker', '98470 77777', 'Day and night shift'),
      ('Lift service', 'Lift maintenance desk', '98470 55555', 'Breakdown calls')
    ) as x(label, name, phone, notes)
    where not exists (select 1 from emergency_contacts e where e.association_id = a and e.label = x.label);
  exception when others then raise exception 'emergency contacts: %', sqlerrm; end;

  begin
    for v in select * from (values ('Parking fee', 1), ('Clubhouse rental', 2), ('Interest income', 3)) as t(name, n) loop
      continue when exists (select 1 from income_categories c where c.association_id = a and lower(c.name) = lower(v.name));
      insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role, category)
      values (a, 'APR-SMP-' || upper(substr(md5(random()::text), 1, 8)), 'W23',
        'New income category: ' || v.name, jsonb_build_object('Category', v.name), uid, 'Sample', 'treasurer', 'Income category')
      returning id into rid;
      insert into approval_steps (request_id, seq, role, name, decision, decided_by, decided_at)
      values (rid, 1, 'president', 'President', 'approved', uid, now());
      insert into income_categories (association_id, name, status, request_ref, request_id, created_by, approved_by, approved_at)
      values (a, v.name, 'active', 'SAMPLE-INC-' || v.n, rid, uid, uid, now());
    end loop;

    insert into income_entries (association_id, category_id, received_on, amount, source, description, recorded_by, recorded_by_name)
    select a, c.id, x.received, x.amount, x.source, x.descr, uid, 'Treasurer'
    from (values
      ('Parking fee', date '2026-10-05', 6000, 'Visitor parking', 'October visitor parking collection'),
      ('Clubhouse rental', date '2026-10-12', 1500, 'Flat B-102', 'Birthday party booking'),
      ('Interest income', date '2026-09-30', 4200, 'Bank', 'Quarterly savings interest')
    ) as x(cat, received, amount, source, descr)
    join income_categories c on c.association_id = a and lower(c.name) = lower(x.cat)
    where not exists (select 1 from income_entries e where e.association_id = a and e.description = x.descr);
  exception when others then raise exception 'income: %', sqlerrm; end;

  begin
    for v in select * from (values
      ('asset', 'Passenger lift - Block A', 'Lift', 'Kone Elevators', date '2023-05-01', current_date + 40, current_date + 55, null::date),
      ('asset', 'Diesel generator 125 kVA', 'Power', 'Kirloskar', date '2022-02-10', null::date, current_date + 75, null::date),
      ('insurance', 'Building fire insurance', 'Insurance', 'National Insurance', date '2025-12-01', null::date, null::date, current_date + 60),
      ('compliance', 'Fire NOC renewal', 'Safety', 'Fire and Rescue', date '2025-11-15', null::date, null::date, current_date + 30)
    ) as t(rt, name, cat, vendor, pd, we, ae, ex) loop
      continue when exists (select 1 from association_register_items r where r.association_id = a and r.name = v.name);
      insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role, category)
      values (a, 'APR-SMP-' || upper(substr(md5(random()::text), 1, 8)), 'W24',
        'Register record: ' || v.name, jsonb_build_object('Record', v.name), uid, 'Sample', 'president', 'Register record')
      returning id into rid;
      insert into approval_steps (request_id, seq, role, name, decision, decided_by, decided_at)
      values (rid, 1, 'president', 'President', 'approved', uid, now());
      insert into association_register_items (association_id, record_type, name, category, vendor, purchase_date,
        warranty_end, amc_end, expires_on, approval_request_id, status, created_by, approved_by, approved_at)
      values (a, v.rt, v.name, v.cat, v.vendor, v.pd, v.we, v.ae, v.ex, rid, 'active', uid, uid, now());
    end loop;
  exception when others then raise exception 'register items: %', sqlerrm; end;
end $$;
