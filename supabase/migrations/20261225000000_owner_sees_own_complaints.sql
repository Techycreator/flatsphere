-- Owners and residents see only the complaints they raised themselves; committee and caretaker still see all.
drop policy complaints_read on complaints;
create policy complaints_read on complaints for select using (
  association_id = my_association() and (
    has_role(association_id, array['admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer','ec_member','monitor','caretaker']::app_role[])
    or raised_by = auth.uid()
  )
);
