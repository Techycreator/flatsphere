# Flatsphere Handbook

Flatsphere is a web app (installable as a PWA) and mobile app that runs an apartment association: money, people, complaints, visitors, records and approvals, with an audit trail for every important action.

> **Keeping this handbook current:** every change to the application must update this file in the same commit, then run `python docs\build_handbook.py` to refresh `docs\Flatsphere_Handbook.docx`. See the *Change log* at the end.

## 1. Getting started

1. **Sign in** with the email the association registered for you. New people are invited by email; the invite is claimed at first sign-in.
2. **Accept the privacy notice** (first sign-in only).
3. **Set a device PIN** when asked. It locks the app on your device. You can change it or turn it off from the profile menu (top right).
4. **Install the app** (browser menu, Install / Add to Home Screen). When a new version is ready an *Update available* banner appears; tap **Update** when convenient. Nothing changes until you tap it.
5. **Language:** switch English / Malayalam from the profile menu.
6. **Several associations:** if you belong to more than one, switch between them from the association switcher.

The menu shows only what your role may use. Anything not listed for your role is intentionally hidden.

## 2. Who can see what

| Menu | Admin | President | Secretary | Treasurer | Jt. Treasurer | Vice Pres. | Jt. Secretary | EC member | Monitor | Owner | Resident | Caretaker | Security | Auditor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Home | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Approvals | Y | Y | Y | Y | Y | Y | Y | desk* | | consent only | | | | |
| Complaints | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | | |
| Finance | Y | Y | Y | Y | Y | Y | Y | Y | Y | | | | | Y |
| My dues / Statements | | | | | | | | | | Y | | | | |
| Checklist | | | Y | | | | Y | Y | Y | | | Y | | |
| Meetings | | Y | Y | Y | Y | Y | Y | Y | Y | Y | | | | |
| Flats & people (Directory) | Y | Y | Y | | | | Y | desk* | | | | | | |
| Family accounts | | | | | | | | | | Y | Y | | | |
| Staff attendance | Y | Y | Y | Y | Y | Y | Y | Y | Y | | | Y | | |
| Household staff | | Y | Y | Y | | Y | Y | Y | | Y | Y | Y | | |
| Visitors | Y | Y | Y | Y | Y | Y | Y | | | Y | Y | Y | Y | |
| Vehicle lookup | Y | Y | Y | Y | Y | | | Y | | | | Y | Y | |
| Registers & expiry | Y | Y | Y | Y | Y | Y | Y | | | | | | | Y |
| Amenities | Y | Y | Y | Y | Y | Y | Y | | | Y | Y | | | |
| Community | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | |
| Association documents | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | | Y | | |
| Notices | | | | | | | | | | Y | Y | Y | | |
| Association settings, Approval workflows | Y | | | | | | | | | | | | | |

\* *desk*: an EC member or monitor designated to the Membership desk also gets Approvals and Flats & people.

Office bearers ("six roles") are President, Vice President, Secretary, Joint Secretary, Treasurer and Joint Treasurer. Admin, President and Secretary also see **Data import & export** and **Audit log** in the profile menu.

## 3. Features and how to use them

### 3.1 Home
A summary for your role: open approvals, complaints, dues, upcoming meetings and notifications. Start your day here.

### 3.2 Complaints
- **Raise:** title, category, details, up to a few photos (camera or gallery), optional **voice note** (up to 3 minutes; compressed on the web). Pick the flat or common area.
- **Follow:** status moves through assigned, in progress and resolved; SLA timers show when action is overdue.
- **Close / reopen:** after resolution, the person who raised it, the President, Vice President, Secretary or Joint Secretary, or the monitor assigned to that area, can choose *Yes, close it* or *Reopen*. Closure by changing the status directly is blocked.
- **Best use:** Owners and residents raise with a photo; monitors and the Secretary assign and track; the committee reviews overdue items weekly.

### 3.3 Approvals and workflows
Money and membership decisions run through approval workflows. Each request shows who approved, who is pending and comments. Decide with Approve, Reject or Send back, always with a comment when rejecting.

| Code | Workflow | Typical path |
|---|---|---|
| W1 | Access change | Reserved; Admin assigns the approver |
| W2 | Visibility template | Secretary review, EC vote, President approval |
| W3 | Bank change | Secretary, President, EC vote, 48-hour wait |
| W12 | Fund request | Configured in Approval workflows |
| W20 | Owner change | Two approvals, move-out/move-in checklist, dues cleared, ID proofs |
| W21 | Resident (tenant) change | As W20; owner consent |
| W22 | Committee change | Configured in Approval workflows |
| W23 | Income category | Configured |
| W24 | Association register change | Configured |
| W25 | Amenity booking | Configured |
| W30 | Family member addition | Configured; raised by owner or resident |

The Admin sets who approves each configurable workflow in **Approval workflows**. When a new workflow appears, it is listed there and in this table.

