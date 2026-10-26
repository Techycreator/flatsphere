-- Security: internal helpers must not be callable through the API.
-- refresh_membership_payment_gate could flip any association's membership-change status (payment gate bypass);
-- seed_workflow_catalog / notify_vendor_amc_renewals could write into any association.
revoke execute on function refresh_membership_payment_gate(uuid) from public, anon, authenticated;
revoke execute on function seed_workflow_catalog(uuid) from public, anon, authenticated;
revoke execute on function notify_vendor_amc_renewals() from public, anon, authenticated;

-- Logged-out callers never need security-definer RPCs (login is email OTP via Supabase Auth).
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prorettype <> 'trigger'::regtype loop
    execute format('revoke execute on function %s from anon', f.sig);
  end loop;
end $$;
alter default privileges in schema public revoke execute on functions from anon;
