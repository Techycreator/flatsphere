import '../models/models.dart';

const associationName = 'Green Meadows Apartment Owners Association';
const associationCity = 'Kochi, Kerala';

const demoUsers = <DemoUser>[
  DemoUser(id: 'u1', name: 'Rajesh Menon', mobile: '98470 11111', roles: [Role.president, Role.owner], flatNumber: 'A-101'),
  DemoUser(id: 'u2', name: 'Anitha Nair', mobile: '98470 22222', roles: [Role.secretary, Role.owner], flatNumber: 'A-203'),
  DemoUser(id: 'u3', name: 'Thomas Kurian', mobile: '98470 33333', roles: [Role.treasurer, Role.owner], flatNumber: 'B-102'),
  DemoUser(id: 'u4', name: 'Lakshmi Pillai', mobile: '98470 44444', roles: [Role.monitor, Role.ecMember, Role.owner], flatNumber: 'B-301', monitorCategories: ['STP', 'Gym', 'Cleaning'], designations: [DemoUser.membershipDesk]),
  DemoUser(id: 'u5', name: 'Priya Varghese', mobile: '98470 55555', roles: [Role.owner], flatNumber: 'C-204'),
  DemoUser(id: 'u6', name: 'Arun Das', mobile: '98470 66666', roles: [Role.resident], flatNumber: 'C-302'),
  DemoUser(id: 'u7', name: 'Suresh Kumar', mobile: '98470 77777', roles: [Role.caretaker]),
  DemoUser(id: 'u8', name: 'CA Meera Iyer', mobile: '98470 88888', roles: [Role.auditor]),
];

const demoFlats = <Flat>[
  Flat(number: 'A-101', block: 'A', type: '3BHK', sqft: 1450, occupancy: Occupancy.ownerOccupied, ownerName: 'Rajesh Menon'),
  Flat(number: 'A-102', block: 'A', type: '2BHK', sqft: 1080, occupancy: Occupancy.rented, ownerName: 'Joseph Mathew', residentName: 'Vivek Rao'),
  Flat(number: 'A-203', block: 'A', type: '2.5BHK', sqft: 1250, occupancy: Occupancy.ownerOccupied, ownerName: 'Anitha Nair'),
  Flat(number: 'A-204', block: 'A', type: '2BHK', sqft: 1080, occupancy: Occupancy.vacant, ownerName: 'Sanjay Gupta'),
  Flat(number: 'B-102', block: 'B', type: '3BHK', sqft: 1450, occupancy: Occupancy.ownerOccupied, ownerName: 'Thomas Kurian'),
  Flat(number: 'B-205', block: 'B', type: '2BHK', sqft: 1080, occupancy: Occupancy.rented, ownerName: 'Priya Varghese', residentName: 'Nikhil Shah'),
  Flat(number: 'B-301', block: 'B', type: '2.5BHK', sqft: 1250, occupancy: Occupancy.ownerOccupied, ownerName: 'Lakshmi Pillai'),
  Flat(number: 'C-204', block: 'C', type: '3BHK', sqft: 1450, occupancy: Occupancy.ownerOccupied, ownerName: 'Priya Varghese'),
  Flat(number: 'C-302', block: 'C', type: '2BHK', sqft: 1080, occupancy: Occupancy.rented, ownerName: 'George Antony', residentName: 'Arun Das'),
  Flat(number: 'C-401', block: 'C', type: '3BHK', sqft: 1450, occupancy: Occupancy.ownerOccupied, ownerName: 'Deepa Krishnan'),
];

const maintenanceRates = <String, int>{'2BHK': 2500, '2.5BHK': 3000, '3BHK': 3500};

