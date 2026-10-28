# Supabase Backup and Restore

## Scope

A `supabase db dump` is a SQL backup of database schemas/data selected by the CLI. It is not a complete FlatSphere backup: Supabase Auth users and the bytes in private Storage buckets (`id-proofs`, `bills`, `checklist-proofs`, `staff-proofs`, `housekeeping-proofs`, `community-event-photos`, and `association-documents`) need separate provider-level backup coverage.

For production, enable the Supabase project's managed backups/PITR for the plan in use, and separately copy private Storage objects to an encrypted, access-controlled destination. Keep the database dump, object manifest, and storage snapshot under the same backup ID and retention policy. Never publish these files or commit them to Git.

## SQL Snapshot (PowerShell)

Run from the repository root. Enter the database connection string at the prompt; do not put it in a command, source file, or shell history.

```powershell
$secureUrl = Read-Host "Supabase database URL" -AsSecureString
$env:SUPABASE_DB_URL = [System.Net.NetworkCredential]::new("", $secureUrl).Password
New-Item -ItemType Directory -Force backups | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
npx supabase db dump --db-url $env:SUPABASE_DB_URL --file "backups/flatsphere-$stamp.sql"
Remove-Item Env:SUPABASE_DB_URL
```

The dump may contain association member details and private application records. Restrict filesystem access and encrypt it at rest and in transit.

## Restore Procedure

1. Prefer Supabase's managed point-in-time/project restore for production recovery.
2. For a logical SQL restore, use a separate, empty staging project with the same Postgres major version. Do not restore over production or an existing populated project.
3. Restore only after reviewing the SQL dump's schemas and ownership commands. Use the staging project's database connection string in a secure terminal prompt and a database tool compatible with the dump, such as `psql` with `ON_ERROR_STOP` enabled.
4. Restore the matching private Storage object snapshot and verify object paths against the database rows before any cutover.
5. Validate authentication, association isolation/RLS, private document access, and key workflows in staging before selecting a production recovery plan.

`npx supabase db reset` is for local development and can destroy data. Do not use it to restore a remote or production project.

## Free-plan nightly backup (GitHub Actions)

`.github/workflows/backup-supabase.yml` runs at 02:00 IST and stores an encrypted `pg_dump` (schemas `public`, `auth`, `storage` metadata) as a private artifact for 30 days. Storage files themselves are not included.

Restore into a **new/test** project only:

```bash
gpg -d flatsphere-YYYY-MM-DD.dump.gpg > backup.dump
pg_restore --no-owner --no-privileges -d "<target connection string>" backup.dump
```
