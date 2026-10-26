-- More sample complaints, maintenance tickets and enhancement requests for Sowparnika Highlands.
do $t$
declare
  a2 constant uuid := '00000000-0000-0000-0000-000000000002';
  aj uuid; ar uuid;
begin
  select id into aj from profiles where lower(email) = 'ajeeshg99@gmail.com';
  select id into ar from profiles where lower(email) = 'aryabr99@gmail.com';
  if aj is null or ar is null then return; end if;

  insert into complaints (association_id, ref, flat_id, kind, ticket_type, category, title, description, location, criticality, status,
                          is_private, estimated_cost, raised_by, raised_by_name, assignee, assignee_name, flat_number, created_at, accepted_at)
  select a2, x.ref, f.id, x.kind::report_kind, x.ttype, x.cat, x.title, x.descr, x.loc, x.crit::criticality, x.status::ticket_status,
         x.priv, x.cost, case when x.byar then ar else aj end, case when x.byar then 'Arya B R' else 'Ajeesh G' end,
         case when x.status in ('assigned','in_progress','on_hold','resolved','closed') then case when x.byar then aj else ar end end,
         case when x.status in ('assigned','in_progress','on_hold','resolved','closed') then case when x.byar then 'Ajeesh G' else 'Arya B R' end end,
         f.number, now() - (x.days || ' days')::interval,
         case when x.status in ('assigned','in_progress','on_hold','resolved','closed') then now() - ((x.days - 1) || ' days')::interval end
  from (values
    ('CMP-2026-S007', 'A-102', 'complaint', 'complaint', 'Security', 'Main gate left open at night', 'Gate not closed after 11 pm on two days.', 'Main gate', 'high', 'new', false, null, true, 2),
    ('CMP-2026-S008', 'B-101', 'complaint', 'complaint', 'Cleaning', 'Garbage not collected', 'Block B bins overflowing since Monday.', 'Block B ground floor', 'medium', 'in_progress', false, null, false, 4),
    ('CMP-2026-S009', 'C-201', 'complaint', 'maintenance', 'Plumbing', 'Overhead tank overflow', 'Tank overflows every morning.', 'Block C terrace', 'high', 'assigned', false, 3500, true, 5),
    ('CMP-2026-S010', 'A-201', 'complaint', 'complaint', 'Noise', 'Late night noise from party hall', 'Music continued after 10 pm.', 'Party hall', 'medium', 'resolved', false, null, false, 12),
    ('CMP-2026-S011', 'B-202', 'complaint', 'maintenance', 'Electrical', 'Generator not starting', 'Backup did not start during last power cut.', 'Generator room', 'critical', 'in_progress', false, 18000, true, 3),
    ('CMP-2026-S012', 'C-101', 'complaint', 'complaint', 'Parking', 'Two wheeler blocking exit', 'Bikes parked across the basement exit.', 'Basement', 'low', 'closed', false, null, false, 20),
    ('CMP-2026-S013', 'A-301', 'complaint', 'complaint', 'Pest control', 'Mosquito breeding near garden', 'Stagnant water near the garden pond.', 'Garden', 'medium', 'on_hold', false, 2500, true, 8),
    ('CMP-2026-S014', 'B-301', 'complaint', 'complaint', 'Staff conduct', 'Rude behaviour by a security guard', 'Private matter, please handle discreetly.', 'Main gate', 'medium', 'pending_review', true, null, false, 1),
    ('CMP-2026-S015', 'C-302', 'enhancement_immediate', 'complaint', 'Safety', 'Install CCTV at Block C entrance', 'No camera covers the Block C entrance.', 'Block C entrance', 'high', 'planned', false, 45000, true, 15),
    ('CMP-2026-S016', 'A-401', 'enhancement_future', 'complaint', 'Sustainability', 'Rooftop solar for common lighting', 'Reduce the monthly common electricity bill.', 'Terrace', 'low', 'new', false, 350000, false, 6),
    ('CMP-2026-S017', 'B-401', 'enhancement_immediate', 'complaint', 'Amenities', 'Add benches near the play area', 'Parents have nowhere to sit.', 'Play area', 'low', 'rejected', false, 12000, true, 25),
    ('CMP-2026-S018', 'C-402', 'complaint', 'maintenance', 'Lift', 'Lift B door sensor faulty', 'Door closes on people.', 'Block B lift', 'high', 'resolved', false, 6500, false, 10)
  ) as x(ref, flat, kind, ttype, cat, title, descr, loc, crit, status, priv, cost, byar, days)
  join flats f on f.association_id = a2 and f.number = x.flat
  where not exists (select 1 from complaints c where c.association_id = a2 and c.ref = x.ref);
end
$t$;
