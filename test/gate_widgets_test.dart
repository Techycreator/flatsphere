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

  testWidgets('walk-in delivery company is one tap', (tester) async {
    await _phone(tester, const WalkInPage(flats: ['A-101']));
    await tester.tap(find.text('Delivery'));
    await tester.pump();
    await tester.ensureVisible(find.text('Flipkart'));
    await tester.tap(find.text('Flipkart'));
    await tester.pump();
    final name = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == 'Flipkart');
    await tester.scrollUntilVisible(name, 200, scrollable: find.byType(Scrollable).first);
    final controller = tester.widget<TextField>(name).controller!;
    await tester.scrollUntilVisible(find.text('Cab'), -200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Cab'));
    await tester.pump();
    expect(find.text('Rapido'), findsOneWidget);
    expect(find.text('Flipkart'), findsNothing);
    expect(controller.text, isEmpty);
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

  test('checkout waits behind an unsynced walk-in', () async {
    SharedPreferences.setMockInitialValues({});
    await GateOffline.add('association-a', {'kind': 'walkin', 'request_id': 'visitor-a'});
    final action = {
      'kind': 'verify',
      'id': 'visitor-a',
      'action': 'check_out',
      'label': 'Guest → Staff: Ravi',
    };

    expect(await GateOffline.verifyAfterPendingWalkIn('association-a', action), isTrue);
    expect(await GateOffline.verifyAfterPendingWalkIn('association-a', action), isTrue);
    final queue = await GateOffline.queue('association-a');
    expect(queue.map((entry) => entry['kind']), ['walkin', 'verify']);
    expect(queue.last['action'], 'check_out');
    expect(queue.last['association_id'], 'association-a');
  });

  test('checkout is sent normally when its walk-in is no longer queued', () async {
    SharedPreferences.setMockInitialValues({});
    expect(
      await GateOffline.verifyAfterPendingWalkIn('association-a', {
        'kind': 'verify',
        'id': 'visitor-a',
        'action': 'check_out',
      }),
      isFalse,
    );
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

  test('explicit legacy recovery preserves entries assigned to other associations', () async {
    SharedPreferences.setMockInitialValues({
      'gate_queue': [
        '{"kind":"walkin","flat":"A-101","_legacy_recovery_association":"association-a"}',
        '{"kind":"walkin","flat":"B-202","_legacy_recovery_association":"association-b"}',
        '{"kind":"verify","id":"unassigned"}',
      ],
    });

    expect(await GateOffline.recoverLegacyQueue('association-a'), 2);
    expect((await GateOffline.queue('association-a')).map((entry) => entry['flat'] ?? entry['id']), [
      'A-101',
      'unassigned',
    ]);
    expect((await GateOffline.legacyQueue()).single['flat'], 'B-202');
  });

  test('assigned legacy entries recover before their association queue is flushed', () async {
    const legacy = '{"kind":"walkin","flat":"A-101","_legacy_recovery_association":"association-a"}';
    const otherAssociation = '{"kind":"walkin","flat":"B-202","_legacy_recovery_association":"association-b"}';
    SharedPreferences.setMockInitialValues({
      'gate_queue': [legacy, otherAssociation, '{"kind":"verify","id":"unassigned"}'],
    });

    expect(await GateOffline.recoverAssignedLegacyQueue('association-a'), 1);
    expect((await GateOffline.queue('association-a')).single['flat'], 'A-101');
    expect((await GateOffline.legacyQueue()).map((entry) => entry['flat'] ?? entry['id']), ['B-202', 'unassigned']);
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
    expect((await GateOffline.legacyQueue()).single['_legacy_recovery_association'], 'association-a');
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
      note: 'Interview',
      photoPath: null,
      guardName: null,
    );
    await GateOffline.cache('association-a', [visitor]);
    expect(await GateOffline.cached('association-b'), isEmpty);
    expect((await GateOffline.cached('association-a')).single.id, 'visitor-a');
    expect((await GateOffline.cached('association-a')).single.note, 'Interview');
  });

  test('cached staff contacts retain recipient IDs and stay association-scoped', () async {
    SharedPreferences.setMockInitialValues({});
    const staff = [(id: 'staff-a', name: 'Ravi', role: 'caretaker', mobile: '9999999999')];
    await GateOffline.cacheStaff('association-a', staff);

    expect(await GateOffline.cachedStaff('association-b'), isEmpty);
    expect((await GateOffline.cachedStaff('association-a')).single.id, 'staff-a');
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
      const TextEditingValue(text: 'KL 07AB1234', selection: TextSelection.collapsed(offset: 5)),
    );

    expect(formatted.text, 'KL07AB1234');
    expect(formatted.selection, const TextSelection.collapsed(offset: 4));

    final clipped = VehicleNumberFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'ABCDEFGHIJKLMN1234567890', selection: TextSelection.collapsed(offset: 24)),
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

  Future<WalkInData? Function()> openWalkIn(WidgetTester tester, Widget page) async {
    WalkInData? result;
    tester.view.physicalSize = const Size(360, 740) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await Navigator.push<WalkInData>(context, MaterialPageRoute(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('walk-in delivery can be left at the lobby when the flat does not answer', (tester) async {
    final result = await openWalkIn(tester, const WalkInPage(flats: ['A-101']));
    await tester.tap(find.text('Delivery'));
    await tester.pump();
    await tester.ensureVisible(find.text('Amazon'));
    await tester.tap(find.text('Amazon'));
    await tester.pump();
    final flatField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Flat number');
    await tester.scrollUntilVisible(flatField, 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(flatField, 'a101');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'A-101'));
    await tester.tap(find.widgetWithText(FilledButton, 'A-101'));
    await tester.pump();
    final lobby = find.text('Flat not reachable · Leave at lobby');
    await tester.scrollUntilVisible(lobby, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(lobby);
    await tester.pumpAndSettle();
    await tester.tap(lobby);
    await tester.pumpAndSettle();
    expect(result()?.mode, 'lobby');
    expect(result()?.flat, 'A-101');
    expect(result()?.name, 'Amazon');
    expect(tester.takeException(), isNull);
  });

  testWidgets('walk-in for staff needs a staff member and an Other purpose', (tester) async {
    final result = await openWalkIn(
      tester,
      const WalkInPage(
        flats: ['A-101'],
        staff: [(id: 'staff-a', name: 'Ravi', role: 'caretaker', mobile: '9999999999')],
      ),
    );
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Purpose of visit *'),
      'Interview',
    );
    await tester.ensureVisible(find.text('Caretaker / staff'));
    await tester.tap(find.text('Caretaker / staff'));
    await tester.pump();
    await tester.ensureVisible(find.text('Ravi'));
    await tester.tap(find.text('Ravi'));
    await tester.pump();
    final name = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Name / company *');
    await tester.scrollUntilVisible(name, 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(name, 'Anil');
    await tester.tap(find.text('Confirmed · Let in'));
    await tester.pumpAndSettle();
    expect(result()?.mode, 'staff');
    expect(result()?.meet, 'Ravi');
    expect(result()?.staffId, 'staff-a');
    expect(result()?.note, 'Interview');
    expect(result()?.type, 'other');
    expect(tester.takeException(), isNull);
  });

  testWidgets('walk-in restores the selected flat after switching to staff and back', (tester) async {
    await _phone(tester, const WalkInPage(flats: ['A-101']));
    final flatField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Flat number');
    await tester.enterText(flatField, 'a101');
    await tester.pump();
    final flatButton = find.widgetWithText(FilledButton, 'A-101');
    await tester.ensureVisible(flatButton);
    await tester.tap(flatButton);
    await tester.pump();

    final staffToggle = find.text('Caretaker / staff');
    await tester.scrollUntilVisible(staffToggle, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(staffToggle);
    await tester.pump();
    final flatToggle = find.text('A flat');
    await tester.scrollUntilVisible(flatToggle, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(flatToggle);
    await tester.pump();

    expect(find.text('Flat A-101'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