### 3.4 Finance (Treasurer, Joint Treasurer, President, Secretary, Auditor and others in read mode)
- **Dues and payments:** create dues per flat, record payments, issue PDF receipts, send reminders (one per flat per day).
- **Ledger:** income and expense entries with categories; export the ledger as CSV.
- **Statements and budgets:** monthly statements and the annual budget each have their own approval chain.
- **Bank account:** the association bank details are changed only through W3.
- **Owners:** *My dues* shows what you owe and your receipts; *Statements* shows published monthly statements.
- **Best use:** record every payment the day it arrives; the Auditor reviews read-only.

### 3.5 Flats and people (Directory)
- **Add / edit a flat:** number, block, type, area, occupancy, vehicles and parking slot.
- **Retire flat:** Admin, President or Secretary, with a reason, only when no active owner or resident, no pending change and no dues remain. History is kept.
- **Add a person:** name, email, mobile, role and flat. Existing accounts get the role immediately; new emails get an invite.
- **Edit details:** designations, monitor areas and dates.
- **Remove / revoke a role:** mandatory reason; access ends at once and the flat's ID documents are archived. The last President, Secretary or Admin cannot be removed.
- **ID documents:** private; only authorised roles can view them.
- **Export flats** to CSV from the download icon.

### 3.6 Family accounts
Owners and residents request family members (W30). Approved members get their own sign-in linked to the flat.

### 3.7 Staff attendance and household staff
- **Association staff:** mark present, absent or leave each day; add staff with ID proof; deactivate when they leave.
- **View attendance** for any month or a custom period (committee, Caretaker, monitors).
- **Household staff:** owners and residents register their own helpers (ID proof, schedule).

### 3.8 Visitors and vehicles
- **Visitors:** residents and owners pre-register guests; the Security desk checks them in and out. Owners and residents see only the visitors they added; the six roles, Caretaker and Security see all.
- **Vehicle lookup:** type the number in any form. `KL07CO1074`, `KL-07-CO-1074` and `KL 07 CO 1074` all match. It searches resident vehicles and visitors.
- **Vehicle register export:** CSV for the boom-barrier system.

### 3.9 Daily checklist
- The Caretaker marks each item Yes or No, adds a **photo proof** where the item requires it, and may add a **text note** and a **voice note** (saved to the database).
- Reviewers (Secretary, Joint Secretary, monitors) see notes, play voice notes and reject items with a reason.
- The Secretary, President or Joint Secretary maintains the list of items.

### 3.10 Meetings and minutes
Schedule meetings, record RSVP, write minutes and have them approved. Action items from minutes are tracked in Community.

### 3.11 Amenities
Owners and residents request a booking (date, time, guests, notes). Every booking goes to the Secretary for approval under W25 and stays Pending and Unpaid until then. After approval, a free amenity is marked Waived automatically; a paid one is marked Paid by the Treasurer, Joint Treasurer or Secretary. Cancel before the start time if plans change.

### 3.12 Community
Events, notices, marketplace and meeting actions.
- **Marketplace:** anyone can list; only the person who listed it or the six office-bearer roles can remove an entry.
- **Meeting actions (MOM):** for the committee only.
- **Security** sees only the parts meant for the gate.

### 3.13 Registers and expiry
Vendors and AMC contracts, insurance, licences and other renewals. Alerts are sent before expiry. Keep scanned documents attached.

### 3.14 Association documents
Bylaws, minutes, certificates. Visible to the committee, monitors, Caretaker and owners; not to residents, Security or the Auditor.

### 3.15 Association settings (Admin)
Name, state, city, brand colour, fiscal year start and default due day, family-account rules, ID-document access. **Create association** adds another association. **Offboard association** closes the current one (see section 5).

### 3.16 Data import and export (Admin, President, Secretary)
See section 4.

### 3.17 Audit log (Admin, President, Secretary)
The last 300 actions: who did what and when. Entries cannot be edited or deleted.

## 4. Moving data in and out

