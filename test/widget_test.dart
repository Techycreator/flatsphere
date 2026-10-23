import 'package:flatsphere/app/router.dart';
import 'package:flatsphere/app/nav.dart';
import 'package:flatsphere/features/approvals/membership_request_screen.dart';
import 'package:flatsphere/features/directory/family_accounts_screen.dart';
import 'package:flatsphere/features/dashboard/dashboard_screen.dart';
import 'package:flatsphere/features/shell/association_settings_screen.dart';
import 'package:flatsphere/l10n/app_localizations.dart';
import 'package:flatsphere/main.dart';
import 'package:flatsphere/models/models.dart';
import 'package:flatsphere/models/sla.dart';
import 'package:flatsphere/state/app_state.dart';
import 'package:flatsphere/state/directory_state.dart';
import 'package:flatsphere/state/demo_data.dart';
import 'package:flatsphere/validation/input_validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Complaint _c(Criticality crit, DateTime created) => Complaint(
  id: 'X',
  flatNumber: 'A-1',
  type: TicketType.complaint,
  category: 'Other',
  title: 't',
  description: '',
  criticality: crit,
  status: TicketStatus.newTicket,
  createdAt: created,
  raisedBy: 'r',
);

class _SignedInSessionNotifier extends SessionNotifier {
  @override
  Session? build() => Session(user: demoUsers.first, activeRole: Role.secretary);
}

class _LoadingDirectoryNotifier extends DirectoryNotifier {
  @override
  DirectoryState build() => const DirectoryState(loading: true);
}

class _OwnerSessionNotifier extends SessionNotifier {
  @override
  Session? build() => Session(
    user: demoUsers.firstWhere((user) => user.roles.contains(Role.owner)),
    activeRole: Role.owner,
  );
}

class _AdminSessionNotifier extends SessionNotifier {
  @override
  Session? build() => Session(
    user: const DemoUser(id: 'admin-test', name: 'Admin Test', mobile: '', roles: [Role.admin]),
    activeRole: Role.admin,
  );
}

