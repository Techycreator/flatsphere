-- Register records: allow an "other" type so associations can keep kinds beyond the four built-in ones.
-- For "other", the category carries the kind name (for example Licence or Lease) and expiry is optional.
alter table association_register_items drop constraint association_register_items_record_type_check;
alter table association_register_items add constraint association_register_items_record_type_check
  check (record_type in ('asset','insurance','compliance','conflict','other'));

do $$
declare body text;
begin
  select pg_get_functiondef(p.oid) into body from pg_proc p
    where p.proname = 'submit_association_register_item' and p.pronamespace = 'public'::regnamespace;
  body := replace(body, $q$p_type not in ('asset','insurance','compliance','conflict')$q$,
                        $q$p_type not in ('asset','insurance','compliance','conflict','other')$q$);
  body := replace(body, $q$if coalesce(trim(p_ref),'') = '' then$q$,
                        $q$if p_type = 'other' and coalesce(trim(p_category),'') = '' then raise exception 'invalid: enter the record kind'; end if;
  if coalesce(trim(p_ref),'') = '' then$q$);
  execute body;
end $$;