List<Complaint> buildDemoComplaints(DateTime now) {
  DateTime ago({int days = 0, int hours = 0}) => now.subtract(Duration(days: days, hours: hours));
  return [
    Complaint(id: 'CMP-2026-0142', flatNumber: 'Common', type: TicketType.complaint, category: 'Lift', title: 'Block B lift stuck between 2nd and 3rd floor', description: 'Lift stopped with a jerk. Nobody inside now but it is not moving.', criticality: Criticality.critical, aiSuggested: true, status: TicketStatus.inProgress, createdAt: ago(hours: 3), raisedBy: 'Lakshmi Pillai', assignee: 'Suresh Kumar', location: 'Block B lift', photoCount: 1),
    Complaint(id: 'CMP-2026-0139', flatNumber: 'C-204', type: TicketType.maintenance, category: 'Plumbing', title: 'Kitchen sink drain blocked', description: 'Water not draining since yesterday night.', criticality: Criticality.medium, aiSuggested: true, status: TicketStatus.assigned, createdAt: ago(days: 2), raisedBy: 'Priya Varghese', assignee: 'Suresh Kumar', photoCount: 2, hasVoiceNote: true),
    Complaint(id: 'CMP-2026-0131', flatNumber: 'C-302', type: TicketType.complaint, category: 'Water supply', title: 'Low water pressure on 3rd floor', description: 'Pressure very low in mornings 6-8 AM.', criticality: Criticality.high, aiSuggested: true, status: TicketStatus.onHold, createdAt: ago(days: 4), raisedBy: 'Arun Das', assignee: 'Suresh Kumar', remarks: [TicketRemark(by: 'Suresh Kumar', at: ago(days: 2), text: 'Pressure pump vendor called; part (pressure switch) awaited.')]),
    Complaint(id: 'CMP-2026-0124', flatNumber: 'A-203', type: TicketType.complaint, category: 'Cleaning', title: 'Garbage not cleared near Block A gate', description: 'Garbage bins overflowing for two days.', criticality: Criticality.medium, status: TicketStatus.inProgress, createdAt: ago(days: 7), raisedBy: 'Anitha Nair', assignee: 'Cleaning staff', remarks: [TicketRemark(by: 'Suresh Kumar', at: ago(days: 1), text: 'Corporation truck did not come; arranged private pickup tomorrow.')]),
    Complaint(id: 'CMP-2026-0120', flatNumber: 'B-301', type: TicketType.maintenance, category: 'Electrical', title: 'Corridor light not working on 3rd floor', description: 'Two tube lights near stairs not working.', criticality: Criticality.low, status: TicketStatus.newTicket, createdAt: ago(days: 1), raisedBy: 'Lakshmi Pillai'),
    Complaint(id: 'CMP-2026-0144', flatNumber: 'Common', type: TicketType.complaint, kind: ReportKind.complaint, category: 'Security', title: 'CCTV camera near Block C gate not recording', description: 'Camera 7 shows "No signal" on the NVR since morning.', criticality: Criticality.high, aiSuggested: true, status: TicketStatus.pendingReview, createdAt: ago(hours: 5), raisedBy: 'Suresh Kumar', location: 'Block C gate', photoCount: 1),
    Complaint(id: 'CMP-2026-0145', flatNumber: 'Common', type: TicketType.complaint, kind: ReportKind.enhancementImmediate, category: 'Gym', title: 'Replace torn treadmill belt', description: 'Belt is torn at the edge; unsafe to use. Vendor quote ₹8,500.', criticality: Criticality.medium, status: TicketStatus.pendingReview, createdAt: ago(days: 1, hours: 2), raisedBy: 'Lakshmi Pillai', location: 'Gym', estimatedCost: 8500, hasVoiceNote: true),
    Complaint(id: 'CMP-2026-0146', flatNumber: 'Common', type: TicketType.complaint, kind: ReportKind.enhancementFuture, category: 'Electrical', title: 'Solar panels on terrace to cut common electricity bill', description: '10 kW rooftop system; estimated payback 5 years.', criticality: Criticality.low, status: TicketStatus.planned, createdAt: ago(days: 20), acceptedAt: ago(days: 18), raisedBy: 'Rajesh Menon', location: 'Terrace', estimatedCost: 650000, remarks: [TicketRemark(by: 'Anitha Nair (Secretary)', at: ago(days: 18), text: 'Moved to future enhancements. Added to AGM 2026 agenda for budget discussion.')]),
    Complaint(id: 'CMP-2026-0147', flatNumber: 'Common', type: TicketType.complaint, kind: ReportKind.enhancementImmediate, category: 'Other', title: 'Anti-skid strips on swimming pool steps', description: 'Two residents slipped last month.', criticality: Criticality.medium, status: TicketStatus.inProgress, createdAt: ago(days: 6), acceptedAt: ago(days: 5), raisedBy: 'Suresh Kumar', location: 'Swimming pool', estimatedCost: 4200, assignee: 'Suresh Kumar', remarks: [TicketRemark(by: 'Anitha Nair (Secretary)', at: ago(days: 5), text: 'Approved as immediate enhancement. Within petty-cash limit.')]),
    Complaint(id: 'CMP-2026-0111', flatNumber: 'C-204', type: TicketType.complaint, category: 'Community', title: 'Unknown car parked in my slot', description: 'KL-07 white sedan parked in C-204 slot for 2 days.', criticality: Criticality.low, status: TicketStatus.resolved, createdAt: ago(days: 9), raisedBy: 'Priya Varghese', remarks: [TicketRemark(by: 'Suresh Kumar', at: ago(days: 8), text: 'Visitor of A-102; vehicle moved and owner informed.')]),
  ];
}

