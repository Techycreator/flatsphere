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
7. **Several flats:** if you own or occupy more than one flat in the association, the profile menu lists all of them, and screens that need a flat (complaints, dues, visitors, amenity bookings, household staff, family accounts) let you pick which one.

The menu shows only what your role may use. Anything not listed for your role is intentionally hidden.

## 2. Who can see what

| Menu | Admin | President | Secretary | Treasurer | Jt. Treasurer | Vice Pres. | Jt. Secretary | EC member | Monitor | Owner | Resident | Caretaker | Security | Auditor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Home | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Approvals | Y | Y | Y | Y | Y | Y | Y | desk* | | own flat + consent | own flat | | | |
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
A summary for your role: open approvals, complaints, dues, upcoming meetings and notifications. Start your day here. Updates found while the app is still loading install automatically; after the first screen appears, confirm before updating so an open form is not lost.

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

**Who starts a change:** the President, Secretary, Admin or a Membership-desk EC member starts any of W20–W22 from Approvals → *New request*. Owners can also start an owner change (sale / transfer) or a tenant change for their own flat, and residents a tenant change for theirs — from the dashboard shortcut or Approvals; the request is limited to their own flats. Committee changes (W22) remain desk-only and need approved EC minutes. A Caretaker (or Security, Auditor) change is not a workflow: the new person is added in *Flats and people*, and the outgoing role is removed there with a reason, which needs President approval before access ends.

Owner-consent steps are tied to a flat. An owner who holds several flats sees and signs the consent for whichever of their flats a request concerns, not just their first-listed flat.

### 3.4 Finance (Treasurer, Joint Treasurer, President, Secretary, Auditor and others in read mode)
- **Dues and payments:** create dues per flat, record payments, issue PDF receipts, send reminders (one per flat per day).
- **Filter the dues table** by **month** and **type** (Maintenance, Corpus fund, Lift AMC, …). The type is the part of the dues name before the dash, so "Maintenance – Nov 2026" and "Maintenance – Dec 2026" are both *Maintenance*. With a filter on, the table shows only matching flats and a collected-vs-charged summary for that slice.
- **Dues types are the Treasurer's to define:** when raising dues, type any name, or tap a category chip (previously used names plus common ones) to prefill it with the current month.
- **Bulk receive (Treasurer / Joint Treasurer):** when many flats pay the same month's dues, choose the month and type, tick the flats (or *Select all*), set one payment mode, an **optional** reference and the received date, then review a **preview** listing every flat, amount and the grand total before *Confirm & save*. The server checks each due's current balance when saving; if a balance changed after preview, that receipt is rejected and you must refresh the preview before trying again. One receipt per due is recorded and owners see theirs immediately.
- **Automatic maintenance bills:** invalid flat-type rates are rejected when saved; the schedule skips retired flats and closed associations. Late fees follow each bill's original due date, including when its grace period crosses a month, and are not charged until after that date and grace period.
- **Petty cash:** the Treasurer records cash handed to the Caretaker. The Caretaker records spends with bills for verification and approval; returned spends remain deducted from the cash balance. On Home, open a returned spend to read the reason, attach the requested bill and resubmit it. When a bill photo is read, the helper prefers the final payable total, ignores dates when guessing an unlabeled amount and skips invalid calendar dates.
- **Fund requests:** select an approved Executive Committee meeting by its meeting record, not by title alone. A Secretary or President records the EC votes from those approved minutes; every EC member, including the requester, is counted. Rejections and send-backs update the request immediately; President approval follows a successful EC vote.
- **Ledger:** income and expense entries with categories; export the ledger as CSV.
- **Statements and budgets:** monthly statements and the annual budget each have their own approval chain.
- **Bank account:** the association bank details are changed only through W3.
- **Owners:** *My dues* shows what you owe and your receipts; *Statements* shows published monthly statements.
- **Best use:** record every payment the day it arrives; the Auditor reviews read-only.

