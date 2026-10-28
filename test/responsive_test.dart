import 'package:flatsphere/app/router.dart';
import 'package:flatsphere/main.dart';
import 'package:flatsphere/models/models.dart';
import 'package:flatsphere/state/app_state.dart';
import 'package:flatsphere/state/demo_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SecretarySession extends SessionNotifier {
  @override
  Session? build() => Session(user: demoUsers.firstWhere((u) => u.roles.contains(Role.secretary)), activeRole: Role.secretary);
}

class _OwnerSession extends SessionNotifier {
  @override
  Session? build() => Session(user: demoUsers.firstWhere((u) => u.roles.contains(Role.owner)), activeRole: Role.owner);
}

const _sizes = {'phone': Size(360, 740), 'tablet': Size(768, 1024), 'desktop': Size(1280, 800)};

const _secretaryRoutes = ['/home', '/finance', '/complaints', '/approvals', '/directory', '/community', '/meetings', '/checklist'];
const _ownerRoutes = ['/home', '/dues', '/family-accounts', '/complaints', '/community', '/notices'];

void _layoutTests(String who, SessionNotifier Function() session, List<String> routes) {
  for (final size in _sizes.entries) {
    testWidgets('$who screens lay out without errors on ${size.key}', (tester) async {
      tester.view.physicalSize = size.value * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [sessionProvider.overrideWith(session)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const FlatSphereApp()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'first screen on ${size.key}');

      for (final route in routes) {
        container.read(routerProvider).go(route);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '$route on ${size.key}');
      }
    });
  }
}

void main() {
  _layoutTests('Secretary', _SecretarySession.new, _secretaryRoutes);
  _layoutTests('Owner', _OwnerSession.new, _ownerRoutes);
}
