# FlatSphere

Apartment association management for Indian housing associations: role-based views, maker-checker approvals, complaints with Green/Amber/Red SLA, caretaker daily checklist, dues and payments, expenses, meetings and MOM.

One Flutter codebase for **web + PWA** (current beta), **Android** and **iOS** (later).

> Status: **clickable design prototype** with in-memory demo data. No backend yet (Supabase planned).

## Run locally

Requires Flutter (stable, 3.47+).

```bash
flutter pub get
flutter run -d chrome          # dev
flutter build web --release    # production build in build/web (installable PWA)
flutter test
flutter analyze
```

On the login screen, pick a demo user (President, Secretary, Treasurer, Monitor, Owner, Resident, Caretaker, Auditor) to see that role's view. Any 6-digit OTP works for the demo mobile numbers.

## Structure

```
lib/
  app/          theme, router (go_router), role-based navigation
  models/       domain models, SLA policy + AI criticality stub
  state/        Riverpod providers and demo data
  features/     auth, shell, dashboard, complaints, checklist, approvals, finance, meetings, notices
  l10n/         ARB translation files (English, Malayalam)
  widgets/      shared UI components
web/            PWA manifest, icons, service worker (sw.js)
```

## Languages

Strings live in `lib/l10n/app_*.arb`. Add a new language by adding `app_<code>.arb` and running `flutter gen-l10n`. Malayalam translations need review by a native speaker.
