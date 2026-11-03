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
  Session? build() =>
      Session(user: demoUsers.firstWhere((u) => u.roles.contains(Role.secretary)), activeRole: Role.secretary);
}

class _OwnerSession extends SessionNotifier {
  @override
  Session? build() => Session(user: demoUsers.firstWhere((u) => u.roles.contains(Role.owner)), activeRole: Role.owner);
}

const _sizes = {'phone': Size(360, 740), 'tablet': Size(768, 1024), 'desktop': Size(1280, 800)};

const _secretaryRoutes = [
  '/home',
  '/finance',
  '/complaints',
  '/approvals',
  '/directory',
  '/community',
  '/meetings',
  '/checklist',
];
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

class _RoleSession extends SessionNotifier {
  _RoleSession(this.role);
  final Role role;
  @override
  Session? build() => Session(user: demoUsers.firstWhere((u) => u.roles.contains(role)), activeRole: role);
}

const _allRoutes = [
  '/home',
  '/complaints',
  '/complaints/new',
  '/checklist',
  '/attendance',
  '/household-staff',
  '/archive',
  '/registers',
  '/association-documents',
  '/association-settings',
  '/workflows',
  '/audit',
  '/data-tools',
  '/amenities',
  '/community',
  '/approvals',
  '/finance',
  '/statements',
  '/dues',
  '/meetings',
  '/directory',
  '/family-accounts',
  '/notices',
  '/visitors',
  '/gate',
  '/vehicles',
];

void main() {
  for (final role in Role.values.where((r) => demoUsers.any((u) => u.roles.contains(r)))) {
    testWidgets('${role.name}: every screen fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [sessionProvider.overrideWith(() => _RoleSession(role))]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const FlatSphereApp()));
      await tester.pump(const Duration(milliseconds: 300));
      for (final route in _allRoutes) {
        container.read(routerProvider).go(route);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '$route as ${role.name} on phone');
      }
    });
  }

  _layoutTests('Secretary', _SecretarySession.new, _secretaryRoutes);
  _layoutTests('Owner', _OwnerSession.new, _ownerRoutes);
}