### 3.5 Flats and people (Directory)
- **Add / edit a flat:** number, block, type, area, occupancy, vehicles and parking slot.
- **Find a flat:** the Flats tab has a search box that filters by flat number or block, alongside the occupancy chips. The People tab search already covers name, email and flat.
- **Retire flat:** Admin, President or Secretary, with a reason, only when no active owner or resident, no pending change and no dues remain. History is kept.
- **Add a person:** name, email, mobile, role and flat. Existing accounts get the role immediately; new emails get an invite.
- **Edit details:** designations, monitor areas and dates. Owner/resident contact changes require a valid phone number and update the number used in the directory and at the gate. An invite cannot be changed to an email that already has an account; add that account through the directory. Profile edits preserve saved contact data when changing a name.
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
- **Visitors:** residents and owners pre-register guests; the Security desk checks them in and out. Owners and residents see visitors they added, walk-ins waiting for approval at their flats, and lobby deliveries for their flats, including after checkout; the six roles, Caretaker and Security see all. Visitor lists, approval alerts and the 30-day gate history show only the active association's requests — a host who belongs to several associations never sees one association's visitors while another is open.
- **Gate desk (Security, Caretaker, Admin, President, Secretary):** select a guard and PIN to start a shift; check visitor pass codes, request flat approval for walk-ins, call saved owner/resident contacts for flat visits, and check daily-help staff in or out. Other walk-ins require a non-empty purpose in both the form and server RPC, and the purpose appears on the flat's approval request. Staff walk-ins notify the selected staff account, even when staff share a name; staff visitor cards do not offer flat-only calling. Checkouts for offline walk-ins remain queued behind the walk-in creation. Gate shifts, guard stamps, offline caches, daily-help passes and flat choices, and the on-duty display are scoped to the active association. Queued actions retain their originating association and sync only when that association is active; offline admission times are retained when actions sync. Assigned older entries are recovered into their association queue before it is sent; unassigned entries wait for an explicit association choice. Queue syncing, queue recovery and online walk-ins are serialized with association switches. Background timer refreshes skip ticks while a load is active; explicit and association-change refreshes are coalesced and load the latest active association. Retried walk-ins keep the same request ID to avoid duplicate requests; interrupted legacy-queue recovery does not duplicate entries. Pass codes are checked against the last saved visitor list.
- **Vehicle lookup:** type the number in any form (up to 24 characters). `KL07CO1074`, `KL-07-CO-1074` and `KL 07 CO 1074` all match. It searches resident vehicles and visitors, including staff visits labelled by the staff member being met.
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
- **Caretaker:** finish the checklist daily with proofs and notes, mark staff attendance, watch the visitors list, and correct returned petty-cash expenses from Home.
- **Security:** check visitors in and out, use vehicle lookup, nothing else.
- **Auditor:** read-only finance and registers; ask the Treasurer for clarifications.

## 7. Privacy and security

- Owner and resident personal details and ID proofs are visible only to authorised roles. Files are private and open through short-lived links.
- Everyone signs in with an email code. Fingerprint or face unlock is optional and checked by the device; old PIN-only protection is retained until the next fresh email-code sign-in. Sessions end when the role is revoked.
- Every important action is recorded in the audit log.
- Never share your sign-in or PIN. Log out on shared devices.

## 8. Change log

