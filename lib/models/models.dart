enum Role {
  admin('Admin'),
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
  security('Security'),
  auditor('Auditor');

  const Role(this.label);
  final String label;

  bool get isOfficeBearer => const {
    Role.admin,
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
    this.associationId,
    this.associations = const [],
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
  final String? associationId;
  final List<AssociationInfo> associations;

  AssociationInfo? get association {
    for (final association in associations) {
      if (association.id == associationId) return association;
    }
    return null;
  }

  static const membershipDesk = 'Membership desk';

  /// President, Secretary or an EC member designated (W6-style) for membership changes.
  bool canInitiateMembership(Role active) =>
      active == Role.admin ||
      active == Role.president ||
      active == Role.secretary ||
      (active.isCommittee && designations.contains(membershipDesk));
}

class AssociationInfo {
  const AssociationInfo({required this.id, required this.name, this.state = '', this.city, this.settings = const {}});

  final String id;
  final String name;
  final String state;
  final String? city;
  final Map<String, dynamic> settings;

  String get location => [city, state].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
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
    this.carNumber,
    this.bikeNumber,
    this.parkingSlot,
  });

  final String? id;
  final String number;
  final String block;
  final String type;
  final int? sqft;
  final Occupancy occupancy;
  final String? carNumber;
  final String? bikeNumber;
  final String? parkingSlot;
}

class VehicleContact {
  const VehicleContact({
    required this.registrationNumber,
    required this.vehicleType,
    required this.flatNumber,
    this.personName,
    this.phone,
  });

  final String registrationNumber;
  final String vehicleType;
  final String flatNumber;
  final String? personName;
  final String? phone;
}

class VehicleRegisterRow {
  const VehicleRegisterRow({
    required this.registrationNumber,
    required this.vehicleType,
    required this.flatNumber,
    this.parkingSlot,
  });

  final String registrationNumber;
  final String vehicleType;
  final String flatNumber;
  final String? parkingSlot;
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
    this.birthDate,
    this.designations = const [],
    this.monitorCategories = const [],
    this.monitorFrom,
    this.monitorUntil,
    this.assignedBy,
    this.since,
    this.supportFlags = const [],
  });

  final String id;
  final String name;
  final String email;
  final Role role;
  final bool invited;
  final String? mobile;
  final String? flatNumber;
  final DateTime? birthDate;
  final List<String> designations;
  final List<String> monitorCategories;
  final DateTime? monitorFrom;
  final DateTime? monitorUntil;
  final String? assignedBy;
  final DateTime? since;
  final List<MemberSupportFlag> supportFlags;

  AgeCategory? get ageCategory {
    final dob = birthDate;
    if (dob == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) age--;
    if (age < 18) return AgeCategory.child;
    if (age >= 60) return AgeCategory.seniorCitizen;
    return AgeCategory.adult;
  }
}

class FamilyMemberRecord {
  const FamilyMemberRecord({
    required this.id,
    required this.name,
    required this.dateOfBirth,
    required this.flatNumber,
    required this.approved,
    this.email,
  });

  final String id;
  final String name;
  final DateTime dateOfBirth;
  final String flatNumber;
  final bool approved;
  final String? email;
}

class FamilyAccountRules {
  static int ageOn(DateTime birthDate, DateTime today) {
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) age--;
    return age;
  }

  static bool isLoginEligible(DateTime birthDate, int minimumAge, DateTime today) =>
      minimumAge > 0 && ageOn(birthDate, today) >= minimumAge;

  static bool isWithinMemberLimit(int count, int limit) => count >= 0 && limit >= 0 && count <= limit;
}

class IdDocumentAccessEntry {
  const IdDocumentAccessEntry({
    required this.userId,
    required this.name,
    required this.roles,
    required this.canViewAll,
    required this.isOfficeBearer,
  });

  final String userId;
  final String name;
  final String roles;
  final bool canViewAll;
  final bool isOfficeBearer;
}

enum AgeCategory {
  child('Child'),
  adult('Adult'),
  seniorCitizen('Senior citizen');

