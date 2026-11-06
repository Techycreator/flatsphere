// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FlatSphere';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get complaints => 'Complaints';

  @override
  String get checklist => 'Daily checklist';

  @override
  String get approvals => 'Approvals';

  @override
  String get myRequests => 'My requests';

  @override
  String get finance => 'Finance';

  @override
  String get myDues => 'My dues';

  @override
  String get meetings => 'Meetings';

  @override
  String get directory => 'Flats & people';

  @override
  String get notices => 'Notices';

  @override
  String get more => 'More';

  @override
  String get login => 'Log in';

  @override
  String get mobileNumber => 'Mobile number';

  @override
  String get sendOtp => 'Send OTP';

  @override
  String get enterOtp => 'Enter OTP';

  @override
  String get verify => 'Verify';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get submit => 'Submit';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get sendBack => 'Send back';

  @override
  String get raiseComplaint => 'Raise complaint';

  @override
  String get payNow => 'Pay now';

  @override
  String get language => 'Language';

  @override
  String get switchRole => 'Switch role';

  @override
  String get logout => 'Log out';

  @override
  String get notes => 'Notes';

  @override
  String get recordVoice => 'Record voice note';

  @override
  String get welcome => 'Welcome';

  @override
  String get pendingApprovals => 'Pending approvals';

  @override
  String get today => 'Today';

  @override
  String get viewAll => 'View all';

  @override
  String get demoPersonas => 'Demo mode – choose a user to explore their view';

  @override
  String get associationSettings => 'Association settings';

  @override
  String get associationIdentity => 'Association identity';

  @override
  String get associationName => 'Association name';

  @override
  String get state => 'State';

  @override
  String get city => 'City';

  @override
  String get brandColor => 'Brand color';

  @override
  String get operatingDefaults => 'Operating defaults';

  @override
  String get fiscalYearStartMonth => 'Financial year start month';

  @override
  String get defaultDueDay => 'Default monthly due day';

  @override
  String get subscription => 'Subscription';

  @override
  String get billingProviderNotConfigured => 'Billing provider not configured';

  @override
  String get billingProviderDescription =>
      'Subscription plans and payments need an approved billing provider and pricing.';

  @override
  String get saveSettings => 'Save settings';

  @override
  String get settingsSaved => 'Association settings saved';

  @override
  String get ageNotRecorded => 'Age not recorded';

  @override
  String get child => 'Child';

  @override
  String get adult => 'Adult';

  @override
  String get seniorCitizen => 'Senior citizen';

  @override
  String get dateOfBirthOptional => 'Date of birth (optional)';

  @override
  String birthdayWish(String name) {
    return 'Happy birthday, $name! Wishing you a wonderful year ahead.';
  }

  @override
  String get notifications => 'Notifications';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get exportLedgerCsv => 'Export ledger CSV';

  @override
  String get applyLateFee => 'Apply late fee';

  @override
  String get perSquareFootCharge => 'Per-square-foot charge';

  @override
  String get meetingInvitesNotSent =>
      'Meeting saved. Notifications have not been sent.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get adminRequired => 'Association Admin access is required.';

  @override
  String get createStatement => 'Create statement';

  @override
  String get monthlyStatementDescription =>
      'Monthly income, dues, receipts and approved expenses';

  @override
  String get statementApprovalDescription =>
      'Owners can view a statement after three separate approvals. Published snapshots are immutable.';

  @override
  String get noStatements => 'No monthly statements yet.';

  @override
  String get published => 'Published';

  @override
  String get rejected => 'Rejected';

  @override
  String get statementAwaitingTreasurer => 'Awaiting Treasurer';

  @override
  String get statementAwaitingSecretary => 'Awaiting Secretary';

  @override
  String get statementAwaitingPresident => 'Awaiting President';

  @override
  String get incomeTotal => 'Income';

  @override
  String get approvedExpenses => 'Approved expenses';

  @override
  String get paymentsReceived => 'Payments';

  @override
  String get analysisYearOnYear => 'Year on year';

  @override
  String get analysisMonthOnMonth => 'Month on month';

  @override
  String get analysisCategory => 'Category';

  @override
  String get noAnalysisData => 'No recorded data matches this selection.';

  @override
  String get noBudgetRecorded =>
      'No AGM-approved budget has been recorded for this association.';

  @override
  String get analysisExportHint =>
      'Use Statements to export the live ledger CSV';

  @override
  String get budgetVsActual => 'Budget vs actual';

  @override
  String get differentReviewerRequired => 'A different reviewer is required';

  @override
  String get vehicleLookup => 'Vehicle lookup';

  @override
  String get vehicleRegistration => 'Vehicle registration number';

  @override
  String get searchVehicleNumber => 'Search vehicle number';

  @override
  String get enterThreeVehicleChars =>
      'Enter at least 3 characters from the vehicle number';

  @override
  String get noRegisteredVehicleMatch =>
      'No registered vehicle matches that number.';

  @override
  String vehicleSearchFailed(Object error) {
    return 'Could not search vehicles: $error';
  }

  @override
  String get noActiveOccupant => 'No active owner/tenant recorded';

  @override
  String get noPhoneOnRecord => 'No phone on record';

  @override
  String get exportBoomBarrierCsv => 'Export boom-barrier CSV';

  @override
  String get meetingsUpcoming => 'Upcoming';

  @override
  String get meetingsPast => 'Past';

  @override
  String get scheduleMeeting => 'Schedule meeting';

  @override
  String get meetingType => 'Meeting type';

  @override
  String get meetingTitle => 'Title';

  @override
  String get meetingAgenda => 'Agenda (one per line)';

  @override
  String get meetingSaved =>
      'Only in-app alerts are queued; email, calendar and WhatsApp delivery is not configured.';

  @override
  String get minutesTitle => 'Meeting minutes';

  @override
  String get minutesDraft => 'Draft minutes';

  @override
  String get minutesPendingApproval => 'Awaiting President approval';

  @override
  String get minutesApproved => 'Approved minutes';

  @override
  String get writeMinutes => 'Write minutes';

  @override
  String get editMinutes => 'Edit minutes';

  @override
  String get submitForApproval => 'Submit for approval';

  @override
  String get approveMinutes => 'Approve minutes';

  @override
  String get viewMinutes => 'View minutes';

  @override
  String get saveDraft => 'Save draft';

  @override
  String get meetingReschedule => 'Reschedule';

  @override
  String get cancel => 'Cancel';

  @override
  String get noUpcomingMeetings => 'No upcoming meetings';

  @override
  String get noPastMeetings => 'No past meetings';

  @override
  String get inPerson => 'In person';

  @override
  String get online => 'Online';

  @override
  String get hybrid => 'Hybrid';

  @override
  String get platform => 'Platform';

  @override
  String get accept => 'Accept';

  @override
  String get tentative => 'Tentative';

  @override
  String get decline => 'Decline';

  @override
  String get accepted => 'accepted';

  @override
  String get tentativeCount => 'tentative';

  @override
  String get declined => 'declined';

  @override
  String get noReply => 'no reply';

  @override
  String get meetingLinkNotConfigured => 'Meeting link not configured';

  @override
  String get minutesPending => 'Minutes pending';

  @override
  String get attendance => 'Attendance';

  @override
  String get householdStaff => 'Household staff';

  @override
  String get visitors => 'Visitors';

  @override
  String get archive => 'Archive';

  @override
  String get registers => 'Assets & expiry';

  @override
  String get amenities => 'Amenities';

  @override
  String get community => 'Community';

  @override
  String get associationDocuments => 'Association documents';

  @override
  String get visitorRegister => 'Visitor register';

  @override
  String get preregisterVisitor => 'Pre-register visitor';

  @override
  String get visitorHostIntro =>
      'Register an expected visit for your flat. Security and the caretaker can verify arrival.';

  @override
  String get visitorGateIntro =>
      'Check the guest name, host flat, arrival time and vehicle before verifying entry.';

  @override
  String get visitorRoleIntro =>
      'Visitor requests are visible only within this association and to the relevant entry staff.';

  @override
  String get visitorRequestSent => 'Visitor request sent to the entry register';

  @override
  String get visitorHost => 'Host';

  @override
  String get expectedArrival => 'Expected arrival';

  @override
  String get noVisitorRequests => 'No visitor requests found.';

  @override
  String get verifyEntry => 'Verify entry';

  @override
  String get checkOut => 'Check out';

  @override
  String get visitorVehicle => 'Visitor vehicle';

  @override
  String get registeredVehicles => 'Registered';

  @override
  String get slot => 'slot';

  @override
  String get vehicleExportTitle => 'Export boom-barrier vehicle list';

  @override
  String vehicleExportComplete(int count) {
    return 'Exported $count registered vehicles';
  }

  @override
  String get annualBudget => 'AGM-approved annual budgets';

  @override
  String get submitBudget => 'Submit budget';

  @override
  String get annualBudgetReference => 'AGM/GBM resolution reference';

  @override
  String get annualBudgetDate => 'Resolution date';

  @override
  String get annualBudgetRequiredCategory =>
      'Enter at least one category amount';

  @override
  String get annualBudgetNoRecords => 'No annual budgets recorded.';

  @override
  String get awaitingSecretary => 'Awaiting Secretary';

  @override
  String get awaitingPresident => 'Awaiting President';

  @override
  String get reviewerDifferent => 'A different reviewer is required.';

  @override
  String get submitBudgetReview => 'Submit for review';

  @override
  String get recordPayment => 'Record payment';

  @override
  String get raiseDues => 'Raise dues';

  @override
  String get openingBalance => 'Opening balance';

  @override
  String get setOpeningBalance => 'Set opening balance';

  @override
  String get editOpeningBalance => 'Edit opening balance';

  @override
  String get noDues => 'No dues';

  @override
  String get pendingDues => 'Pending dues';

  @override
  String get lateFeeFixed => 'Fixed late fee';

  @override
  String get perSqFtRate => 'Rate per sq ft';

  @override
  String get flatTypeAmount => 'Amount per flat type (leave empty to skip)';

  @override
  String get recordPaymentReceived => 'Record payment received';

  @override
  String get saveReceipt => 'Save & issue receipt';

  @override
  String get paymentReceived => 'Amount received';

  @override
  String get paymentMode => 'Mode';

  @override
  String get paymentReference => 'Reference';

  @override
  String get save => 'Save';

  @override
  String get account => 'Account';

  @override
  String get balance => 'Balance';

  @override
  String get fixedLateAmount => 'Fixed amount per flat';

  @override
  String get duesName => 'Name';

  @override
  String get dueBy => 'Due by';

  @override
  String get createAssociation => 'Create association';

  @override
  String get firstAssociationSetup => 'Set up your association';

  @override
  String get verifiedEmailNoAssociation =>
      'Verified email with no existing association';

  @override
  String get adminName => 'Your full name';

  @override
  String get familyDobPrivacyNotice =>
      'Family dates of birth are securely stored and visible only to the owner/resident account that submits them. No other account, including association staff, can view them.';
}