List<ChecklistItem> buildDemoChecklist() => const [
      ChecklistItem(id: 'c1', title: 'Overhead water tank level check', category: 'Caretaker functions', timeWindow: 'Before 7:00 AM', done: true, proofRequired: true),
      ChecklistItem(id: 'c2', title: 'Sump level and pump running check', category: 'Caretaker functions', timeWindow: 'Before 7:30 AM', done: true),
      ChecklistItem(id: 'c3', title: 'STP blower and pH reading', category: 'STP', timeWindow: 'Before 9:00 AM', proofRequired: true),
      ChecklistItem(id: 'c4', title: 'Generator diesel level', category: 'Caretaker functions', timeWindow: 'Before 10:00 AM'),
      ChecklistItem(id: 'c5', title: 'Common area cleaning – lobby and stairs', category: 'Cleaning', timeWindow: 'Before 11:00 AM', done: true),
      ChecklistItem(id: 'c6', title: 'Garbage clearance from all blocks', category: 'Cleaning', timeWindow: 'Before 12:00 PM'),
      ChecklistItem(id: 'c7', title: 'Gym equipment wipe-down and AC check', category: 'Gym', timeWindow: 'Before 5:00 PM'),
      ChecklistItem(id: 'c8', title: 'CCTV recording status check', category: 'Security', timeWindow: 'Before 6:00 PM'),
      ChecklistItem(id: 'c9', title: 'Security guard shift handover log', category: 'Security', timeWindow: 'At 8:00 PM'),
      ChecklistItem(id: 'c10', title: 'Common lights on (sunset)', category: 'Caretaker functions', timeWindow: 'At 6:30 PM'),
    ];

