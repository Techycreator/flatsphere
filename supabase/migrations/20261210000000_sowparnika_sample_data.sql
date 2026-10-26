-- Sample data: Sowparnika Highlands (first association) with full records, and both test users holding all roles in both associations.
do $t$
declare
  a1 constant uuid := '00000000-0000-0000-0000-000000000001';
  a2 constant uuid := '00000000-0000-0000-0000-000000000002';
  aj uuid; ar uuid; oth uuid; rid uuid; sid uuid;
  v record; r text; fid uuid;
  owners text[] := array['Anil Kumar','Meera Nair','Rajesh Menon','Sunitha Pillai','Thomas Kurian','Lakshmi Iyer','Vinod Varghese',
    'Deepa Krishnan','Suresh Babu','Anitha Nair','George Mathew','Priya Raghavan','Mohammed Ashraf','Reshmi Das','Joseph Thomas',
    'Kavitha Menon','Biju Philip','Sheela George','Ramesh Chandran','Nisha Joseph','Arun Prasad','Divya Mohan'];
  tenants text[] := array['Rahul Sharma','Fatima Khan','Karthik Reddy','Pooja Verma','Naveen Rao','Sneha Kulkarni','Imran Sheikh','Anjali Gupta'];
  workers text[] := array['Lalitha K','Saraswathi P','Mini Joseph','Kamala Devi','Radha S','Beena Thomas','Usha Kumari','Valsala M','Girija N','Santha R'];
