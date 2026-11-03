import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flatsphere/backend/backend.dart' show AssociationContext;
import 'package:flatsphere/backend/gate_offline.dart';
import 'package:flatsphere/backend/gate_repo.dart';
import 'package:flatsphere/features/visitors/gate_widgets.dart';
import 'package:flatsphere/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _phone(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(360, 740) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

void main() {
  testWidgets('pass code pad shows typed digits and enables Check in at 6', (tester) async {
    await _phone(tester, const CodePad(title: 'Visitor pass code', action: 'Check in'));
    expect(find.bySemanticsLabel('Backspace'), findsOneWidget);
    for (final d in ['1', '2', '3', '4', '5']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
    }
    await tester.pump();
    expect(find.text('5'), findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, '6'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('walk-in suggests flats as you type and fits a phone', (tester) async {
    await _phone(tester, const WalkInPage(flats: ['A-101', 'A-102', 'B-101', 'C-201']));
    await tester.enterText(find.byType(TextField).first, 'a1');
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'A-101'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'B-101'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'A-102'));
    await tester.pump();
    expect(find.text('Flat A-102'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty flat list submits the normalized flat number once', (tester) async {
    String? submitted;
    var submissions = 0;
    await _phone(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: FlatPicker(
            flats: const [],
            onChanged: (_) {},
            onSubmitted: (flat) {
              submitted = flat;
              submissions++;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), ' a-101 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, 'A-101');
    expect(submissions, 1);
  });

  test('cached gate flats are scoped to their association', () async {
    SharedPreferences.setMockInitialValues({});
    await GateOffline.cacheFlats('association-a', ['A-101']);
    await GateOffline.cacheFlats('association-b', ['B-202']);
    expect(await GateOffline.cachedFlats('association-a'), ['A-101']);
    expect(await GateOffline.cachedFlats('association-b'), ['B-202']);
  });

  test('queued gate actions are scoped to their association', () async {
    SharedPreferences.setMockInitialValues({});
    await GateOffline.add('association-a', {'kind': 'walkin', 'flat': 'A-101'});
    expect(await GateOffline.queue('association-b'), isEmpty);
    expect((await GateOffline.queue('association-a')).single['association_id'], 'association-a');
  });

  test('legacy gate queue is preserved until assigned to an association', () async {
    SharedPreferences.setMockInitialValues({
      'gate_queue': ['{"kind":"walkin","flat":"A-101"}'],
      'gate_queue_association-a': ['{"kind":"verify","id":"visitor-a","association_id":"association-a"}'],
    });

    expect((await GateOffline.legacyQueue()).single['flat'], 'A-101');
    expect(await GateOffline.recoverLegacyQueue('association-a'), 1);

    final recovered = await GateOffline.queue('association-a');
    expect(recovered, hasLength(2));
    expect(recovered.last['association_id'], 'association-a');
    expect(recovered.last['at'], isA<String>());
    expect(await GateOffline.legacyQueue(), isEmpty);
    expect(await GateOffline.queue('association-b'), isEmpty);
  });

  test('legacy gate queue recovery is safe to repeat after a partial save', () async {
    const legacy = '{"kind":"walkin","flat":"A-101"}';
    final recoveryId = sha256.convert(utf8.encode('0:$legacy')).toString();
    final assignedLegacy = jsonEncode({
      'kind': 'walkin',
      'flat': 'A-101',
      '_legacy_recovery_association': 'association-a',
      '_legacy_recovery_id': recoveryId,
    });
    SharedPreferences.setMockInitialValues({
      'gate_queue': [assignedLegacy],
      'gate_queue_association-a': [
        jsonEncode({'kind': 'walkin', 'flat': 'A-101', '_legacy_recovery_id': recoveryId}),
      ],
    });

    expect(await GateOffline.recoverLegacyQueue('association-a'), 0);
    expect(await GateOffline.legacyQueue(), isEmpty);
    expect(await GateOffline.queue('association-a'), hasLength(1));
  });

  test('legacy recovery cannot reassign entries after an interrupted recovery', () async {
    const legacy = '{"kind":"walkin","flat":"A-101"}';
    final recoveryId = sha256.convert(utf8.encode('0:$legacy')).toString();
    SharedPreferences.setMockInitialValues({
      'gate_queue': [
        jsonEncode({
          'kind': 'walkin',
          'flat': 'A-101',
          '_legacy_recovery_association': 'association-a',
          '_legacy_recovery_id': recoveryId,
        }),
      ],
    });

    await expectLater(GateOffline.recoverLegacyQueue('association-b'), throwsA(isA<StateError>()));
    expect(await GateOffline.queue('association-b'), isEmpty);
    expect(await GateOffline.recoverLegacyQueue('association-a'), 1);
    expect((await GateOffline.queue('association-a')).single['association_id'], 'association-a');
  });

  test('legacy queue recovery and new gate actions retain both entries', () async {
    SharedPreferences.setMockInitialValues({
      'gate_queue': ['{"kind":"walkin","flat":"A-101"}'],
    });

    await Future.wait([
      GateOffline.recoverLegacyQueue('association-a'),
      GateOffline.add('association-a', {'kind': 'verify', 'id': 'visitor-a'}),
    ]);

    expect(await GateOffline.legacyQueue(), isEmpty);
    expect(await GateOffline.queue('association-a'), hasLength(2));
  });

  test('association context operations are serialized', () async {
    final order = <String>[];
    final flush = AssociationContext.run(() async {
      order.add('flush-start');
      await Future<void>.delayed(Duration.zero);
      order.add('flush-end');
    });
    final switchAssociation = AssociationContext.run(() async {
      order.add('switch');
    });

    await Future.wait([flush, switchAssociation]);
    expect(order, ['flush-start', 'flush-end', 'switch']);
  });

  test('walk-in request IDs are UUID v4 values', () {
    expect(
      GateRepo.newWalkInRequestId(),
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
  });

  test('cached gate visitors are scoped to their association', () async {
    SharedPreferences.setMockInitialValues({});
    final visitor = (
      id: 'visitor-a',
      guest: 'Guest A',
      phone: null,
      flat: 'A-101',
      status: 'expected',
      approval: 'approved',
      type: 'guest',
      vehicle: null,
      passCode: '123456',
      arrival: DateTime(2026, 11, 3),
      photoPath: null,
      guardName: null,
    );
    await GateOffline.cache('association-a', [visitor]);
    expect(await GateOffline.cached('association-b'), isEmpty);
    expect((await GateOffline.cached('association-a')).single.id, 'visitor-a');
  });

  test('daily-help cache and guard status are scoped to their association', () async {
    SharedPreferences.setMockInitialValues({});
    final help = (
      id: 'help-a',
      name: 'Helper A',
      kind: 'maid',
      phone: null,
      flatIds: <String>['flat-a'],
      flats: 'A-101',
      days: <int>[1],
      start: null,
      end: null,
      notify: false,
      code: 'A123',
      inside: false,
    );
    await GateOffline.cacheHelp('association-a', [help]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GateOffline.guardKey('association-a'), 'Guard A');

    expect(await GateOffline.cachedHelp('association-b'), isEmpty);
    expect((await GateOffline.cachedHelp('association-a')).single.id, 'help-a');
    expect(prefs.getString(GateOffline.guardKey('association-b')), isNull);
    expect(prefs.getString(GateOffline.guardKey('association-a')), 'Guard A');
  });

  test('vehicle formatter retains the supported 24-character registration', () {
    const registration = 'ABCDEFGHIJKLMN1234567890';
    final formatted = VehicleNumberFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: registration),
    );
    expect(formatted.text, registration);
  });

  test('vehicle formatter preserves and adjusts the selection', () {
    final formatted = VehicleNumberFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'KL 07AB1234',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    expect(formatted.text, 'KL07AB1234');
    expect(formatted.selection, const TextSelection.collapsed(offset: 4));

    final clipped = VehicleNumberFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'ABCDEFGHIJKLMN1234567890',
        selection: TextSelection.collapsed(offset: 24),
      ),
    );
    expect(clipped.selection, const TextSelection.collapsed(offset: 24));
  });

  testWidgets('call-a-flat picker fits a phone', (tester) async {
    await _phone(tester, const CallFlatPage(flats: ['A-101', 'B-202']));
    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'B-202'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
