enum Role {
  president('President'),
  secretary('Secretary'),
  treasurer('Treasurer'),
  vicePresident('Vice President'),
  jointSecretary('Joint Secretary'),
  jointTreasurer('Joint Treasurer'),
  ecMember('EC Member'),
  monitor('Monitor'),
  owner('Owner'),
  resident('Resident'),
  caretaker('Caretaker'),
  auditor('Auditor');

  const Role(this.label);
  final String label;

  bool get isOfficeBearer => const {
    Role.president,
    Role.secretary,
    Role.treasurer,
    Role.vicePresident,
    Role.jointSecretary,
    Role.jointTreasurer,
  }.contains(this);

  bool get isCommittee => isOfficeBearer || this == Role.ecMember || this == Role.monitor;

  bool get canReviewChecklist => const {Role.secretary, Role.jointSecretary, Role.monitor}.contains(this);

  bool get seesFinance => isOfficeBearer || this == Role.ecMember || this == Role.auditor;
}

class DemoUser {
  const DemoUser({
    required this.id,
    required this.name,
    required this.mobile,
    required this.roles,
    this.flatNumber,
    this.monitorCategories = const [],
    this.designations = const [],
    this.monitorUntil,
    this.monitorAssignedBy,
  });

  final String id;
  final String name;
  final String mobile;
  final List<Role> roles;
  final String? flatNumber;
  final List<String> monitorCategories;
  final List<String> designations;
  final DateTime? monitorUntil;
  final String? monitorAssignedBy;

  static const membershipDesk = 'Membership desk';

  /// President, Secretary or an EC member designated (W6-style) for membership changes.
  bool canInitiateMembership(Role active) =>
      active == Role.president ||
      active == Role.secretary ||
      (active.isCommittee && designations.contains(membershipDesk));
}

class Session {
  const Session({required this.user, required this.activeRole});

  final DemoUser user;
  final Role activeRole;

  Session copyWith({Role? activeRole}) => Session(user: user, activeRole: activeRole ?? this.activeRole);
}

enum Occupancy { ownerOccupied, rented, vacant }

class Flat {
  const Flat({
    required this.number,
    required this.block,
    required this.type,
    required this.sqft,
    required this.occupancy,
    required this.ownerName,
    this.residentName,
  });

  final String number;
  final String block;
  final String type;
  final int sqft;
  final Occupancy occupancy;
  final String ownerName;
  final String? residentName;
}

/// A flat as stored in the directory (owner/resident names come from [Person] records).
class FlatInfo {
  const FlatInfo({
    this.id,
    required this.number,
    required this.block,
    required this.type,
    this.sqft,
    this.occupancy = Occupancy.ownerOccupied,
  });

  final String? id;
  final String number;
  final String block;
  final String type;
  final int? sqft;
  final Occupancy occupancy;
}

/// One role held (or invited) in the association; a person with two roles appears twice.
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.invited = false,
    this.mobile,
    this.flatNumber,
    this.designations = const [],
    this.monitorCategories = const [],
    this.monitorFrom,
    this.monitorUntil,
    this.assignedBy,
    this.since,
  });

  final String id;
  final String name;
  final String email;
  final Role role;
  final bool invited;
  final String? mobile;
  final String? flatNumber;
  final List<String> designations;
  final List<String> monitorCategories;
  final DateTime? monitorFrom;
  final DateTime? monitorUntil;
  final String? assignedBy;
  final DateTime? since;
}

class IdDocument {
  const IdDocument({
    required this.id,
    required this.type,
    required this.uploadedAt,
    this.last4,
    this.path,
    this.archived = false,
  });

  final String id;
  final String type;
  final DateTime uploadedAt;
  final String? last4;
  final String? path;
  final bool archived;
}

const idDocTypes = [
  'Aadhaar (masked)',
  'PAN card',
  'Passport',
  'Driving licence',
  'Voter ID',
  'Lease / rent agreement',
  'Sale deed',
  'Police verification form',
];

const monitorAreas = [
  'STP',
  'Gym',
  'Cleaning',
  'Security',
  'Electrical',
  'Plumbing',
  'Lift',
  'Water supply',
  'Garden',
  'Swimming pool',
  'Parking',
];

enum Criticality {
  critical('Critical'),
  high('High'),
  medium('Medium'),
  low('Low');

  const Criticality(this.label);
  final String label;
}

enum TicketType { maintenance, complaint }

enum TicketStatus {
  pendingReview('Awaiting Secretary review'),
  newTicket('New'),
  assigned('Assigned'),
  inProgress('In progress'),
  onHold('On hold'),
  planned('Planned (future)'),
  resolved('Resolved'),
  closed('Closed'),
  rejected('Rejected');

  const TicketStatus(this.label);
  final String label;

  bool get isOpen =>
      !const {TicketStatus.resolved, TicketStatus.closed, TicketStatus.rejected, TicketStatus.planned}.contains(this);
}

enum ReportKind {
  complaint('Complaint'),
  enhancementImmediate('Enhancement – immediate'),
  enhancementFuture('Enhancement – future');

