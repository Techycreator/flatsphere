import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nav.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final items = navFor(session.activeRole, membershipDesk: session.user.canInitiateMembership(session.activeRole));
    final idx = items.indexWhere((i) => location.startsWith(i.path));
    final selected = idx < 0 ? 0 : idx;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final pendingForMe = ref
        .watch(approvalsProvider)
        .where((a) => a.awaits(session.activeRole, session.user.name))
        .length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Icon(Icons.apartment, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FlatSphere', style: TextStyle(fontWeight: FontWeight.w700)),
                  if (wide) Text('$associationName · $associationCity', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _RoleSwitcher(session: session),
          if (wide) const LanguageToggle(),
          IconButton(
            tooltip: l.notices,
            onPressed: () => _showNotifications(context, ref),
            icon: Badge(
              isLabelVisible: pendingForMe > 0,
              label: Text('$pendingForMe'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          _ProfileMenu(session: session, showLanguage: !wide),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: width >= 1200,
                  selectedIndex: selected,
                  labelType: width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  onDestinationSelected: (i) => context.go(items[i].path),
                  destinations: [
                    for (final i in items) NavigationRailDestination(icon: Icon(i.icon), label: Text(i.label(l))),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(items[i].path),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [for (final i in items) NavigationDestination(icon: Icon(i.icon), label: i.label(l))],
            ),
    );
  }

  void _showNotifications(BuildContext context, WidgetRef ref) {
    final s = ref.read(sessionProvider)!;
    final pending = ref.read(approvalsProvider).where((a) => a.awaits(s.activeRole, s.user.name)).toList();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final a in pending)
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(a.title),
              subtitle: Text('${a.code} · waiting for your approval'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/approvals/${a.id}');
              },
            ),
          const ListTile(
            leading: Icon(Icons.warning_amber, color: Colors.red),
            title: Text('Complaint CMP-2026-0124 turned RED'),
            subtitle: Text('Garbage not cleared near Block A gate · Day 7'),
          ),
          const ListTile(
            leading: Icon(Icons.campaign_outlined),
            title: Text('Water supply interruption – Saturday'),
            subtitle: Text('Notice from Secretary'),
          ),
        ],
      ),
    );
  }
}

class _RoleSwitcher extends ConsumerWidget {
  const _RoleSwitcher({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chip = Chip(avatar: const Icon(Icons.badge_outlined, size: 18), label: Text(session.activeRole.label));
    if (session.user.roles.length < 2) return chip;
    return PopupMenuButton<Role>(
      tooltip: AppLocalizations.of(context).switchRole,
      onSelected: (r) {
        ref.read(sessionProvider.notifier).switchRole(r);
        context.go('/home');
      },
      itemBuilder: (_) => [
        for (final r in session.user.roles)
          CheckedPopupMenuItem(value: r, checked: r == session.activeRole, child: Text(r.label)),
      ],
      child: Chip(avatar: const Icon(Icons.swap_horiz, size: 18), label: Text(session.activeRole.label)),
    );
  }
}

class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu({required this.session, required this.showLanguage});
  final Session session;
  final bool showLanguage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final initials = session.user.name.split(' ').take(2).map((p) => p[0]).join();
    return PopupMenuButton<String>(
      tooltip: session.user.name,
      onSelected: (v) {
        switch (v) {
          case 'en' || 'ml':
            ref.read(localeProvider.notifier).set(Locale(v));
          case 'logout':
            ref.read(sessionProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(session.user.name),
            subtitle: Text([session.user.mobile, ?session.user.flatNumber].join(' · ')),
          ),
        ),
        if (showLanguage) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'en', child: Text('English')),
          const PopupMenuItem(value: 'ml', child: Text('മലയാളം')),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.logout), title: Text(l.logout)),
        ),
      ],
      child: CircleAvatar(radius: 18, child: Text(initials, style: const TextStyle(fontSize: 13))),
    );
  }
}

class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 'en', label: Text('EN')),
          ButtonSegment(value: 'ml', label: Text('മല')),
        ],
        selected: {locale.languageCode},
        onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(Locale(s.first)),
      ),
    );
  }
}
