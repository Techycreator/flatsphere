import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ml.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ml'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'FlatSphere'**
  String get appTitle;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @complaints.
  ///
  /// In en, this message translates to:
  /// **'Complaints'**
  String get complaints;

  /// No description provided for @checklist.
  ///
  /// In en, this message translates to:
  /// **'Daily checklist'**
  String get checklist;

  /// No description provided for @approvals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvals;

  /// No description provided for @finance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get finance;

  /// No description provided for @myDues.
  ///
  /// In en, this message translates to:
  /// **'My dues'**
  String get myDues;

  /// No description provided for @meetings.
  ///
  /// In en, this message translates to:
  /// **'Meetings'**
  String get meetings;

  /// No description provided for @directory.
  ///
  /// In en, this message translates to:
  /// **'Flats & people'**
  String get directory;

  /// No description provided for @notices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get notices;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get mobileNumber;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// No description provided for @enterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get enterOtp;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @sendBack.
  ///
  /// In en, this message translates to:
  /// **'Send back'**
  String get sendBack;

  /// No description provided for @raiseComplaint.
  ///
  /// In en, this message translates to:
  /// **'Raise complaint'**
  String get raiseComplaint;

  /// No description provided for @payNow.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get payNow;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @switchRole.
  ///
  /// In en, this message translates to:
  /// **'Switch role'**
  String get switchRole;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @recordVoice.
  ///
  /// In en, this message translates to:
  /// **'Record voice note'**
  String get recordVoice;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @pendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'Pending approvals'**
  String get pendingApprovals;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @demoPersonas.
  ///
  /// In en, this message translates to:
  /// **'Demo mode – choose a user to explore their view'**
  String get demoPersonas;

  /// No description provided for @associationSettings.
  ///
  /// In en, this message translates to:
  /// **'Association settings'**
  String get associationSettings;

  /// No description provided for @associationIdentity.
  ///
  /// In en, this message translates to:
  /// **'Association identity'**
  String get associationIdentity;

  /// No description provided for @associationName.
  ///
  /// In en, this message translates to:
  /// **'Association name'**
  String get associationName;

  /// No description provided for @state.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get state;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @brandColor.
  ///
  /// In en, this message translates to:
  /// **'Brand color'**
  String get brandColor;

  /// No description provided for @operatingDefaults.
  ///
  /// In en, this message translates to:
  /// **'Operating defaults'**
  String get operatingDefaults;

  /// No description provided for @fiscalYearStartMonth.
  ///
  /// In en, this message translates to:
  /// **'Financial year start month'**
  String get fiscalYearStartMonth;

  /// No description provided for @defaultDueDay.
  ///
  /// In en, this message translates to:
  /// **'Default monthly due day'**
  String get defaultDueDay;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @billingProviderNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Billing provider not configured'**
  String get billingProviderNotConfigured;

  /// No description provided for @billingProviderDescription.
  ///
  /// In en, this message translates to:
  /// **'Subscription plans and payments need an approved billing provider and pricing.'**
  String get billingProviderDescription;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get saveSettings;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Association settings saved'**
  String get settingsSaved;

  /// No description provided for @ageNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Age not recorded'**
  String get ageNotRecorded;

  /// No description provided for @child.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get child;

  /// No description provided for @adult.
  ///
  /// In en, this message translates to:
  /// **'Adult'**
  String get adult;

  /// No description provided for @seniorCitizen.
  ///
  /// In en, this message translates to:
  /// **'Senior citizen'**
  String get seniorCitizen;

  /// No description provided for @dateOfBirthOptional.
  ///
  /// In en, this message translates to:
  /// **'Date of birth (optional)'**
  String get dateOfBirthOptional;

  /// No description provided for @birthdayWish.
  ///
  /// In en, this message translates to:
  /// **'Happy birthday, {name}! Wishing you a wonderful year ahead.'**
  String birthdayWish(String name);

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @exportLedgerCsv.
  ///
  /// In en, this message translates to:
  /// **'Export ledger CSV'**
  String get exportLedgerCsv;

  /// No description provided for @applyLateFee.
  ///
  /// In en, this message translates to:
  /// **'Apply late fee'**
  String get applyLateFee;

  /// No description provided for @perSquareFootCharge.
  ///
  /// In en, this message translates to:
  /// **'Per-square-foot charge'**
  String get perSquareFootCharge;

  /// No description provided for @meetingInvitesNotSent.
  ///
  /// In en, this message translates to:
  /// **'Meeting saved. Notifications have not been sent.'**
  String get meetingInvitesNotSent;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @adminRequired.
  ///
  /// In en, this message translates to:
  /// **'Association Admin access is required.'**
  String get adminRequired;

  /// No description provided for @createStatement.
  ///
  /// In en, this message translates to:
  /// **'Create statement'**
  String get createStatement;

  /// No description provided for @monthlyStatementDescription.
  ///
  /// In en, this message translates to:
  /// **'Monthly income, dues, receipts and approved expenses'**
  String get monthlyStatementDescription;

  /// No description provided for @statementApprovalDescription.
  ///
  /// In en, this message translates to:
  /// **'Owners can view a statement after three separate approvals. Published snapshots are immutable.'**
  String get statementApprovalDescription;

  /// No description provided for @noStatements.
  ///
  /// In en, this message translates to:
  /// **'No monthly statements yet.'**
  String get noStatements;

  /// No description provided for @published.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get published;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @statementAwaitingTreasurer.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Treasurer'**
  String get statementAwaitingTreasurer;

  /// No description provided for @statementAwaitingSecretary.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Secretary'**
  String get statementAwaitingSecretary;

  /// No description provided for @statementAwaitingPresident.
  ///
  /// In en, this message translates to:
  /// **'Awaiting President'**
  String get statementAwaitingPresident;

  /// No description provided for @incomeTotal.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomeTotal;

  /// No description provided for @approvedExpenses.
  ///
  /// In en, this message translates to:
  /// **'Approved expenses'**
  String get approvedExpenses;

  /// No description provided for @paymentsReceived.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentsReceived;

  /// No description provided for @analysisYearOnYear.
  ///
  /// In en, this message translates to:
  /// **'Year on year'**
  String get analysisYearOnYear;

  /// No description provided for @analysisMonthOnMonth.
  ///
  /// In en, this message translates to:
  /// **'Month on month'**
  String get analysisMonthOnMonth;

  /// No description provided for @analysisCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get analysisCategory;

  /// No description provided for @noAnalysisData.
  ///
  /// In en, this message translates to:
  /// **'No recorded data matches this selection.'**
  String get noAnalysisData;

  /// No description provided for @noBudgetRecorded.
  ///
  /// In en, this message translates to:
  /// **'No AGM-approved budget has been recorded for this association.'**
  String get noBudgetRecorded;

  /// No description provided for @analysisExportHint.
  ///
  /// In en, this message translates to:
  /// **'Use Statements to export the live ledger CSV'**
  String get analysisExportHint;

  /// No description provided for @budgetVsActual.
  ///
  /// In en, this message translates to:
  /// **'Budget vs actual'**
  String get budgetVsActual;

  /// No description provided for @differentReviewerRequired.
  ///
  /// In en, this message translates to:
  /// **'A different reviewer is required'**
  String get differentReviewerRequired;

  /// No description provided for @vehicleLookup.
  ///
  /// In en, this message translates to:
  /// **'Vehicle lookup'**
  String get vehicleLookup;

  /// No description provided for @vehicleRegistration.
  ///
  /// In en, this message translates to:
  /// **'Vehicle registration number'**
  String get vehicleRegistration;

  /// No description provided for @searchVehicleNumber.
  ///
  /// In en, this message translates to:
  /// **'Search vehicle number'**
  String get searchVehicleNumber;

  /// No description provided for @enterThreeVehicleChars.
  ///
  /// In en, this message translates to:
  /// **'Enter at least 3 characters from the vehicle number'**
  String get enterThreeVehicleChars;

  /// No description provided for @noRegisteredVehicleMatch.
  ///
  /// In en, this message translates to:
  /// **'No registered vehicle matches that number.'**
  String get noRegisteredVehicleMatch;

  /// No description provided for @vehicleSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not search vehicles: {error}'**
  String vehicleSearchFailed(Object error);

  /// No description provided for @noActiveOccupant.
  ///
  /// In en, this message translates to:
  /// **'No active owner/tenant recorded'**
  String get noActiveOccupant;

  /// No description provided for @noPhoneOnRecord.
  ///
  /// In en, this message translates to:
  /// **'No phone on record'**
  String get noPhoneOnRecord;

  /// No description provided for @exportBoomBarrierCsv.
  ///
  /// In en, this message translates to:
  /// **'Export boom-barrier CSV'**
  String get exportBoomBarrierCsv;

  /// No description provided for @meetingsUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get meetingsUpcoming;

  /// No description provided for @meetingsPast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get meetingsPast;

  /// No description provided for @scheduleMeeting.
  ///
  /// In en, this message translates to:
  /// **'Schedule meeting'**
  String get scheduleMeeting;

  /// No description provided for @meetingType.
  ///
  /// In en, this message translates to:
  /// **'Meeting type'**
  String get meetingType;

  /// No description provided for @meetingTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get meetingTitle;

  /// No description provided for @meetingAgenda.
  ///
  /// In en, this message translates to:
  /// **'Agenda (one per line)'**
  String get meetingAgenda;

  /// No description provided for @meetingSaved.
  ///
  /// In en, this message translates to:
  /// **'Only in-app alerts are queued; email, calendar and WhatsApp delivery is not configured.'**
  String get meetingSaved;

  /// No description provided for @minutesTitle.
  ///
  /// In en, this message translates to:
  /// **'Meeting minutes'**
  String get minutesTitle;

  /// No description provided for @minutesDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft minutes'**
  String get minutesDraft;

  /// No description provided for @minutesPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting President approval'**
  String get minutesPendingApproval;

  /// No description provided for @minutesApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved minutes'**
  String get minutesApproved;

  /// No description provided for @writeMinutes.
  ///
  /// In en, this message translates to:
  /// **'Write minutes'**
  String get writeMinutes;

  /// No description provided for @editMinutes.
  ///
  /// In en, this message translates to:
  /// **'Edit minutes'**
  String get editMinutes;

  /// No description provided for @submitForApproval.
  ///
  /// In en, this message translates to:
  /// **'Submit for approval'**
  String get submitForApproval;

  /// No description provided for @approveMinutes.
  ///
  /// In en, this message translates to:
  /// **'Approve minutes'**
  String get approveMinutes;

  /// No description provided for @viewMinutes.
  ///
  /// In en, this message translates to:
  /// **'View minutes'**
  String get viewMinutes;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// No description provided for @meetingReschedule.
  ///
  /// In en, this message translates to:
  /// **'Reschedule'**
  String get meetingReschedule;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @noUpcomingMeetings.
  ///
  /// In en, this message translates to:
  /// **'No upcoming meetings'**
  String get noUpcomingMeetings;

  /// No description provided for @noPastMeetings.
  ///
  /// In en, this message translates to:
  /// **'No past meetings'**
  String get noPastMeetings;

  /// No description provided for @inPerson.
  ///
  /// In en, this message translates to:
  /// **'In person'**
  String get inPerson;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @hybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get hybrid;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @tentative.
  ///
  /// In en, this message translates to:
  /// **'Tentative'**
  String get tentative;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @accepted.
  ///
  /// In en, this message translates to:
  /// **'accepted'**
  String get accepted;

  /// No description provided for @tentativeCount.
  ///
  /// In en, this message translates to:
  /// **'tentative'**
  String get tentativeCount;

  /// No description provided for @declined.
  ///
  /// In en, this message translates to:
  /// **'declined'**
  String get declined;

  /// No description provided for @noReply.
  ///
  /// In en, this message translates to:
  /// **'no reply'**
  String get noReply;

  /// No description provided for @meetingLinkNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Meeting link not configured'**
  String get meetingLinkNotConfigured;

  /// No description provided for @minutesPending.
  ///
  /// In en, this message translates to:
  /// **'Minutes pending'**
  String get minutesPending;

  /// No description provided for @attendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendance;

  /// No description provided for @householdStaff.
  ///
  /// In en, this message translates to:
  /// **'Household staff'**
  String get householdStaff;

  /// No description provided for @visitors.
  ///
  /// In en, this message translates to:
  /// **'Visitors'**
  String get visitors;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @registers.
  ///
  /// In en, this message translates to:
  /// **'Assets & expiry'**
  String get registers;

  /// No description provided for @amenities.
  ///
  /// In en, this message translates to:
  /// **'Amenities'**
  String get amenities;

  /// No description provided for @community.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get community;

  /// No description provided for @associationDocuments.
  ///
  /// In en, this message translates to:
  /// **'Association documents'**
  String get associationDocuments;

  /// No description provided for @visitorRegister.
  ///
  /// In en, this message translates to:
  /// **'Visitor register'**
  String get visitorRegister;

  /// No description provided for @preregisterVisitor.
  ///
  /// In en, this message translates to:
  /// **'Pre-register visitor'**
  String get preregisterVisitor;

  /// No description provided for @visitorHostIntro.
  ///
  /// In en, this message translates to:
  /// **'Register an expected visit for your flat. Security and the caretaker can verify arrival.'**
  String get visitorHostIntro;

  /// No description provided for @visitorGateIntro.
  ///
  /// In en, this message translates to:
  /// **'Check the guest name, host flat, arrival time and vehicle before verifying entry.'**
  String get visitorGateIntro;

  /// No description provided for @visitorRoleIntro.
  ///
  /// In en, this message translates to:
  /// **'Visitor requests are visible only within this association and to the relevant entry staff.'**
  String get visitorRoleIntro;

  /// No description provided for @visitorRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Visitor request sent to the entry register'**
  String get visitorRequestSent;

  /// No description provided for @visitorHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get visitorHost;

  /// No description provided for @expectedArrival.
  ///
  /// In en, this message translates to:
  /// **'Expected arrival'**
  String get expectedArrival;

  /// No description provided for @noVisitorRequests.
  ///
  /// In en, this message translates to:
  /// **'No visitor requests found.'**
  String get noVisitorRequests;

  /// No description provided for @verifyEntry.
  ///
  /// In en, this message translates to:
  /// **'Verify entry'**
  String get verifyEntry;

  /// No description provided for @checkOut.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get checkOut;

  /// No description provided for @visitorVehicle.
  ///
  /// In en, this message translates to:
  /// **'Visitor vehicle'**
  String get visitorVehicle;

  /// No description provided for @registeredVehicles.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get registeredVehicles;

  /// No description provided for @slot.
  ///
  /// In en, this message translates to:
  /// **'slot'**
  String get slot;

  /// No description provided for @vehicleExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export boom-barrier vehicle list'**
  String get vehicleExportTitle;

  /// No description provided for @vehicleExportComplete.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} registered vehicles'**
  String vehicleExportComplete(int count);

  /// No description provided for @annualBudget.
  ///
  /// In en, this message translates to:
  /// **'AGM-approved annual budgets'**
  String get annualBudget;

  /// No description provided for @submitBudget.
  ///
  /// In en, this message translates to:
  /// **'Submit budget'**
  String get submitBudget;

  /// No description provided for @annualBudgetReference.
  ///
  /// In en, this message translates to:
  /// **'AGM/GBM resolution reference'**
  String get annualBudgetReference;

  /// No description provided for @annualBudgetDate.
  ///
  /// In en, this message translates to:
  /// **'Resolution date'**
  String get annualBudgetDate;

  /// No description provided for @annualBudgetRequiredCategory.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one category amount'**
  String get annualBudgetRequiredCategory;

  /// No description provided for @annualBudgetNoRecords.
  ///
  /// In en, this message translates to:
  /// **'No annual budgets recorded.'**
  String get annualBudgetNoRecords;

  /// No description provided for @awaitingSecretary.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Secretary'**
  String get awaitingSecretary;

  /// No description provided for @awaitingPresident.
  ///
  /// In en, this message translates to:
  /// **'Awaiting President'**
  String get awaitingPresident;

  /// No description provided for @reviewerDifferent.
  ///
  /// In en, this message translates to:
  /// **'A different reviewer is required.'**
  String get reviewerDifferent;

  /// No description provided for @submitBudgetReview.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get submitBudgetReview;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recordPayment;

  /// No description provided for @raiseDues.
  ///
  /// In en, this message translates to:
  /// **'Raise dues'**
  String get raiseDues;

  /// No description provided for @openingBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get openingBalance;

  /// No description provided for @setOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Set opening balance'**
  String get setOpeningBalance;

  /// No description provided for @editOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Edit opening balance'**
  String get editOpeningBalance;

  /// No description provided for @noDues.
  ///
  /// In en, this message translates to:
  /// **'No dues'**
  String get noDues;

  /// No description provided for @pendingDues.
  ///
  /// In en, this message translates to:
  /// **'Pending dues'**
  String get pendingDues;

  /// No description provided for @lateFeeFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed late fee'**
  String get lateFeeFixed;

  /// No description provided for @perSqFtRate.
  ///
  /// In en, this message translates to:
  /// **'Rate per sq ft'**
  String get perSqFtRate;

  /// No description provided for @flatTypeAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount per flat type (leave empty to skip)'**
  String get flatTypeAmount;

  /// No description provided for @recordPaymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Record payment received'**
  String get recordPaymentReceived;

  /// No description provided for @saveReceipt.
  ///
  /// In en, this message translates to:
  /// **'Save & issue receipt'**
  String get saveReceipt;

  /// No description provided for @paymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Amount received'**
  String get paymentReceived;

  /// No description provided for @paymentMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get paymentMode;

  /// No description provided for @paymentReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get paymentReference;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @fixedLateAmount.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount per flat'**
  String get fixedLateAmount;

  /// No description provided for @duesName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get duesName;

  /// No description provided for @dueBy.
  ///
  /// In en, this message translates to:
  /// **'Due by'**
  String get dueBy;

  /// No description provided for @createAssociation.
  ///
  /// In en, this message translates to:
  /// **'Create association'**
  String get createAssociation;

  /// No description provided for @firstAssociationSetup.
  ///
  /// In en, this message translates to:
  /// **'Set up your association'**
  String get firstAssociationSetup;

  /// No description provided for @verifiedEmailNoAssociation.
  ///
  /// In en, this message translates to:
  /// **'Verified email with no existing association'**
  String get verifiedEmailNoAssociation;

  /// No description provided for @adminName.
  ///
  /// In en, this message translates to:
  /// **'Your full name'**
  String get adminName;

  /// No description provided for @familyDobPrivacyNotice.
  ///
  /// In en, this message translates to:
  /// **'Family dates of birth are securely stored and visible only to the owner/resident account that submits them. No other account, including association staff, can view them.'**
  String get familyDobPrivacyNotice;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ml'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ml':
      return AppLocalizationsMl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