List<ApprovalRequest> buildDemoApprovals(DateTime now) => [
      ApprovalRequest(
        id: 'APR-031', code: 'W3', title: 'Change association bank account (settlement)',
        initiatorName: 'Thomas Kurian', initiatorRole: Role.treasurer, createdAt: now.subtract(const Duration(days: 1)),
        momRequired: true, momRef: 'EC-2026-09 · Decision #4', highRisk: true,
        details: const {'Current account': 'SBI Kakkanad ••••4521', 'New account': 'Federal Bank Edappally ••••8890', 'Reason': 'Lower charges, sweep FD facility', 'Proof': 'Cancelled cheque + bank letter', 'Cooling-off': '48 hours after final approval'},
        steps: const [ApproverStep(role: Role.secretary, name: 'Anitha Nair', decision: Decision.approved, comment: 'Verified bank letter.'), ApproverStep(role: Role.president, name: 'Rajesh Menon')],
      ),
      ApprovalRequest(
        id: 'APR-033', code: 'W20', category: 'Membership', title: 'Owner change – A-204: Sanjay Gupta → Meera & Ravi Shankar (sale)',
        initiatorName: 'Lakshmi Pillai', initiatorRole: Role.ecMember, createdAt: now.subtract(const Duration(hours: 20)),
        details: const {'Flat': 'A-204 (2BHK, vacant)', 'Current owner': 'Sanjay Gupta', 'New owner(s)': 'Meera Shankar, Ravi Shankar (joint)', 'Sale deed': 'Registered · Doc no. 4417/2026, SRO Edappally', 'Dues check': 'Pending ₹12,500 – must be cleared before final approval', 'After approval': 'Old owner archived; new owners invited by SMS/WhatsApp'},
        steps: const [ApproverStep(role: Role.secretary, name: 'Anitha Nair'), ApproverStep(role: Role.president, name: 'Rajesh Menon')],
      ),
      ApprovalRequest(
        id: 'APR-034', code: 'W21', category: 'Membership', title: 'Resident change – B-205: Nikhil Shah → Sneha Joseph (tenant)',
        initiatorName: 'Lakshmi Pillai', initiatorRole: Role.ecMember, createdAt: now.subtract(const Duration(hours: 6)),
        details: const {'Flat': 'B-205 (owner: Priya Varghese)', 'Outgoing resident': 'Nikhil Shah – lease ends 31 Oct', 'Incoming resident': 'Sneha Joseph + 2 family members (1 login, age 12+)', 'Lease': '1 Nov 2026 – 31 Oct 2027', 'ID proofs': '3 uploaded (Aadhaar masked)', 'Police verification': 'Form submitted'},
        steps: const [ApproverStep(role: Role.owner, name: 'Priya Varghese'), ApproverStep(role: Role.secretary, alternateRole: Role.president, name: 'Anitha Nair / Rajesh Menon')],
      ),
      ApprovalRequest(
        id: 'APR-035', code: 'W22', category: 'Committee', title: 'Committee change – Joint Secretary: Biju Thomas resigns; co-opt Deepa Krishnan (C-401)',
        initiatorName: 'Anitha Nair', initiatorRole: Role.secretary, createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        momRequired: true, momRef: 'EC-2026-10 · Decision #3',
        details: const {'Position': 'Joint Secretary', 'Change type': 'Resignation and co-option', 'Outgoing': 'Biju Thomas (resignation letter uploaded)', 'Incoming': 'Deepa Krishnan (C-401)', 'EC formal vote': '7 for · 1 against · 0 abstain (quorum met)', 'GBM ratification': 'Required at AGM 2026 (office bearer)'},
        steps: const [ApproverStep(role: Role.president, name: 'Rajesh Menon')],
      ),
      ApprovalRequest(
        id: 'APR-030', code: 'W12', title: 'Onam 2026 celebration – voluntary fund request',
        initiatorName: 'Anitha Nair', initiatorRole: Role.secretary, createdAt: now.subtract(const Duration(days: 2)),
        momRequired: true, momRef: 'EC-2026-09 · Decision #2',
        details: const {'Type': 'Adhoc', 'Amount': 'Voluntary (suggested ₹1,000)', 'Applies to': 'All flats', 'Due date': '30 Aug'},
        steps: const [ApproverStep(role: Role.president, name: 'Rajesh Menon')],
      ),
      ApprovalRequest(
        id: 'APR-029', code: 'W6', title: 'Appoint Lakshmi Pillai as Monitor – STP, Gym, Cleaning (3 months)',
        initiatorName: 'Anitha Nair', initiatorRole: Role.secretary, createdAt: now.subtract(const Duration(days: 3)),
        details: const {'Monitor': 'Lakshmi Pillai (EC)', 'Categories': 'STP, Gym, Cleaning', 'Duration': '1 Oct – 31 Dec 2026'},
        steps: const [ApproverStep(role: Role.president, name: 'Rajesh Menon')],
      ),
      ApprovalRequest(
        id: 'APR-028', code: 'W10', title: 'New tenant for C-302 – Arun Das + 2 family members',
        initiatorName: 'George Antony (Owner)', initiatorRole: Role.owner, createdAt: now.subtract(const Duration(days: 1)),
        details: const {'Lease': '1 Oct 2026 – 30 Sep 2027', 'ID proofs': '3 uploaded (Aadhaar masked)', 'Police verification': 'Form submitted', 'Family logins': '1 (spouse)'},
        steps: const [ApproverStep(role: Role.secretary, name: 'Anitha Nair')],
      ),
      ApprovalRequest(
        id: 'APR-027', code: 'W16', title: 'Late fee rule: ₹100 after 15-day grace, cap ₹500',
        initiatorName: 'Anitha Nair & Thomas Kurian', initiatorRole: Role.secretary, createdAt: now.subtract(const Duration(days: 5)),
        momRequired: true, momRef: 'EC-2026-08 · Decision #6',
        details: const {'Rule': 'Flat ₹100 after 15 days', 'Cap': '₹500 per due', 'Excludes': 'Voluntary fund requests', 'Effective': 'From Nov 2026 dues'},
        steps: const [ApproverStep(role: Role.president, name: 'Rajesh Menon', decision: Decision.approved)],
      ),
    ];