  const AgeCategory(this.label);
  final String label;
}

enum MemberSupportFlag {
  wheelchairAssisted('Wheelchair assistance');

  const MemberSupportFlag(this.label);
  final String label;
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
  inProgress('In Progress'),
  onHold('On Hold'),
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
    this.photoProofPaths = const [],
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
  final List<String> photoProofPaths;
  final String? rejectedReason;

  ChecklistItem copyWith({
    bool? done,
    String? note,
    bool? hasVoiceNote,
    List<String>? photoProofPaths,
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
    photoProofPaths: photoProofPaths ?? this.photoProofPaths,
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

class MembershipTransitionItem {
  const MembershipTransitionItem({
    required this.id,
    required this.phase,
    required this.label,
    required this.required,
    required this.completed,
    this.completedBy,
    this.completedAt,
    this.note = '',
  });

  final String id;
  final String phase;
  final String label;
  final bool required;
  final bool completed;
  final String? completedBy;
  final DateTime? completedAt;
  final String note;
}

class DueLine {
  const DueLine({
    this.id,
    this.flatId,
    required this.flatNumber,
    required this.head,
    required this.amount,
    required this.paid,
    required this.dueDate,
    this.receiptNo,
  });

  final String? id;
  final String? flatId;
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
    this.dbId,
    this.billPaths = const [],
    this.eventId,
  });

  /// Display reference, e.g. EXP-1001; [dbId] is the database key in cloud mode.
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
  final String? dbId;
  final List<String> billPaths;
  final String? eventId;

  Expense copyWith({ExpenseStatus? status, bool? flagged, String? comment, int? documents}) => Expense(
    id: id,
    date: date,
    category: category,
    vendor: vendor,
    description: description,
    amount: amount,
    status: status ?? this.status,
    enteredBy: enteredBy,
    documents: documents ?? this.documents,
    flagged: flagged ?? this.flagged,
    comment: comment ?? this.comment,
    dbId: dbId,
    billPaths: billPaths,
    eventId: eventId,
  );
}

class OpeningBalance {
  const OpeningBalance({required this.account, required this.amount, required this.asOf});

  final String account;
  final int amount;

  /// Balance at the start of this day; payments and approved expenses from this day on are added.
  final DateTime asOf;
}

class PaymentRecord {
  const PaymentRecord({
    required this.flatNumber,
    required this.amount,
    required this.paidOn,
    required this.receiptNo,
    required this.mode,
    this.reference,
    this.head,
  });

  final String flatNumber;
  final int amount;
  final DateTime paidOn;
  final String receiptNo;
  final String mode;
  final String? reference;
  final String? head;
}

class MonthlyStatement {
  const MonthlyStatement({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.snapshot,
    required this.createdBy,
    this.treasurerApprovedBy,
    this.secretaryApprovedBy,
    this.presidentApprovedBy,
    this.rejectionNote,
  });

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final Map<String, dynamic> snapshot;
  final String createdBy;
  final String? treasurerApprovedBy;
  final String? secretaryApprovedBy;
  final String? presidentApprovedBy;
  final String? rejectionNote;
}

class AnnualBudget {
  const AnnualBudget({
    required this.id,
    required this.fiscalYearStart,
    required this.fiscalYearEnd,
    required this.categoryAmounts,
    required this.resolutionRef,
    required this.resolutionDate,
    required this.status,
    required this.createdBy,
    this.secretaryApprovedBy,
    this.presidentApprovedBy,
    this.rejectionNote,
  });

  final String id;
  final DateTime fiscalYearStart;
  final DateTime fiscalYearEnd;
  final Map<String, int> categoryAmounts;
  final String resolutionRef;
  final DateTime resolutionDate;
  final String status;
  final String createdBy;
  final String? secretaryApprovedBy;
  final String? presidentApprovedBy;
  final String? rejectionNote;
}

enum IncomeCategoryStatus { pending, active, rejected, sentBack }

class IncomeCategory {
  const IncomeCategory({required this.id, required this.name, required this.status, required this.requestRef});

