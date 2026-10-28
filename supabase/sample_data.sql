-- Sample records for the demo association: a month fully collected, a partly paid month, unpaid dues, and marketplace posts.
-- Safe to re-run. Run in the Supabase SQL editor after at least one user has signed in (records need a profile as the recorder).

insert into dues (association_id, flat_id, head, amount, due_date, created_by)
select f.association_id, f.id, h.head, round(f.sqft * 3.0)::int, h.due_date, p.id
from flats f
cross join (select id from profiles order by created_at limit 1) p
cross join (values ('Maintenance Sep 2026', date '2026-09-10'), ('Maintenance Oct 2026', date '2026-10-10')) as h(head, due_date)
where f.association_id = '00000000-0000-0000-0000-000000000001' and f.sqft is not null
on conflict (flat_id, head) do nothing;

-- September: collected from every flat except A-204 and C-302 (overdue). October: A-101 and B-102 paid, A-203 half paid, rest pending.
insert into payments (association_id, flat_id, due_id, amount, paid_on, mode, reference, recorded_by)
select d.association_id, d.flat_id, d.id,
  case when d.head = 'Maintenance Oct 2026' and f.number = 'A-203' then d.amount / 2 else d.amount end,
  case when d.head = 'Maintenance Sep 2026' then date '2026-09-08' else date '2026-10-08' end,
  case when f.number in ('A-101', 'B-102', 'C-401') then 'upi' else 'cash' end,
  'SAMPLE-' || d.id, p.id
from dues d
join flats f on f.id = d.flat_id
cross join (select id from profiles order by created_at limit 1) p
where d.association_id = '00000000-0000-0000-0000-000000000001'
  and ((d.head = 'Maintenance Sep 2026' and f.number not in ('A-204', 'C-302'))
    or (d.head = 'Maintenance Oct 2026' and f.number in ('A-101', 'B-102', 'A-203')))
  and not exists (select 1 from payments x where x.reference = 'SAMPLE-' || d.id);

insert into marketplace_posts (association_id, post_type, title, description, price, contact, created_by, created_by_name)
select '00000000-0000-0000-0000-000000000001', v.t, v.title, v.d, v.price, v.c, p.id, 'Sample owner'
from (values
  ('for_sale', 'Dining table with 6 chairs', 'Teak, 3 years old, good condition.', 18000, '98470 00001'),
  ('wanted', 'Looking for a used treadmill', 'Preferably foldable.', null, '98470 00002'),
  ('service_recommendation', 'Reliable AC service technician', 'Prompt and fairly priced.', null, '98470 00003')
) as v(t, title, d, price, c)
cross join (select id from profiles order by created_at limit 1) p
where not exists (
  select 1 from marketplace_posts m
  where m.association_id = '00000000-0000-0000-0000-000000000001' and m.title = v.title
);
