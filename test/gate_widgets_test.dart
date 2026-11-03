import 'package:flatsphere/backend/gate_offline.dart';
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

  testWidgets('call-a-flat picker fits a phone', (tester) async {
    await _phone(tester, const CallFlatPage(flats: ['A-101', 'B-202']));
    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'B-202'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