  final String id;
  final String name;
  final IncomeCategoryStatus status;
  final String requestRef;
}

class IncomeEntry {
  const IncomeEntry({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.receivedOn,
    required this.amount,
    required this.recordedBy,
    this.source,
    this.description = '',
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final DateTime receivedOn;
  final int amount;
  final String recordedBy;
  final String? source;
  final String description;
}

const paymentModes = {
  'upi': 'UPI',
  'bank_transfer': 'Bank transfer / NEFT',
  'cash': 'Cash',
  'cheque': 'Cheque',
  'online': 'Online',
};

const expenseCategories = [
  'Common electricity',
  'Water bill',
  'Security services',
  'Housekeeping / cleaning',
  'Cleaning liquids & equipment',
  'STP maintenance',
  'Lift AMC & repairs',
  'Motor maintenance',
  'Generator & diesel',
  'Garden',
  'Repairs & maintenance',
  'Staff salary',
  'Insurance',
  'Bank charges',
  'Events & festivals',
  'Legal & professional',
  'Office & stationery',
  'Other',
];

class FundRequest {
  const FundRequest({required this.name, required this.kind, required this.basis, required this.status, this.dueDay});

  final String name;
  final String kind;
  final String basis;
  final String status;
  final String? dueDay;
}

class FundRequestRecord {
  const FundRequestRecord({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.momRef,
    this.amount,
    this.basis = '',
    this.dueDay,
  });

  final String id;
  final String title;
  final String type;
  final String status;
  final String momRef;
  final int? amount;
  final String basis;
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
    this.minutesText,
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
  final String? minutesText;

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
      minutesText: minutesText,
    );
  }

  Meeting copyWith({DateTime? at, String? minutesStatus, String? minutesText}) => Meeting(
    id: id,
    type: type,
    title: title,
    at: at ?? this.at,
    mode: mode,
    agenda: agenda,
    platform: platform,
    venue: venue,
    accepted: accepted,
    tentative: tentative,
    declined: declined,
    invited: invited,
    myRsvp: myRsvp,
    minutesStatus: minutesStatus ?? this.minutesStatus,
    minutesText: minutesText ?? this.minutesText,
  );
}

class Notice {
  const Notice({required this.title, required this.body, required this.date, this.important = false});
  final String title;
  final String body;
  final DateTime date;
  final bool important;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.actionPath,
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? actionPath;
  final DateTime? readAt;
}

enum StaffType {
  housekeeping('Housekeeping'),
  stpOperator('STP operator'),
  security('Security');

  const StaffType(this.label);
  final String label;
}

enum AttendanceStatus {
  present('Present'),
  absent('Absent'),
  leave('Leave');

  const AttendanceStatus(this.label);
  final String label;
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.type,
    required this.area,
    this.active = true,
    this.employerType = StaffEmployerType.association,
    this.agencyName,
    this.monthlySalary,
    this.idProofPath,
  });

  final String id;
  final String name;
  final StaffType type;
  final String area;
  final bool active;
  final StaffEmployerType employerType;
  final String? agencyName;
  final int? monthlySalary;
  final String? idProofPath;
}

enum StaffEmployerType { association, agency }

class StaffAttendance {
  const StaffAttendance({
    required this.staffId,
    required this.date,
    required this.status,
    required this.markedBy,
    this.note = '',
  });

  final String staffId;
  final DateTime date;
  final AttendanceStatus status;
  final String markedBy;
  final String note;
}

class FlatHousekeepingWorker {
  const FlatHousekeepingWorker({
    required this.id,
    required this.flatNumber,
    required this.name,
    required this.idProofPath,
    required this.usualIn,
    required this.usualOut,
    required this.residesInFlat,
    this.active = true,
  });

  final String id;
  final String flatNumber;
  final String name;
  final String idProofPath;
  final String usualIn;
  final String usualOut;
  final bool residesInFlat;
  final bool active;
}