void main() {
  group('SLA colours (medium: blue day 0, amber 1-5, red 6+)', () {
    final now = DateTime(2026, 10, 16, 12);
    test('medium', () {
      expect(slaFor(_c(Criticality.medium, now), now).color, SlaColor.blue);
      expect(slaFor(_c(Criticality.medium, now.subtract(const Duration(days: 1))), now).color, SlaColor.amber);
      expect(slaFor(_c(Criticality.medium, now.subtract(const Duration(days: 5))), now).color, SlaColor.amber);
      expect(slaFor(_c(Criticality.medium, now.subtract(const Duration(days: 6))), now).color, SlaColor.red);
    });
    test('critical is measured in hours', () {
      expect(slaFor(_c(Criticality.critical, now.subtract(const Duration(hours: 1))), now).color, SlaColor.blue);
      expect(slaFor(_c(Criticality.critical, now.subtract(const Duration(hours: 3))), now).color, SlaColor.amber);
      expect(slaFor(_c(Criticality.critical, now.subtract(const Duration(hours: 7))), now).color, SlaColor.red);
    });
  });

  test('AI criticality stub flags a stuck lift as critical', () {
    expect(suggestCriticality('Lift stuck on 3rd floor')!.criticality, Criticality.critical);
  });

  testWidgets('demo persona login shows dashboard', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: FlatSphereApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anitha Nair'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome, Anitha'), findsOneWidget);
    expect(find.text('Secretary view · Flat A-203'), findsOneWidget);
  });

  testWidgets('membership request waits for live directory data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_SignedInSessionNotifier.new),
          directoryProvider.overrideWith(_LoadingDirectoryNotifier.new),
        ],
        child: const MaterialApp(home: MembershipRequestScreen(type: MembershipRequestType.resident)),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('owner sees the DOB privacy notice in family accounts', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_OwnerSessionNotifier.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FamilyAccountsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Family dates of birth are securely stored'), findsOneWidget);
    expect(find.text('No family members are recorded for your flat yet.'), findsOneWidget);
  });

  testWidgets('non-household role is denied family DOB screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_SignedInSessionNotifier.new)],
        child: const MaterialApp(home: FamilyAccountsScreen()),
      ),
    );
    expect(find.text('Only owners and residents can view family DOBs.'), findsOneWidget);
  });

  testWidgets('Admin settings expose ID-document access controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_AdminSessionNotifier.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AssociationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ID document access'), findsOneWidget);
    expect(find.text('Connect Supabase to manage ID-document access.'), findsOneWidget);
  });

  testWidgets('SLA summary shows only active statuses with single-line labels', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_SignedInSessionNotifier.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder labelMatching(RegExp expression) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.data != null && expression.hasMatch(widget.data!),
    );
    expect(labelMatching(RegExp(r'^Open \d+$')), findsOneWidget);
    expect(labelMatching(RegExp(r'^Attention \d+$')), findsOneWidget);
    expect(labelMatching(RegExp(r'^Overdue \d+$')), findsOneWidget);
    expect(labelMatching(RegExp(r'^(Done|Closed) \d+$')), findsNothing);
    expect(find.byType(FittedBox), findsAtLeastNWidgets(3));
  });

  group('route guard', () {
    test('resident cannot deep-link to finance or dues', () {
      expect(canAccess(Role.resident, '/finance'), isFalse);
      expect(canAccess(Role.resident, '/dues'), isFalse);
      expect(canAccess(Role.resident, '/complaints/new'), isTrue);
    });
    test('owner can open approvals for consent; auditor limited to finance', () {
      expect(canAccess(Role.owner, '/approvals/APR-034'), isTrue);
      expect(canAccess(Role.auditor, '/complaints'), isFalse);
      expect(canAccess(Role.auditor, '/finance'), isTrue);
      expect(canAccess(Role.ecMember, '/approvals/new/owner'), isFalse);
      expect(canAccess(Role.secretary, '/finance/analysis'), isTrue);
      expect(canAccess(Role.jointSecretary, '/finance'), isTrue);
      expect(canAccess(Role.vicePresident, '/finance'), isTrue);
      expect(canAccess(Role.jointTreasurer, '/finance'), isTrue);
      expect(canAccess(Role.ecMember, '/approvals/new/owner', membershipDesk: true), isTrue);
      expect(canAccess(Role.ecMember, '/meetings', membershipDesk: true), isTrue);
      expect(navFor(Role.ecMember, membershipDesk: true).map((i) => i.path), contains('/approvals'));
    });
    test('family account screen is limited to owner and resident roles', () {
      expect(canAccess(Role.owner, '/family-accounts'), isTrue);
      expect(canAccess(Role.resident, '/family-accounts'), isTrue);
      for (final role in Role.values.where((role) => role != Role.owner && role != Role.resident)) {
        expect(canAccess(role, '/family-accounts'), isFalse, reason: '${role.name} must not access family DOBs');
      }
    });
  });

  group('family account policy boundaries', () {
    final dateOfBirth = DateTime(2014, 10, 23);
    test('login eligibility begins on the configured birthday', () {
      expect(FamilyAccountRules.isLoginEligible(dateOfBirth, 12, DateTime(2026, 10, 22)), isFalse);
      expect(FamilyAccountRules.isLoginEligible(dateOfBirth, 12, DateTime(2026, 10, 23)), isTrue);
      expect(FamilyAccountRules.isLoginEligible(dateOfBirth, 12, DateTime(2026, 10, 24)), isTrue);
      expect(FamilyAccountRules.isLoginEligible(dateOfBirth, 0, DateTime(2026, 10, 23)), isFalse);
    });
    test('dependent count accepts the cap and rejects overflow/negative values', () {
      expect(FamilyAccountRules.isWithinMemberLimit(5, 5), isTrue);
      expect(FamilyAccountRules.isWithinMemberLimit(6, 5), isFalse);
      expect(FamilyAccountRules.isWithinMemberLimit(-1, 5), isFalse);
    });
  });

  group('contact input validation', () {
    test('accepts email addresses and rejects plain text or malformed domains', () {
      expect(InputValidation.isEmail('ajeesh@example.org'), isTrue);
      expect(InputValidation.isEmail('person+tag@example.co.in'), isTrue);
      expect(InputValidation.isEmail('not an email'), isFalse);
      expect(InputValidation.isEmail('person@localhost'), isFalse);
    });
    test('accepts optional blank phones and rejects invalid phone text/ranges', () {
      expect(InputValidation.isOptionalPhone(''), isTrue);
      expect(InputValidation.isPhone('+91 98765 43210'), isTrue);
      expect(InputValidation.isOptionalPhone('call me'), isFalse);
      expect(InputValidation.isPhone('123'), isFalse);
    });
    test('accepts registration-like values and rejects prose as a vehicle number', () {
      expect(InputValidation.isVehicleRegistration('KL 07 AB 1234'), isTrue);
      expect(InputValidation.isVehicleRegistration('hello world'), isFalse);
      expect(InputValidation.isVehicleRegistration('AB-12'), isFalse);
    });
  });

  test('W21 owner-consent step only matches the named owner; either/or step matches both roles', () {
    const owner = ApproverStep(role: Role.owner, name: 'Priya Varghese');
    expect(owner.matches(Role.owner, 'Priya Varghese'), isTrue);
    expect(owner.matches(Role.owner, 'Someone Else'), isFalse);
    const either = ApproverStep(role: Role.secretary, alternateRole: Role.president, name: 'x');
    expect(either.matches(Role.president, 'Rajesh Menon'), isTrue);
    expect(either.matches(Role.treasurer, 'Thomas Kurian'), isFalse);
  });

  test('income can only be recorded to an active category', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(incomeProvider.notifier);
    final active = container.read(incomeProvider).categories.first;
    final requestRef = await notifier.requestCategory('Hall rental');
    final pending = container.read(incomeProvider).categories.firstWhere((c) => c.requestRef == requestRef);
    expect(pending.status, IncomeCategoryStatus.pending);
    await expectLater(
      notifier.record(
        categoryId: pending.id,
        receivedOn: DateTime(2026, 10, 22),
        amount: 10000,
        source: 'Resident booking',
        description: '',
      ),
      throwsStateError,
    );
    await notifier.record(
      categoryId: active.id,
      receivedOn: DateTime(2026, 10, 22),
      amount: 10000,
      source: 'Resident booking',
      description: 'Hall rental',
    );
    expect(container.read(incomeProvider).entries.single.categoryName, active.name);
  });

  test('items awaiting Secretary review and enhancements have no SLA colour', () {
    final c = _c(Criticality.medium, DateTime(2026, 10, 1));
    expect(c.slaApplies, isTrue);
    expect(c.copyWith(status: TicketStatus.pendingReview).slaApplies, isFalse);
    expect(c.copyWith(kind: ReportKind.enhancementImmediate).slaApplies, isFalse);
  });
}