### 4.1 One-time load when joining Flatsphere from another system
Prepare two CSV files (UTF-8, comma separated, first row = column names; Excel's *CSV UTF-8* works). Download the blank templates from **Profile menu, Data import & export**.

**Step 1: flats** (`flatsphere-flats-template.csv`)

| Column | Required | Notes |
|---|---|---|
| number | yes | e.g. A-101, unique. Existing flats with the same number are updated |
| block | no | |
| type | no | 1BHK, 2BHK, ...; default 2BHK |
| sqft | no | whole number |
| occupancy | no | owner_occupied (default), rented or vacant |
| car_number, bike_number | no | any format; spaces and dashes are ignored in lookups |
| parking_slot | no | |

**Step 2: people** (`flatsphere-people-template.csv`)

| Column | Required | Notes |
|---|---|---|
| full_name | yes | |
| email | yes | the address they will sign in with |
| role | yes | owner, resident, president, vice_president, secretary, joint_secretary, treasurer, joint_treasurer, ec_member, monitor, caretaker, security, auditor |
| mobile | no | |
| flat_number | owner/resident | must exist from step 1 |

Rules: at most 500 rows and 2 MB per file; the Admin role cannot be imported; committee and staff roles are accepted only if you are Admin, President or Secretary. People with an existing account get the role at once; others are invited (limit 400 new invites per day). The screen shows a preview with every row problem, then the result with any rejected lines, which you can fix and re-import (existing rows are skipped as duplicates).

**Not in the CSV load (do these in the app):** opening dues and balances (Finance), ID proofs (Flats & people), vendor and AMC records (Registers), documents (Association documents), staff (Staff attendance).

**Recommended order:** create the association, import flats, import people, spot-check five flats, add dues, invite office bearers last, then announce go-live.

### 4.2 Leaving Flatsphere: what you receive
**Data import & export, Export all data (ZIP)** (Admin or President):
- `csv/<table>.csv`: one UTF-8 CSV per table (flats, dues, payments, complaints, vendors, members, ...). First row = column names. Ids are UUIDs that link tables (for example `flat_id` matches `id` in `flats.csv`). Nested values are JSON text.
- `data.json`: the same data in one file.
- `README.txt`: export time, contents and row counts.

**Not in the ZIP:** uploaded files (complaint photos and voice notes, checklist proofs and notes, documents), ID proofs, the audit log and passwords. Download documents from their screens, use *Audit log* for history, and use the ledger and flats CSV buttons for ready-made spreadsheets. The nightly backup process is described in `docs\supabase-backup-restore.md`.

## 5. Onboarding and offboarding

Full step-by-step procedures are in `docs\Onboarding_Offboarding_Procedures.docx`. Summary:

| Case | Who | How |
|---|---|---|
| New owner or tenant | Owner, committee | W20 / W21 with checklist, dues clearance and ID proofs |
| Office bearer, monitor, Caretaker, Security, Auditor | President or Secretary | Add person with the role; W22 where configured |
| Leaving a role | President, Secretary or Admin | Revoke with reason; hand over keys, tasks and approvals first |
| New flat | Admin, President, Secretary | Add flat, or bulk import |
| Retire a flat | Admin, President, Secretary | No active members, no pending change, dues cleared |
| New association | Admin | Association settings, Create association; bulk import |
| Close an association | Admin | Export data first, then Offboard association: type the name and a reason. All access ends; data is retained |

## 6. Best practice by role

- **Admin:** create the association, import data, set workflows, keep at least two people holding President or Secretary, review the audit log monthly.
- **President / Vice President:** approve on time, close complaints, review the dashboard weekly.
- **Secretary / Joint Secretary:** run the directory, checklist items, complaints assignment and meeting minutes.
- **Treasurer / Joint Treasurer:** record payments daily, send reminders, publish monthly statements.
- **EC member / Monitor:** vote on approvals, inspect assigned areas, close complaints for your area, review the checklist.
- **Owner:** keep dues paid, register vehicles and household staff, raise complaints with photos, approve tenant changes for your flat.
- **Resident:** raise complaints, pre-register visitors, book amenities, add family through W30.
- **Caretaker:** finish the checklist daily with proofs and notes, mark staff attendance, watch the visitors list.
- **Security:** check visitors in and out, use vehicle lookup, nothing else.
- **Auditor:** read-only finance and registers; ask the Treasurer for clarifications.

## 7. Privacy and security

- Owner and resident personal details and ID proofs are visible only to authorised roles. Files are private and open through short-lived links.
- Everyone signs in with an email code and a device PIN; sessions end when the role is revoked.
- Every important action is recorded in the audit log.
- Never share your sign-in or PIN. Log out on shared devices.

## 8. Change log

| Date | Change | Sections |
|---|---|---|
| 2026-10-28 | Handbook created. Bulk CSV import, ZIP export, flat retirement, association offboarding, last-holder guard, checklist notes and voice notes, invite limit raised to 400/day, fixed the Audit log menu link being redirected | All |
| 2026-10-28 | The "dues reminder" banner on the owner Home now disappears as soon as the flat's dues are zero (it used to linger until the screen reloaded) | 3.1 Home |
| 2026-10-28 | Home header ("Owner view · Flat X") now shows the flat(s) held under the active role, so an owner and a resident each see their own flat(s) | 3.1 Home |
| 2026-10-28 | Amenity bookings now always follow W25 approval (previously free amenities were auto-approved and shown Waived instantly). Waived is set only after approval | 3.x Amenities |
| 2026-10-28 | Fixed a flat appearing twice in the "Add housekeeping staff" flat dropdown when the same person is both owner and resident of it | 3.x Household staff |
| 2026-10-28 | Fixed "stream not supported" when recording a voice note. Browsers now record compressed Opus/AAC; other devices record WAV. Same recorder for complaints and checklist notes | 3.2, 3.9 |
