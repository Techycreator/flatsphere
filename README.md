# FlatSphere

Apartment association management for Indian housing associations: role-based views, multi-association isolation, maker-checker approvals, complaints with SLA, caretaker checklist, dues and payments, expenses, meetings/minutes, and community operations.

One Flutter codebase for **web + PWA** (current beta), **Android** and **iOS** (later).

> Status: Supabase-backed application with demo mode. Supabase migrations are managed from `supabase/migrations`.

## Run locally

Requires Flutter (stable, 3.47+).

```bash
flutter pub get
flutter run -d chrome          # dev
flutter build web --release    # production build in build/web (installable PWA)
flutter test
flutter analyze
```

When Supabase build-time settings are absent, the login screen runs in demo mode. With Supabase configured, users sign in with an email OTP and their active association memberships determine available roles.

## Supabase

From the repository root, check migration status and apply pending migrations to the linked project:

```powershell
npx supabase migration list
npx supabase db push
```

Back up production before applying migrations. Do not use `supabase db reset` against a remote project. See [Supabase backup and restore](docs/supabase-backup-restore.md) for recovery scope and staging guidance.

## Structure

```
lib/
  app/          theme, router (go_router), role-based navigation
  backend/      Supabase repositories and upload preparation
  models/       domain models, SLA policy + AI criticality stub
  state/        Riverpod providers and demo data
  features/     auth, shell, dashboard, complaints, checklist, approvals, finance, meetings, notices, community operations
  l10n/         ARB translation files (English, Malayalam)
  widgets/      shared UI components
supabase/
  migrations/   association-isolated schema and database workflows
web/            PWA manifest, icons, service worker (sw.js)
```

## Languages

Strings live in `lib/l10n/app_*.arb`. Add a new language by adding `app_<code>.arb` and running `flutter gen-l10n`. Malayalam coverage is partial and needs review by a native speaker.

## Requirements coverage

Implemented in the current application:

- Email OTP sign-in, invite-based association membership, and first-time self-service association creation with the creator as Admin.
- Association-scoped roles and route guards, role-specific dashboards, directory and flat management, monitor assignments with areas/dates, and staff attendance.
- Complaint intake, severity/SLA tracking, assignment and approvals; checklist workflows; notices; meeting scheduling, RSVPs and minutes.
- Finance ledger, flat dues, per-square-foot charges, fixed late fees, receipts, expenses with bill attachments, fund requests, annual budgets and three-stage monthly statement approvals.
- Community events, MOM actions and Marketplace. Owners can post all current post types; Caretakers can post service recommendations.
- Association-configurable family login-age and dependent-count rules. Family DOBs are separated from the general directory, redacted from manager directory results, and restricted by database policies. ID-document reads are limited by office-bearer, requester/owner and assigned-approver policy; Admins can configure broad access for eligible office bearers and Membership Desk POCs.
- In-app notices, vehicle lookup/export, optional member DOB age classification, birthday wishes, archive search, and private proof/document storage.

## Not implemented or not fully verified

- Android/iOS release readiness: signing, store metadata, platform-specific auth/deep-link verification and release-device testing remain deferred.
- Automated online payment collection/provider integration. In backend mode, residents pay the association outside the app and an authorized Treasurer records the receipt; demo payment is simulated only.
- Automatic recurring monthly dues or late-fee scheduling. Dues and fixed late fees are raised manually; paid charges remain in the ledger and are excluded from pending totals.
- Full operational backup/restore in the app. The documented recovery runbook relies on Supabase backups and separately managed Storage backups.
- Independent penetration testing and exhaustive multi-account Supabase integration tests. Local Flutter tests/builds and read-only role-route smoke checks do not replace staging tests with dedicated accounts for every role.

## Verification

The widget/unit suite covers representative positive and negative behavior, including route guards, email/phone/vehicle validation, family age/count boundaries, and selected role-specific screens. Run `flutter test`, `flutter analyze`, and `flutter build web --release` before release. Analyzer currently has no compile errors but reports existing lint/info findings; live Supabase mutation flows require a controlled staging association for end-to-end verification.