| Date | Change | Sections |
|---|---|---|
| 2026-10-28 | Handbook created. Bulk CSV import, ZIP export, flat retirement, association offboarding, last-holder guard, checklist notes and voice notes, invite limit raised to 400/day, fixed the Audit log menu link being redirected | All |
| 2026-10-28 | App update: tapping "Update now" now switches to a full-screen "Updating FlatSphere…" spinner, clears old cached copies and restarts once. It no longer flickers or comes back repeatedly (it waits two minutes before asking again if the new version has not reached your device yet, and first-time installs no longer trigger a stray reload) | 3.1 / Technical |
| 2026-10-28 | Owners with more than one flat: "My pending dues" on Home and the My dues page now add up all your flats (they showed only the primary flat, so a reminder for another flat looked wrong). Dues-reminder notifications in the bell are removed automatically once the flat has nothing pending | 3.x Dues, Home |
| 2026-10-28 | Dashboard "Reports to review" now opens the Complaints list already filtered to "Awaiting review". EC votes now show as pending items (Dashboard count, bell, Approvals list) for EC members and office bearers, and the person who raised a request also votes: their vote counts towards the majority | 3.1 Home, Approvals, EC vote |
| 2026-10-28 | Top bar: the association name now gets more room (wraps to two lines on phones, tighter spacing, compact role chip) so more of a long name is visible | 3.1 Navigation |
| 2026-10-28 | Flagged-for-discussion expenses now do something: the President must give a reason; the committee is notified; the expense cannot be approved until the flag is resolved; the Secretary or President resolves it with a recorded decision note (audit-logged); open flags are pre-filled into the agenda when scheduling a meeting | 3.x Expenses, Meetings |
| 2026-10-28 | Receipts (Recent receipts for the Treasurer, Receipts for owners) now have a **View** (eye) button that shows the receipt on screen without downloading; Download is still available there and beside it | 3.x Dues |
| 2026-10-28 | Dues & follow-ups table is more compact (tighter column spacing and row height) so more flats and columns fit on screen without sideways scrolling | 3.x Dues & follow-ups |
| 2026-10-28 | Dropdowns across the app (for example Document type in Upload association document) now fit inside their card on phones; long options are shortened with "…" instead of spilling outside | All |
| 2026-10-28 | Vendors: "Service category" has a "+ Add new category…" option, and categories already used by your vendors are listed. Assets & records: new "Other" record type (name the kind in Category, expiry optional) for anything beyond Asset, Insurance, Compliance and Conflict of interest | 3.x Assets & records, Vendors |
| 2026-10-28 | Monthly statements: the card now uses the full width (approval status, income / expenses / payments figures, then Review details and the action), and "Review details" shows each section as an aligned table with an amount column | 3.x Statements |
| 2026-10-28 | The separate "switch association" icon in the top bar is gone. If you belong to more than one association, tap the association name (with the small arrow) at the top left to switch | 3.1 Navigation |
| 2026-10-28 | App updates no longer interrupt a critical action. While a payment (or any action wrapped in `runWithoutUpdatePrompt`) is in flight, the "Update available" screen is held back and shown right after it finishes (auto-expires after 10 minutes). Groundwork for the future payment gateway | 3.1 / Technical |
| 2026-10-28 | The "dues reminder" banner on the owner Home now disappears as soon as the flat's dues are zero (it used to linger until the screen reloaded) | 3.1 Home |
| 2026-10-28 | Home header ("Owner view · Flat X") now shows the flat(s) held under the active role, so an owner and a resident each see their own flat(s) | 3.1 Home |
| 2026-10-28 | Amenity bookings now always follow W25 approval (previously free amenities were auto-approved and shown Waived instantly). Waived is set only after approval | 3.x Amenities |
| 2026-10-28 | Fixed a flat appearing twice in the "Add housekeeping staff" flat dropdown when the same person is both owner and resident of it | 3.x Household staff |
| 2026-10-28 | Fixed "stream not supported" when recording a voice note. Browsers now record compressed Opus/AAC; other devices record WAV. Same recorder for complaints and checklist notes | 3.2, 3.9 |
| 2026-11-03 | Gate desk adds guard PIN shifts, pass-code checks, walk-in approval requests, flat calling, daily-help check-in/out, and offline action queuing with association-scoped flat suggestions. Role access is unchanged. | 3.8 |
| 2026-11-03 | Gate offline state and queued actions are association-scoped; owner/resident gate alerts show only visitors they added; vehicle lookup retains numbers up to the supported 24 characters. Feature-branch pushes no longer deploy to the shared Pages project. | 3.8, 3.x Visitors, Technical |
| 2026-11-03 | Gate queue entries are bound to their originating association, and stale in-memory gate state clears when switching associations. | 3.8 |
| 2026-11-03 | Legacy gate queue entries remain available for recovery until a user assigns them to an association. | 3.8 |
| 2026-11-03 | Gate queue syncing is serialized with association switches to prevent queued actions from running in a different association's server context. | 3.8 |
| 2026-11-03 | Owners and residents can see walk-ins awaiting approval at their flats; gate queue recovery, sending and additions are serialized; flat suggestions, disposal handling and verification feedback are corrected. | 3.8 |
| 2026-11-03 | Online gate walk-ins are bound to the active association; retried requests are idempotent and interrupted legacy-queue recovery is safe to repeat. | 3.8 |
| 2026-11-03 | Gate shifts and guard stamps are association-specific; daily-help passes and flat choices, and awaiting walk-ins, are filtered to the active association and authorized flats. | 3.8 |
| 2026-11-03 | Gate background refreshes are single-flight and coalesce pending requests while preserving refreshes after association switches. | 3.8 |
| 2026-11-03 | Gate timer refreshes skip active loads; explicit and association-change refreshes remain coalesced. | 3.8 |
| 2026-11-03 | Caretakers can review, attach bills to and resubmit returned petty-cash expenses; cash remains deducted while a spend is returned. Profile edits preserve saved contact data, directory/gate phone numbers stay in sync, and invite edits cannot target existing accounts. Automatic bills skip retired flats and closed associations, calculate cross-month late fees from each bill's due date, and resumed app sessions ask before updating. | 3.4, 3.5, Caretaker, Technical |
| 2026-11-04 | Legacy PIN protection now remains until fresh email-code sign-in; update prompts wait for the first screen, bill-photo guesses prefer final totals and valid dates, and owner/resident contact edits require a valid phone synchronized to the active association. Dues rates are validated before saving and late fees use each bill's stored due date after its grace period. | 3.1, 3.4, 3.5, 7 |
| 2026-11-04 | Fund requests now link to the exact approved EC meeting, meeting votes validate those minutes and count all EC members, rejected or returned requests update immediately, and petty-cash balances refresh correctly after top-ups or association switches. | 3.4 |
| 2026-11-04 | Bulk receipts validate each due's current balance on the server and refresh dues after a partial save; stale previews must be reviewed again. Directory search fields reset correctly when switching tabs. | 3.4, 3.5 |
| 2026-11-04 | Gate approvals show Other visit purposes; staff walk-in alerts target the selected account; offline lobby changes, admission times and visitor cache persist correctly. | 3.8 |
| 2026-11-04 | Pending walk-in checkouts queue after creation; staff visitor actions, vehicle lookup and owner/resident lobby delivery visibility are corrected, and Other visits require a purpose in the RPC. | 3.8 |
| 2026-11-04 | The gate RPC now explicitly rejects Other walk-ins with an empty or whitespace-only purpose before inserting a request. | 3.8 |
| 2026-11-04 | Owners with several flats see all their flats in the profile menu, and owner-consent approval steps are matched against every flat they own rather than only the first-listed one. | 1, 3.3 |
| 2026-11-04 | The Flats tab in Flats and people gains a search box that filters by flat number or block; the search box clears when switching tabs. | 3.5 |
| 2026-11-04 | Visitor lists and the gate history are filtered to the active association, so requests from one association no longer appear for approval or review while another association is open. | 3.8 |
| 2026-11-04 | Owners and residents can now actually start their own flat's owner/tenant change: dashboard shortcuts added, residents may open Approvals, and the New request menu offers each role only the request types it may raise. | 2, 3.1, 3.3 |
| 2026-11-04 | Finance: the dues table can be filtered by month and dues type; category chips prefill dues names when raising dues; and a bulk-receive flow lets the Treasurer tick many flats for a month's dues, with an optional reference and a full preview before saving. | 3.4 |
