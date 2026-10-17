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
}