List<DueLine> buildDemoDues(DateTime now) {
  final due = DateTime(now.year, now.month, 10);
  final lines = <DueLine>[];
  var i = 0;
  for (final f in demoFlats) {
    final rate = maintenanceRates[f.type] ?? 2500;
    final paidMaint = i % 3 != 1;
    lines.add(DueLine(flatNumber: f.number, head: 'Maintenance – ${_month(now)}', amount: rate, paid: paidMaint ? rate : 0, dueDate: due, receiptNo: paidMaint ? 'RCT-${1200 + i}' : null));
    if (i % 4 == 2) {
      lines.add(DueLine(flatNumber: f.number, head: 'Maintenance – ${_month(DateTime(now.year, now.month - 1))}', amount: rate, paid: 0, dueDate: DateTime(now.year, now.month - 1, 10)));
    }
    lines.add(DueLine(flatNumber: f.number, head: 'Corpus fund (instalment 2)', amount: 10000, paid: i % 2 == 0 ? 10000 : 0, dueDate: DateTime(now.year, now.month - 2, 30), receiptNo: i % 2 == 0 ? 'RCT-${1100 + i}' : null));
    i++;
  }
  return lines;
}

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _month(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

List<Expense> buildDemoExpenses(DateTime now) => [
      Expense(id: 'EXP-0412', date: now.subtract(const Duration(days: 1)), category: 'Common electricity', vendor: 'KSEB', description: 'Common area bill – Sep', amount: 18640, status: ExpenseStatus.awaitingTreasurer, enteredBy: 'Anitha Nair', documents: 1),
      Expense(id: 'EXP-0411', date: now.subtract(const Duration(days: 2)), category: 'STP maintenance', vendor: 'AquaTech Services', description: 'Blower motor rewinding', amount: 12500, status: ExpenseStatus.awaitingTreasurer, enteredBy: 'Anitha Nair', documents: 0),
      Expense(id: 'EXP-0409', date: now.subtract(const Duration(days: 3)), category: 'Cleaning liquids & equipment', vendor: 'Kochi Hygiene Mart', description: 'Phenyl, mops, garbage bags', amount: 3420, status: ExpenseStatus.awaitingPresident, enteredBy: 'Thomas Kurian', documents: 2),
      Expense(id: 'EXP-0405', date: now.subtract(const Duration(days: 5)), category: 'Water bill', vendor: 'Kerala Water Authority', description: 'Bi-monthly water charges', amount: 9870, status: ExpenseStatus.approved, enteredBy: 'Thomas Kurian', documents: 1),
      Expense(id: 'EXP-0401', date: now.subtract(const Duration(days: 8)), category: 'Motor maintenance', vendor: 'Sree Electricals', description: 'Pump 2 bearing replacement', amount: 4800, status: ExpenseStatus.approved, enteredBy: 'Anitha Nair', documents: 1, flagged: true, comment: 'Same repair done in July – discuss in EC'),
    ];

const demoFundRequests = <FundRequest>[
  FundRequest(name: 'Monthly maintenance', kind: 'Recurring (monthly)', basis: 'By flat type: 2BHK ₹2,500 · 2.5BHK ₹3,000 · 3BHK ₹3,500', status: 'Active', dueDay: '10th of every month'),
  FundRequest(name: 'Corpus fund – instalment 2', kind: 'Adhoc', basis: 'Fixed ₹10,000 per flat', status: 'Active'),
  FundRequest(name: 'Onam 2026 celebration', kind: 'Adhoc', basis: 'Voluntary (suggested ₹1,000)', status: 'Awaiting President + EC MOM'),
  FundRequest(name: 'Christmas & New Year 2026', kind: 'Adhoc', basis: 'Voluntary', status: 'Draft'),
];

List<Meeting> buildDemoMeetings(DateTime now) => [
      Meeting(id: 'M-21', type: 'Executive Committee', title: 'EC meeting – October', at: DateTime(now.year, now.month, now.day + 3, 19, 30), mode: MeetingMode.hybrid, platform: 'Google Meet', venue: 'Association office', agenda: const ['Review of Sep accounts', 'Flagged: Pump 2 repeat repair (EXP-0401)', 'Red complaints review', 'Lift AMC renewal quotes'], invited: 9, accepted: 5, tentative: 2, declined: 0),
      Meeting(id: 'M-22', type: 'Staff meeting', title: 'Monthly staff review', at: DateTime(now.year, now.month, now.day + 6, 11), mode: MeetingMode.inPerson, venue: 'Clubhouse', agenda: const ['Checklist completion %', 'Diwali duty roster'], invited: 6, accepted: 4),
      Meeting(id: 'M-23', type: 'General Body', title: 'Annual General Meeting 2026', at: DateTime(now.year, now.month + 1, 15, 10), mode: MeetingMode.hybrid, platform: 'Zoom', venue: 'Party hall', agenda: const ['Adoption of audited accounts FY 2025-26', 'Budget FY 2026-27', 'Election of new committee'], invited: 120, accepted: 46, tentative: 18, declined: 3),
      Meeting(id: 'M-20', type: 'Office bearers', title: 'Office bearers – October review', at: now.subtract(const Duration(days: 2)), mode: MeetingMode.online, platform: 'Google Meet', agenda: const ['Lift AMC renewal quotes', 'Diesel spend increase'], invited: 5, accepted: 5),
      Meeting(id: 'M-19', type: 'Executive Committee', title: 'EC meeting – September', at: DateTime(now.year, now.month - 1, 20, 19, 30), mode: MeetingMode.online, platform: 'Google Meet', agenda: const ['Bank account change proposal', 'Onam fund request'], invited: 9, accepted: 8, minutesStatus: 'Approved by President'),
    ];

List<Notice> buildDemoNotices(DateTime now) => [
      Notice(title: 'Water supply interruption – Saturday 10 AM to 1 PM', body: 'Overhead tank cleaning in Block B and C. Please store water.', date: now.subtract(const Duration(days: 1)), important: true),
      Notice(title: 'September accounts published', body: 'Income & expenditure for September is now available under Statements.', date: now.subtract(const Duration(days: 3))),
      Notice(title: 'AGM on 15th next month', body: 'Agenda and audited accounts will be shared 14 days before the meeting.', date: now.subtract(const Duration(days: 6))),
    ];
