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

-- PUBLIC holds a default EXECUTE grant too; move it to signed-in users only.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prorettype <> 'trigger'::regtype loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    if f.proname not in ('refresh_membership_payment_gate','seed_workflow_catalog','notify_vendor_amc_renewals',
                         'meeting_audience','notify_meeting_reminders','notify_expiry_alerts') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