  const ReportKind(this.label);
  final String label;

  bool get isEnhancement => this != ReportKind.complaint;
}

class TicketRemark {
  const TicketRemark({required this.by, required this.at, required this.text});
  final String by;
  final DateTime at;
  final String text;
}

class Complaint {
  const Complaint({
    required this.id,
    required this.flatNumber,
    required this.type,
    required this.category,
    required this.title,
    required this.description,
    required this.criticality,
    required this.status,
    required this.createdAt,
    required this.raisedBy,
    this.aiSuggested = false,
    this.assignee,
    this.remarks = const [],
    this.photoCount = 0,
    this.hasVoiceNote = false,
    this.isPrivate = false,
    this.location = 'Inside flat',
    this.kind = ReportKind.complaint,
    this.acceptedAt,
    this.estimatedCost,
  });

  final String id;
  final String flatNumber;
  final TicketType type;
  final String category;
  final String title;
  final String description;
  final Criticality criticality;
  final TicketStatus status;
  final DateTime createdAt;
  final String raisedBy;
  final bool aiSuggested;
  final String? assignee;
  final List<TicketRemark> remarks;
  final int photoCount;
  final bool hasVoiceNote;
  final bool isPrivate;
  final String location;
  final ReportKind kind;

  /// When the Secretary accepted a common-area report; the SLA clock starts here.
  final DateTime? acceptedAt;
  final int? estimatedCost;

  bool get inReview => status == TicketStatus.pendingReview;

  /// SLA colours apply only to accepted, open complaints (not enhancements or items in review).
  bool get slaApplies => status.isOpen && !inReview && !kind.isEnhancement;

  Complaint copyWith({
    TicketStatus? status,
    Criticality? criticality,
    String? assignee,
    List<TicketRemark>? remarks,
    bool? aiSuggested,
    ReportKind? kind,
    DateTime? acceptedAt,
    String? title,
    String? description,
    String? category,
    int? estimatedCost,
  }) => Complaint(
    id: id,
    flatNumber: flatNumber,
    type: type,
    category: category ?? this.category,
    title: title ?? this.title,
    description: description ?? this.description,
    criticality: criticality ?? this.criticality,
    status: status ?? this.status,
    createdAt: createdAt,
    raisedBy: raisedBy,
    aiSuggested: aiSuggested ?? this.aiSuggested,
    assignee: assignee ?? this.assignee,
    remarks: remarks ?? this.remarks,
    photoCount: photoCount,
    hasVoiceNote: hasVoiceNote,
    isPrivate: isPrivate,
    location: location,
    kind: kind ?? this.kind,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    estimatedCost: estimatedCost ?? this.estimatedCost,
  );
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.category,
    required this.timeWindow,
    this.done = false,
    this.note = '',
    this.hasVoiceNote = false,
    this.proofRequired = false,
    this.rejectedReason,
  });

  final String id;
  final String title;
  final String category;
  final String timeWindow;
  final bool done;
  final String note;
  final bool hasVoiceNote;
  final bool proofRequired;
  final String? rejectedReason;

  ChecklistItem copyWith({
    bool? done,
    String? note,
    bool? hasVoiceNote,
    String? rejectedReason,
    bool clearRejection = false,
  }) => ChecklistItem(
    id: id,
    title: title,
    category: category,
    timeWindow: timeWindow,
    done: done ?? this.done,
    note: note ?? this.note,
    hasVoiceNote: hasVoiceNote ?? this.hasVoiceNote,
    proofRequired: proofRequired,
    rejectedReason: clearRejection ? null : (rejectedReason ?? this.rejectedReason),
  );
}

enum Decision { pending, approved, rejected, sentBack }

class ApproverStep {
  const ApproverStep({
    required this.role,
    required this.name,
    this.decision = Decision.pending,
    this.comment,
    this.onBehalfOf,
    this.alternateRole,
    this.decidedBy,
  });

  final Role role;
  final String name;
  final Decision decision;
  final String? comment;
  final String? onBehalfOf;

  /// "Either/or" step, e.g. Secretary OR President.
  final Role? alternateRole;
  final String? decidedBy;

  String get label => alternateRole == null ? role.label : '${role.label} or ${alternateRole!.label}';

  /// Owner-consent steps are bound to a named owner; other steps to the role.
  bool matches(Role active, String userName) {
    if (active != role && active != alternateRole) return false;
    return role != Role.owner || name == userName;
  }

