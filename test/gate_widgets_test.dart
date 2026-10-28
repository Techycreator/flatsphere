import 'package:flatsphere/features/visitors/gate_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('call-a-flat picker fits a phone', (tester) async {
    await _phone(tester, const CallFlatPage(flats: ['A-101', 'B-202']));
    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'B-202'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
