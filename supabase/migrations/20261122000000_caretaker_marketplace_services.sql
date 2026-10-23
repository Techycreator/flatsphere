-- Caretakers may publish service recommendations; owners retain all marketplace post types.
drop policy marketplace_insert on marketplace_posts;
create policy marketplace_insert on marketplace_posts for insert with check (
  association_id=my_association() and created_by=auth.uid() and (
    has_role(association_id,array['owner']::app_role[])
    or (post_type='service_recommendation' and has_role(association_id,array['caretaker']::app_role[]))
  )
);