  ApproverStep copyWith({Decision? decision, String? comment, String? decidedBy}) => ApproverStep(
    role: role,
    name: name,
    decision: decision ?? this.decision,
    comment: comment ?? this.comment,
    onBehalfOf: onBehalfOf,
    alternateRole: alternateRole,
    decidedBy: decidedBy ?? this.decidedBy,
  );
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.code,
    required this.title,
    required this.initiatorName,
    required this.initiatorRole,
    required this.createdAt,
    required this.steps,
    required this.details,
    this.momRequired = false,
    this.momRef,
    this.highRisk = false,
    this.flagged = false,
    this.category = 'General',
  });

  final String id;
  final String code;
  final String title;
  final String initiatorName;
  final Role initiatorRole;
  final DateTime createdAt;
  final List<ApproverStep> steps;
  final Map<String, String> details;
  final bool momRequired;
  final String? momRef;
  final bool highRisk;
  final bool flagged;
  final String category;

  bool awaits(Role active, String userName) =>
      currentStep?.matches(active, userName) == true && !initiatorName.contains(userName);

  Decision get overall {
    if (steps.any((s) => s.decision == Decision.rejected)) return Decision.rejected;
    if (steps.any((s) => s.decision == Decision.sentBack)) return Decision.sentBack;
    if (steps.every((s) => s.decision == Decision.approved)) return Decision.approved;
    return Decision.pending;
  }

  ApproverStep? get currentStep {
    if (overall != Decision.pending) return null;
    for (final s in steps) {
      if (s.decision == Decision.pending) return s;
    }
    return null;
  }

  ApprovalRequest copyWith({List<ApproverStep>? steps, bool? flagged}) => ApprovalRequest(
    id: id,
    code: code,
    title: title,
    initiatorName: initiatorName,
    initiatorRole: initiatorRole,
    createdAt: createdAt,
    steps: steps ?? this.steps,
    details: details,
    momRequired: momRequired,
    momRef: momRef,
    highRisk: highRisk,
    flagged: flagged ?? this.flagged,
    category: category,
  );
}

class DueLine {
  const DueLine({
    required this.flatNumber,
    required this.head,
    required this.amount,
    required this.paid,
    required this.dueDate,
    this.receiptNo,
  });

  final String flatNumber;
  final String head;
  final int amount;
  final int paid;
  final DateTime dueDate;
  final String? receiptNo;

  int get pending => amount - paid;
  bool get isPaid => pending <= 0;

  DueLine markPaid(String receipt) =>
      DueLine(flatNumber: flatNumber, head: head, amount: amount, paid: amount, dueDate: dueDate, receiptNo: receipt);
}

enum ExpenseStatus {
  awaitingTreasurer('Awaiting Treasurer'),
  awaitingPresident('Awaiting President'),
  approved('Approved'),
  sentBack('Sent back');

  const ExpenseStatus(this.label);
  final String label;
}

class Expense {
  const Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.vendor,
    required this.description,
    required this.amount,
    required this.status,
    required this.enteredBy,
    this.documents = 1,
    this.flagged = false,
    this.comment,
  });

  final String id;
  final DateTime date;
  final String category;
  final String vendor;
  final String description;
  final int amount;
  final ExpenseStatus status;
  final String enteredBy;
  final int documents;
  final bool flagged;
  final String? comment;

  Expense copyWith({ExpenseStatus? status, bool? flagged, String? comment}) => Expense(
    id: id,
    date: date,
    category: category,
    vendor: vendor,
    description: description,
    amount: amount,
    status: status ?? this.status,
    enteredBy: enteredBy,
    documents: documents,
    flagged: flagged ?? this.flagged,
    comment: comment ?? this.comment,
  );
}

class FundRequest {
  const FundRequest({required this.name, required this.kind, required this.basis, required this.status, this.dueDay});

  final String name;
  final String kind;
  final String basis;
  final String status;
  final String? dueDay;
}

enum MeetingMode { inPerson, online, hybrid }

enum Rsvp { pending, accepted, tentative, declined }

class Meeting {
  const Meeting({
    required this.id,
    required this.type,
    required this.title,
    required this.at,
    required this.mode,
    required this.agenda,
    this.platform,
    this.venue,
    this.accepted = 0,
    this.tentative = 0,
    this.declined = 0,
    this.invited = 0,
    this.myRsvp = Rsvp.pending,
    this.minutesStatus,
  });

  final String id;
  final String type;
  final String title;
  final DateTime at;
  final MeetingMode mode;
  final List<String> agenda;
  final String? platform;
  final String? venue;
  final int accepted;
  final int tentative;
  final int declined;
  final int invited;
  final Rsvp myRsvp;
  final String? minutesStatus;

  Meeting withRsvp(Rsvp r) {
    int a = accepted, t = tentative, d = declined;
    void adj(Rsvp x, int delta) {
      if (x == Rsvp.accepted) a += delta;
      if (x == Rsvp.tentative) t += delta;
      if (x == Rsvp.declined) d += delta;
    }

    adj(myRsvp, -1);
    adj(r, 1);
    return Meeting(
      id: id,
      type: type,
      title: title,
      at: at,
      mode: mode,
      agenda: agenda,
      platform: platform,
      venue: venue,
      accepted: a,
      tentative: t,
      declined: d,
      invited: invited,
      myRsvp: r,
      minutesStatus: minutesStatus,
    );
  }
}

class Notice {
  const Notice({required this.title, required this.body, required this.date, this.important = false});
  final String title;
  final String body;
  final DateTime date;
  final bool important;
}
