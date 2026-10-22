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
