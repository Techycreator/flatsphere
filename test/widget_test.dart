import 'package:flatsphere/app/router.dart';
import 'package:flatsphere/app/nav.dart';
import 'package:flatsphere/main.dart';
import 'package:flatsphere/models/models.dart';
import 'package:flatsphere/models/sla.dart';
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

void main() {
  group('SLA colours (medium: green day 0, amber 1-5, red 6+)', () {
    final now = DateTime(2026, 10, 16, 12);
    test('medium', () {
      expect(slaFor(_c(Criticality.medium, now), now).color, SlaColor.green);
      expect(slaFor(_c(Criticality.medium, now.subtract(const Duration(days: 1))), now).color, SlaColor.amber);
      expect(slaFor(_c(Criticality.medium, now.subtract(const Duration(days: 5))), now).color, SlaColor.amber);
      expect(slaFor(_c(Criticality.medium, now.subtract(const Duration(days: 6))), now).color, SlaColor.red);
    });
    test('critical is measured in hours', () {
      expect(slaFor(_c(Criticality.critical, now.subtract(const Duration(hours: 1))), now).color, SlaColor.green);
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
  });

  test('W21 owner-consent step only matches the named owner; either/or step matches both roles', () {
    const owner = ApproverStep(role: Role.owner, name: 'Priya Varghese');
    expect(owner.matches(Role.owner, 'Priya Varghese'), isTrue);
    expect(owner.matches(Role.owner, 'Someone Else'), isFalse);
    const either = ApproverStep(role: Role.secretary, alternateRole: Role.president, name: 'x');
    expect(either.matches(Role.president, 'Rajesh Menon'), isTrue);
    expect(either.matches(Role.treasurer, 'Thomas Kurian'), isFalse);
  });

  test('items awaiting Secretary review and enhancements have no SLA colour', () {
    final c = _c(Criticality.medium, DateTime(2026, 10, 1));
    expect(c.slaApplies, isTrue);
    expect(c.copyWith(status: TicketStatus.pendingReview).slaApplies, isFalse);
    expect(c.copyWith(kind: ReportKind.enhancementImmediate).slaApplies, isFalse);
  });
}