begin
  select id into aj from profiles where lower(email) = 'ajeeshg99@gmail.com';
  select id into ar from profiles where lower(email) = 'aryabr99@gmail.com';
  select id into oth from profiles where id not in (aj, ar) order by created_at limit 1;
  if aj is null or ar is null or oth is null then raise exception 'sample data: required profiles are missing'; end if;

  begin -- association and catalogue
    insert into associations (id, name, state, city) values (a2, 'Sowparnika Highlands', 'Kerala', 'Kochi') on conflict (id) do nothing;
    insert into workflow_types (association_id, code, version, name, description, requires_mom, active)
    select a2, t.code, t.version, t.name, t.description, t.requires_mom, t.active from workflow_types t
    where t.association_id = a1 and not exists (select 1 from workflow_types x where x.association_id = a2 and x.code = t.code and x.version = t.version);
    delete from workflow_type_steps where workflow_type_id in (select id from workflow_types where association_id = a2 and code = 'W3');
    insert into workflow_type_steps (workflow_type_id, step_no, label, role_required, alternate_role, action_type, mandatory, config)
    select n.id, s.step_no, s.label, s.role_required, s.alternate_role, s.action_type, s.mandatory, s.config
    from workflow_types o join workflow_type_steps s on s.workflow_type_id = o.id
    join workflow_types n on n.association_id = a2 and n.code = o.code and n.version = o.version
    where o.association_id = a1 and not exists (select 1 from workflow_type_steps z where z.workflow_type_id = n.id and z.step_no = s.step_no);
    insert into bank_accounts (association_id, bank_name, branch, account_name, account_number, ifsc, is_sample)
    select a2, 'Federal Bank', 'Edappally (sample)', 'Sowparnika Highlands', '000000009876', 'FDRL0000000', true
    where not exists (select 1 from bank_accounts where association_id = a2 and status = 'active');
  exception when others then raise exception 'section association: %', sqlerrm; end;

  begin -- flats
    insert into flats (association_id, number, block, flat_type, sqft, occupancy)
    select a2, b || '-' || fl || '0' || u, b, case when u = 1 then '2BHK' else '3BHK' end, case when u = 1 then 1080 else 1450 end,
      (case ((ascii(b) - 64) + fl * 2 + u) % 4 when 0 then 'rented' when 1 then 'vacant' else 'owner_occupied' end)::occupancy
    from unnest(array['A', 'B', 'C']) b, generate_series(1, 4) fl, generate_series(1, 2) u
    on conflict (association_id, number) do nothing;
    update flats set occupancy = 'owner_occupied' where association_id = a2 and number in ('A-101', 'A-102');
  exception when others then raise exception 'section flats: %', sqlerrm; end;

  begin -- both users hold every role in both associations
    delete from user_association_context where user_id in (aj, ar);
    for r in select unnest(array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer',
        'ec_member','monitor','owner','resident','caretaker','security','auditor']) loop
      for v in select * from (values (a1, aj), (a1, ar), (a2, aj), (a2, ar)) as x(assoc, uid) loop
        if exists (select 1 from memberships m where m.association_id = v.assoc and m.user_id = v.uid and m.role = r::app_role and m.ended_at is null) then continue; end if;
        fid := null;
        if r in ('owner', 'resident') then
          if v.assoc = a2 then
            select id into fid from flats where association_id = a2 and number = case when v.uid = aj then 'A-101' else 'A-102' end;
          else
            select m.flat_id into fid from memberships m where m.association_id = a1 and m.user_id = v.uid and m.role = 'owner' and m.ended_at is null limit 1;
          end if;
          if fid is null then continue; end if;
        end if;
        insert into memberships (association_id, user_id, role, flat_id, contact_phone, monitor_categories, monitor_from, monitor_until, assigned_by, started_at)
        values (v.assoc, v.uid, r::app_role, fid, case when r in ('owner', 'resident') then case when v.uid = aj then '98470 12345' else '98470 54321' end end,
          case when r = 'monitor' then array['STP', 'Gym', 'Cleaning'] else '{}'::text[] end,
          case when r = 'monitor' then current_date end, case when r = 'monitor' then current_date + 365 end,
          case when r = 'monitor' then 'President' end,
          case when v.assoc = a2 then timestamptz '2026-10-01' else now() end);
      end loop;
    end loop;
  exception when others then raise exception 'section roles: %', sqlerrm; end;

  begin -- owners and tenants (invited members, no logins)
    insert into invites (association_id, email, full_name, role, flat_id, invited_by, mobile)
    select a2, lower(translate(owners[((x.rn - 1) % array_length(owners, 1)) + 1], ' ', '.')) || '.' || lower(replace(x.number, '-', '')) || '@sowparnika.example',
      owners[((x.rn - 1) % array_length(owners, 1)) + 1], 'owner', x.id, aj, '98470' || lpad((x.rn * 137)::text, 5, '0')
    from (select id, number, row_number() over (order by number) rn from flats where association_id = a2 and number not in ('A-101', 'A-102')) x
    where not exists (select 1 from invites i where i.association_id = a2 and i.flat_id = x.id and i.role = 'owner');
    insert into invites (association_id, email, full_name, role, flat_id, invited_by, mobile)
    select a2, lower(translate(tenants[((x.rn - 1) % array_length(tenants, 1)) + 1], ' ', '.')) || '.' || lower(replace(x.number, '-', '')) || '@sowparnika.example',
      tenants[((x.rn - 1) % array_length(tenants, 1)) + 1], 'resident', x.id, aj, '99460' || lpad((x.rn * 211)::text, 5, '0')
    from (select id, number, row_number() over (order by number) rn from flats where association_id = a2 and occupancy = 'rented') x
    where not exists (select 1 from invites i where i.association_id = a2 and i.flat_id = x.id and i.role = 'resident');
  exception when others then raise exception 'section members: %', sqlerrm; end;

  begin -- cars and bikes
    insert into flat_vehicles (association_id, flat_id, vehicle_type, registration_number, parking_slot)
    select a2, x.id, 'car', 'KL-07-' || chr((65 + x.rn % 26)::int) || chr((65 + (x.rn * 7) % 26)::int) || '-' || lpad((1000 + x.rn * 37)::text, 4, '0'),
      'P-' || lpad(x.rn::text, 2, '0')
    from (select id, row_number() over (order by number) rn from flats where association_id = a2 and occupancy <> 'vacant') x
    on conflict (flat_id, vehicle_type) do nothing;
    insert into flat_vehicles (association_id, flat_id, vehicle_type, registration_number, parking_slot)
    select a2, x.id, 'bike', 'KL-07-' || chr((65 + (x.rn * 3) % 26)::int) || chr((65 + (x.rn * 5) % 26)::int) || '-' || lpad((2000 + x.rn * 53)::text, 4, '0'),
      'B-' || lpad(x.rn::text, 2, '0')
    from (select id, row_number() over (order by number) rn from flats where association_id = a2 and occupancy <> 'vacant') x
    where x.rn % 2 = 1
    on conflict (flat_id, vehicle_type) do nothing;
  exception when others then raise exception 'section vehicles: %', sqlerrm; end;

  begin -- household staff
    insert into flat_housekeeping_workers (association_id, flat_id, full_name, id_proof_path, usual_in, usual_out, resides_in_flat, created_by)
    select a2, x.id, workers[((x.rn - 1) % array_length(workers, 1)) + 1], a2::text || '/sample/worker-' || x.rn,
      time '07:30' + (x.rn % 3) * interval '30 minutes', time '10:30' + (x.rn % 3) * interval '30 minutes', x.rn % 5 = 0, aj
    from (select id, row_number() over (order by number) rn from flats where association_id = a2 and occupancy <> 'vacant') x
    where x.rn <= 10
      and not exists (select 1 from flat_housekeeping_workers w where w.flat_id = x.id);
  exception when others then raise exception 'section household staff: %', sqlerrm; end;

  begin -- association staff and attendance
    if not exists (select 1 from staff_members where association_id = a2) then
      for v in select * from (values
        ('Sindhu P', 'housekeeping', 'Block A', 'agency', 'CleanCo Services', 14500),
        ('Remani K', 'housekeeping', 'Block B', 'agency', 'CleanCo Services', 14500),
        ('Latha M', 'housekeeping', 'Block C', 'agency', 'CleanCo Services', 14500),
        ('Pradeep V', 'security', 'Main gate - day', 'agency', 'SafeGuard Security', 21000),
        ('Anwar S', 'security', 'Main gate - night', 'agency', 'SafeGuard Security', 21000),
        ('Gopalan T', 'security', 'Back gate', 'agency', 'SafeGuard Security', 19500),
        ('Sebastian J', 'stp_operator', 'Sewage treatment plant', 'association', null, 24000)
      ) as s(name, kind, area, emp, agency, salary) loop
        insert into staff_members (association_id, full_name, staff_type, area, created_by)
        values (a2, v.name, v.kind, v.area, aj) returning id into sid;
        insert into staff_private_details (staff_id, association_id, employer_type, agency_name, monthly_salary, id_proof_path)
        values (sid, a2, v.emp, v.agency, v.salary, a2::text || '/sample/staff-' || sid);
        insert into staff_attendance (association_id, staff_id, attendance_date, status, marked_by, marked_by_name)
        select a2, sid, d::date, case when extract(day from d)::int % 9 = 0 then 'absent' when extract(day from d)::int % 13 = 0 then 'leave' else 'present' end, aj, 'Ajeesh G'
        from generate_series(current_date - 9, current_date, interval '1 day') d
        on conflict do nothing;
      end loop;
    end if;
  exception when others then raise exception 'section association staff: %', sqlerrm; end;

  begin -- visitors
    if not exists (select 1 from visitor_requests where association_id = a2) then
      insert into visitor_requests (association_id, flat_id, host_id, host_name, guest_name, guest_phone, expected_arrival,
        vehicle_number, note, status, verified_by, verified_by_name, checked_in_at, checked_out_at)
      select a2, (select id from flats where association_id = a2 and number = x.flat), case when x.flat = 'A-101' then aj else ar end,
        case when x.flat = 'A-101' then 'Ajeesh G' else 'ARYA BR' end, x.guest, x.phone, now() + x.shift, x.vehicle, x.note, x.status,
        case when x.status in ('checked_in', 'checked_out') then oth end, case when x.status in ('checked_in', 'checked_out') then 'Gate security' end,
        case when x.status in ('checked_in', 'checked_out') then now() + x.shift end, case when x.status = 'checked_out' then now() + x.shift + interval '2 hours' end
      from (values
        ('A-101', 'Ravi Kumar', '9895011111', 'KL-07-CD-4567', 'Courier delivery', 'expected', interval '2 hours'),
        ('A-101', 'Maya Thomas', '9895022222', null, 'Family visit', 'checked_in', interval '-1 hour'),
        ('A-101', 'Joseph (plumber)', '9895033333', 'KL-07-BX-1234', 'Bathroom repair', 'checked_out', interval '-1 day'),
        ('A-101', 'Nair family', '9895044444', 'KL-39-AA-9001', 'Dinner guests', 'cancelled', interval '-2 days'),
        ('A-102', 'Sunil Babu', '9895055555', null, 'Friend', 'expected', interval '5 hours'),
        ('A-102', 'Delivery - Amazon', '9895066666', null, 'Parcel', 'checked_out', interval '-3 hours'),
        ('A-102', 'Dr Anjali Rao', '9895077777', 'KL-07-ZZ-7777', 'Home visit', 'checked_in', interval '-30 minutes'),
        ('A-102', 'AC technician', '9895088888', 'KL-07-MN-5550', 'Annual service', 'expected', interval '1 day')
      ) as x(flat, guest, phone, vehicle, note, status, shift);
    end if;
  exception when others then raise exception 'section visitors: %', sqlerrm; end;

  begin -- finance: dues, payments, opening balance
    insert into opening_balances (association_id, account_name, amount, as_of, entered_by)
    values (a2, 'Federal Bank current a/c', 1250000, date '2026-04-01', aj) on conflict (association_id) do nothing;
    insert into dues (association_id, flat_id, head, amount, due_date, created_by)
    select a2, f.id, h.head, case when h.fixed is null then round(f.sqft * 3.0)::int else h.fixed end, h.due, aj
    from flats f cross join (values
      ('Maintenance Sep 2026', date '2026-09-10', null::int), ('Maintenance Oct 2026', date '2026-10-10', null::int),
      ('Maintenance Nov 2026', date '2026-11-10', null::int), ('Sinking fund Q4 2026', date '2026-11-30', 1500)) as h(head, due, fixed)
    where f.association_id = a2 and f.sqft is not null
    on conflict (flat_id, head) do nothing;
    insert into payments (association_id, flat_id, due_id, amount, paid_on, mode, reference, recorded_by)
    select d.association_id, d.flat_id, d.id,
      case when d.head = 'Maintenance Oct 2026' and abs(hashtext(f.number || 'o')) % 10 = 7 then d.amount / 2 else d.amount end,
      case d.head when 'Maintenance Sep 2026' then date '2026-09-06' + abs(hashtext(f.number)) % 5
                  when 'Maintenance Oct 2026' then date '2026-10-06' + abs(hashtext(f.number || 'o')) % 5
                  else current_date - abs(hashtext(f.number || 'n')) % 6 end,
      (array['upi', 'cash', 'bank_transfer', 'cheque'])[1 + abs(hashtext(f.number || d.head)) % 4], 'SAMPLE-' || d.id, aj
    from dues d join flats f on f.id = d.flat_id
    where d.association_id = a2 and f.occupancy <> 'vacant'
      and ((d.head = 'Maintenance Sep 2026' and abs(hashtext(f.number)) % 8 <> 0)
        or (d.head = 'Maintenance Oct 2026' and abs(hashtext(f.number || 'o')) % 10 < 8)
        or (d.head = 'Maintenance Nov 2026' and abs(hashtext(f.number || 'n')) % 10 < 3)
        or (d.head = 'Sinking fund Q4 2026' and abs(hashtext(f.number || 's')) % 10 < 2))
      and not exists (select 1 from payments p where p.reference = 'SAMPLE-' || d.id);
  exception when others then raise exception 'section dues: %', sqlerrm; end;

  begin -- finance: expenses
    insert into expenses (association_id, spent_on, category, vendor, description, amount, status, entered_by, entered_by_name, verified_by, approved_by)
    select a2, x.spent, x.cat, x.vendor, x.descr, x.amount, x.status, aj, 'Ajeesh G',
      case when x.status in ('awaiting_president', 'approved') then oth end, case when x.status = 'approved' then ar end
    from (values
      (date '2026-09-28', 'Security', 'SafeGuard Security', 'Security staff - September', 61500, 'approved'),
      (date '2026-09-30', 'Housekeeping', 'CleanCo Services', 'Housekeeping contract - September', 43500, 'approved'),
      (date '2026-09-18', 'Electricity', 'KSEB', 'Common area electricity - August', 38250, 'approved'),
      (date '2026-09-12', 'Lifts', 'Kone Elevators', 'Lift AMC - quarterly', 27000, 'approved'),
      (date '2026-09-20', 'STP', 'AquaCare', 'STP chemicals and servicing', 15600, 'approved'),
      (date '2026-10-02', 'Water', 'Kochi Water Tankers', 'Water tanker supply', 9800, 'approved'),
      (date '2026-10-08', 'Garden', 'Green Touch', 'Garden maintenance - October', 12000, 'approved'),
      (date '2026-10-15', 'Generator', 'Fuel Station', 'Generator diesel', 21400, 'approved'),
      (date '2026-10-20', 'Repairs', 'Raju Plumbing', 'Plumbing repairs Block B', 7300, 'awaiting_president'),
      (date '2026-10-24', 'Security', 'SafeGuard Security', 'Security staff - October', 61500, 'awaiting_treasurer'),
      (date '2026-10-25', 'Repairs', 'Bright Electricals', 'Corridor lights replacement', 18400, 'sent_back')
    ) as x(spent, cat, vendor, descr, amount, status)
    where not exists (select 1 from expenses e where e.association_id = a2 and e.description = x.descr);
  exception when others then raise exception 'section expenses: %', sqlerrm; end;

  begin -- finance: income categories and entries
    for v in select * from (values ('Parking fee', 1), ('Clubhouse rental', 2), ('Interest income', 3)) as t(name, n) loop
      continue when exists (select 1 from income_categories c where c.association_id = a2 and lower(c.name) = lower(v.name));
      insert into approval_requests (association_id, ref, code, title, details, initiator, initiator_name, initiator_role, category)
      values (a2, 'APR-SMP-' || upper(substr(md5(random()::text), 1, 8)), 'W23', 'New income category: ' || v.name,
        jsonb_build_object('Category', v.name), aj, 'Sample', 'treasurer', 'Income category') returning id into rid;
      insert into approval_steps (request_id, seq, role, name, decision, decided_by, decided_at)
      values (rid, 1, 'president', 'President', 'approved', aj, now());
      insert into income_categories (association_id, name, status, request_ref, request_id, created_by, approved_by, approved_at)
      values (a2, v.name, 'active', 'SAMPLE-INC-' || v.n, rid, aj, aj, now());
    end loop;
    insert into income_entries (association_id, category_id, received_on, amount, source, description, recorded_by, recorded_by_name)
    select a2, c.id, x.received, x.amount, x.source, x.descr, aj, 'Treasurer'
    from (values
      ('Parking fee', date '2026-10-05', 9000, 'Visitor parking', 'October visitor parking collection'),
      ('Parking fee', date '2026-09-05', 8200, 'Visitor parking', 'September visitor parking collection'),
      ('Clubhouse rental', date '2026-10-12', 2500, 'Flat B-102', 'Birthday party booking'),
      ('Interest income', date '2026-09-30', 11800, 'Bank', 'Quarterly savings interest')
    ) as x(cat, received, amount, source, descr)
    join income_categories c on c.association_id = a2 and lower(c.name) = lower(x.cat)
    where not exists (select 1 from income_entries e where e.association_id = a2 and e.description = x.descr);
  exception when others then raise exception 'section income: %', sqlerrm; end;

  begin -- community, amenities, complaints, meetings
    insert into emergency_contacts (association_id, label, contact_name, phone, category, notes, created_by)
    select a2, x.label, x.name, x.phone, 'Emergency', x.notes, aj from (values
      ('Ambulance', 'Emergency ambulance', 'Dial 108', 'Free, 24 hours'), ('Police', 'Local police', 'Dial 112', 'Emergency helpline'),
      ('Fire', 'Fire and rescue', 'Dial 101', 'Emergency helpline'), ('Caretaker', 'Association caretaker', '98470 66666', 'Day and night shift'),
      ('Lift service', 'Lift maintenance desk', '98470 44444', 'Breakdown calls')) as x(label, name, phone, notes)
    where not exists (select 1 from emergency_contacts e where e.association_id = a2 and e.label = x.label);
    insert into amenities (association_id, name, rules, fee, requires_approval, active)
    select a2, x.name, x.rules, x.fee, x.appr, true from (values
      ('Clubhouse', 'Up to 60 guests. Clean up after use.', 800, true), ('Party hall', 'Music off by 10 pm.', 1500, true),
      ('Badminton court', 'Slots of one hour. Carry your own racquets.', 0, false), ('Swimming pool', 'Residents only. Open 6 am to 8 pm.', 0, false)) as x(name, rules, fee, appr)
    where not exists (select 1 from amenities a where a.association_id = a2 and a.name = x.name);
    insert into marketplace_posts (association_id, post_type, title, description, price, contact, created_by, created_by_name)
    select a2, x.t, x.title, x.d, x.price, x.c, aj, 'Ajeesh G' from (values
      ('for_sale', 'Sofa set 3+1+1', 'Fabric, two years old.', 22000, '98470 11001'), ('wanted', 'Looking for a study table', 'For a school student.', null, '98470 11002'),
      ('service_recommendation', 'Electrician - Babu', 'Reliable for flat wiring work.', null, '98470 11003')) as x(t, title, d, price, c)
    where not exists (select 1 from marketplace_posts m where m.association_id = a2 and m.title = x.title);
    insert into complaints (association_id, ref, flat_id, category, title, description, criticality, status, raised_by, raised_by_name, flat_number)
    select a2, x.ref, f.id, x.cat, x.title, x.descr, x.crit::criticality, x.status::ticket_status, aj, 'Ajeesh G', f.number from (values
      ('CMP-2026-S001', 'A-101', 'Plumbing', 'Water leakage in bathroom ceiling', 'Seepage from the flat above.', 'high', 'assigned'),
      ('CMP-2026-S002', 'B-201', 'Electrical', 'Corridor light not working', 'Second floor corridor light is out.', 'medium', 'new'),
      ('CMP-2026-S003', 'C-301', 'Lift', 'Lift stops between floors', 'Mostly in the evening.', 'critical', 'in_progress'),
      ('CMP-2026-S004', 'A-202', 'Housekeeping', 'Staircase not cleaned', 'Needs cleaning on weekends.', 'low', 'resolved'),
      ('CMP-2026-S005', 'B-102', 'Parking', 'Visitor car in reserved slot', 'Slot P-07 is being used by visitors.', 'medium', 'new'),
      ('CMP-2026-S006', 'C-102', 'Water', 'Low water pressure', 'Pressure drops after 7 pm.', 'high', 'assigned')) as x(ref, flat, cat, title, descr, crit, status)
    join flats f on f.association_id = a2 and f.number = x.flat
    where not exists (select 1 from complaints c where c.association_id = a2 and c.ref = x.ref);
    insert into association_meetings (association_id, meeting_type, title, starts_at, meeting_mode, platform, venue, agenda, invited_count, created_by)
    select a2, x.mt, x.title, x.s, x.mode, x.platform, x.venue, x.agenda::jsonb, x.inv, aj from (values
      ('Executive Committee', 'Monthly EC meeting', now() + interval '6 days', 'hybrid', 'Google Meet', 'Clubhouse', '["Minutes of last meeting","Finance review","Pending complaints"]', 12),
      ('General Body', 'Annual General Body meeting', now() + interval '40 days', 'inPerson', null, 'Clubhouse hall', '["Annual accounts","Budget 2026-27","Elections"]', 80)) as x(mt, title, s, mode, platform, venue, agenda, inv)
    where not exists (select 1 from association_meetings m where m.association_id = a2 and m.title = x.title);
  exception when others then raise exception 'section community: %', sqlerrm; end;
end $t$;
