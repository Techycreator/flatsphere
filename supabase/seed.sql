-- Demo association for the beta. Safe to re-run.
insert into associations (id, name, state, city) values
  ('00000000-0000-0000-0000-000000000001', 'Green Meadows Apartment Owners Association', 'Kerala', 'Kochi')
on conflict (id) do nothing;

insert into flats (association_id, number, block, flat_type, sqft, occupancy) values
  ('00000000-0000-0000-0000-000000000001', 'A-101', 'A', '3BHK', 1450, 'owner_occupied'),
  ('00000000-0000-0000-0000-000000000001', 'A-102', 'A', '2BHK', 1080, 'rented'),
  ('00000000-0000-0000-0000-000000000001', 'A-203', 'A', '2.5BHK', 1250, 'owner_occupied'),
  ('00000000-0000-0000-0000-000000000001', 'A-204', 'A', '2BHK', 1080, 'vacant'),
  ('00000000-0000-0000-0000-000000000001', 'B-102', 'B', '3BHK', 1450, 'owner_occupied'),
  ('00000000-0000-0000-0000-000000000001', 'B-205', 'B', '2BHK', 1080, 'rented'),
  ('00000000-0000-0000-0000-000000000001', 'B-301', 'B', '2.5BHK', 1250, 'owner_occupied'),
  ('00000000-0000-0000-0000-000000000001', 'C-204', 'C', '3BHK', 1450, 'owner_occupied'),
  ('00000000-0000-0000-0000-000000000001', 'C-302', 'C', '2BHK', 1080, 'rented'),
  ('00000000-0000-0000-0000-000000000001', 'C-401', 'C', '3BHK', 1450, 'owner_occupied')
on conflict (association_id, number) do nothing;

insert into invites (association_id, email, full_name, role, flat_id, designations)
select '00000000-0000-0000-0000-000000000001', 'ajeeshg99@gmail.com', 'Ajeesh G', r.role::app_role,
       case when r.role = 'owner' then (select id from flats where number = 'A-101') end,
       case when r.role = 'ec_member' then array['Membership desk'] else '{}' end
from (values ('president'), ('secretary'), ('treasurer'), ('vice_president'), ('joint_secretary'),
             ('joint_treasurer'), ('ec_member'), ('owner')) as r(role)
where not exists (select 1 from invites where lower(email) = 'ajeeshg99@gmail.com');

insert into invites (association_id, email, full_name, role, monitor_categories)
select '00000000-0000-0000-0000-000000000001', 'ajeeshg99@gmail.com', 'Ajeesh G', 'monitor', array['STP','Gym','Cleaning']
where not exists (select 1 from invites where lower(email) = 'ajeeshg99@gmail.com' and role = 'monitor');
