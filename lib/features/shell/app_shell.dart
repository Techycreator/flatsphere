import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nav.dart';
import '../../backend/notifications_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common.dart' show dateTimeFmt, EmptyState;
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
    final birthdayWish = ref.watch(birthdayWishProvider);
    final l = AppLocalizations.of(context);
    final items = navFor(session.activeRole, membershipDesk: session.user.canInitiateMembership(session.activeRole));
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final barItems = items.length > 5 ? items.take(4).toList() : items;
    final moreItems = items.skip(barItems.length).toList();
    final primaryIndex = barItems.indexWhere((i) => location.startsWith(i.path));
    final selected = primaryIndex >= 0 ? primaryIndex : (moreItems.isNotEmpty ? barItems.length : 0);
    final pendingForMe = ref
        .watch(approvalsProvider)
        .where((a) => a.awaits(session.activeRole, session.user.name))
        .length;
    final unreadCount = ref.watch(appNotificationsProvider).value?.where((n) => n.readAt == null).length ?? 0;

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
                  Text(
                    session.user.association?.name ?? associationName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (wide)
                    Text(
                      session.user.association?.location ?? associationCity,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _AssociationSwitcher(session: session),
          _RoleSwitcher(session: session),
          if (wide) const LanguageToggle(),
          IconButton(
            tooltip: l.notices,
            onPressed: () => _showNotifications(context, ref),
            icon: Badge(
              isLabelVisible: pendingForMe + unreadCount > 0,
              label: Text('${pendingForMe + unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          _ProfileMenu(session: session, showLanguage: !wide),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (birthdayWish.value == true)
            MaterialBanner(
              leading: const Icon(Icons.cake_outlined),
              content: Text(l.birthdayWish(session.user.name)),
              actions: [
                TextButton(
                  onPressed: () => ref.invalidate(birthdayWishProvider),
                  child: Text(l.dismiss),
                ),
              ],
            ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        extended: width >= 1200,
                        selectedIndex: selected,
                        labelType: width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                        onDestinationSelected: (i) =>
                            i < barItems.length ? context.go(barItems[i].path) : _showMore(context, moreItems, l),
                        destinations: [
                          for (final i in barItems) NavigationRailDestination(icon: Icon(i.icon), label: Text(i.label(l))),
                          if (moreItems.isNotEmpty)
                            NavigationRailDestination(icon: const Icon(Icons.more_horiz), label: Text(l.more)),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: child),
                    ],
                  )
                : child,
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected < barItems.length ? selected : barItems.length,
              onDestinationSelected: (i) =>
                  i < barItems.length ? context.go(barItems[i].path) : _showMore(context, moreItems, l),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final i in barItems) NavigationDestination(icon: Icon(i.icon), label: i.label(l)),
                if (moreItems.isNotEmpty) NavigationDestination(icon: const Icon(Icons.more_horiz), label: l.more),
              ],
            ),
    );
  }

  void _showMore(BuildContext context, List<NavItem> more, AppLocalizations l) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.72,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(l.more, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final i in more)
                ListTile(
                  leading: Icon(i.icon),
                  title: Text(i.label(l)),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go(i.path);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotifications(BuildContext context, WidgetRef ref) {
    final s = ref.read(sessionProvider)!;
    final pending = ref.read(approvalsProvider).where((a) => a.awaits(s.activeRole, s.user.name)).toList();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final notifications = ref.watch(appNotificationsProvider);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (pending.isNotEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Approvals')),
              for (final approval in pending)
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(approval.title),
                  subtitle: Text('${approval.code} · waiting for your approval'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/approvals/${approval.id}');
                  },
                ),
              if (notifications.isLoading) const LinearProgressIndicator(),
              if (notifications.hasError)
                ListTile(leading: const Icon(Icons.error_outline), title: Text('${notifications.error}')),
              if (notifications.hasValue && notifications.value!.isNotEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Notifications')),
              if (notifications.hasValue)
                for (final notice in notifications.value!)
                  ListTile(
                    leading: Icon(notice.readAt == null ? Icons.notifications_active_outlined : Icons.notifications_none),
                    title: Text(notice.title),
                    subtitle: Text('${notice.body}${notice.body.isEmpty ? '' : ' · '}${dateTimeFmt.format(notice.createdAt)}'),
                    onTap: () async {
                      try {
                        await NotificationsRepo.markRead(notice.id);
                        ref.invalidate(appNotificationsProvider);
                      } catch (_) {}
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (notice.actionPath != null) context.go(notice.actionPath!);
                    },
                  ),
              if (pending.isEmpty && notifications.value?.isEmpty != false)
                const Padding(padding: EdgeInsets.all(24), child: EmptyState('No notifications')),
            ],
          );
        },
      ),
    );
  }
}

class _AssociationSwitcher extends ConsumerWidget {
  const _AssociationSwitcher({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final associations = session.user.associations;
    if (associations.length < 2) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Switch association',
      onSelected: (id) async {
        try {
          await ref.read(sessionProvider.notifier).switchAssociation(id);
          if (context.mounted) context.go('/home');
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not switch association.')));
          }
        }
      },
      itemBuilder: (_) => [
        for (final a in associations)
          CheckedPopupMenuItem(
            value: a.id,
            checked: a.id == session.user.associationId,
            child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.apartment_outlined)),
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