enum VisitorStatus {
  expected('Expected'),
  checkedIn('Checked in'),
  checkedOut('Checked out'),
  cancelled('Cancelled');

  const VisitorStatus(this.label);
  final String label;
}

class VisitorRequest {
  const VisitorRequest({
    required this.id,
    required this.hostFlat,
    required this.guestName,
    required this.expectedAt,
    required this.status,
    this.guestPhone,
    this.vehicleNumber,
    this.flatCarNumber,
    this.flatBikeNumber,
    this.parkingSlot,
    this.note = '',
    this.hostName = '',
  });

  final String id;
  final String hostFlat;
  final String guestName;
  final DateTime expectedAt;
  final VisitorStatus status;
  final String? guestPhone;
  final String? vehicleNumber;
  final String? flatCarNumber;
  final String? flatBikeNumber;
  final String? parkingSlot;
  final String note;
  final String hostName;
}

class AssociationRegisterItem {
  const AssociationRegisterItem({
    required this.id,
    required this.type,
    required this.name,
    required this.category,
    required this.status,
    required this.createdAt,
    this.vendor,
    this.purchaseDate,
    this.warrantyEnd,
    this.amcEnd,
    this.expiresOn,
    this.expectedLifeYears,
    this.replacementCost,
    this.details = const {},
  });

  final String id;
  final String type;
  final String name;
  final String category;
  final String status;
  final DateTime createdAt;
  final String? vendor;
  final DateTime? purchaseDate;
  final DateTime? warrantyEnd;
  final DateTime? amcEnd;
  final DateTime? expiresOn;
  final int? expectedLifeYears;
  final int? replacementCost;
  final Map<String, dynamic> details;
}

class Amenity {
  const Amenity({required this.id, required this.name, required this.rules, required this.fee, required this.requiresApproval});

  final String id;
  final String name;
  final String rules;
  final int fee;
  final bool requiresApproval;
}

enum AmenityBookingStatus { pending, approved, rejected, cancelled, completed }

enum AmenityPaymentStatus { unpaid, paid, waived, refunded }

class AmenityBooking {
  const AmenityBooking({
    required this.id,
    required this.amenityName,
    required this.flatNumber,
    required this.hostName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.paymentStatus,
    required this.amountDue,
    this.guestCount = 0,
    this.note = '',
  });

  final String id;
  final String amenityName;
  final String flatNumber;
  final String hostName;
  final DateTime startsAt;
  final DateTime endsAt;
  final AmenityBookingStatus status;
  final AmenityPaymentStatus paymentStatus;
  final int amountDue;
  final int guestCount;
  final String note;
}

class EmergencyContact {
  const EmergencyContact({required this.id, required this.label, required this.name, required this.phone, required this.category, this.notes = ''});
  final String id;
  final String label;
  final String name;
  final String phone;
  final String category;
  final String notes;
}

class CommunityEvent {
  const CommunityEvent({required this.id, required this.title, required this.type, required this.startsAt, required this.endsAt, required this.location, this.description = '', this.budget, this.status = 'scheduled', this.photoPaths = const [], this.fundRequestId, this.fundRequestTitle});
  final String id;
  final String title;
  final String type;
  final DateTime startsAt;
  final DateTime endsAt;
  final String location;
  final String description;
  final int? budget;
  final String status;
  final List<String> photoPaths;
  final String? fundRequestId;
  final String? fundRequestTitle;
}

class MeetingAction {
  const MeetingAction({required this.id, required this.momRef, required this.title, required this.owner, required this.status, this.dueDate, this.eventId});
  final String id;
  final String momRef;
  final String title;
  final String owner;
  final String status;
  final DateTime? dueDate;
  final String? eventId;
}

class MarketplacePost {
  const MarketplacePost({required this.id, required this.type, required this.title, required this.description, required this.contact, required this.expiresAt, required this.author, this.price});
  final String id;
  final String type;
  final String title;
  final String description;
  final String contact;
  final DateTime expiresAt;
  final String author;
  final int? price;
}
