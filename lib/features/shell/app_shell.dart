import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nav.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../security/device_lock.dart';
import '../../backend/notifications_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common.dart' show dateTimeFmt, EmptyState;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import 'privacy_notice_screen.dart';
import 'glossary.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    ref.watch(idleLogoutProvider);
    if (backendEnabled && ref.watch(privacyAcceptedProvider).value == false) return const PrivacyNoticeScreen();
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
        titleSpacing: wide ? 16 : 8,
        title: _AssociationSwitcher(
          session: session,
          child: Row(
            children: [
              Icon(Icons.apartment, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.user.association?.name ?? associationName,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: wide ? null : 15, height: 1.15),
                      maxLines: wide ? 1 : 2,
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
              if (session.user.associations.length > 1) const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          _RoleSwitcher(session: session),
          if (wide) const LanguageToggle(),
          if (wide) IconButton(
            tooltip: 'Help & terms',
            onPressed: () => showGlossary(context),
            icon: const Icon(Icons.help_outline),
          ),
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
          SizedBox(width: wide ? 8 : 2),
        ],
      ),
      body: Column(
        children: [
          if (birthdayWish.value == true)
            MaterialBanner(
              leading: const Icon(Icons.cake_outlined),
              content: Text(l.birthdayWish(session.user.name)),
              actions: [TextButton(onPressed: () => ref.invalidate(birthdayWishProvider), child: Text(l.dismiss))],
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
                          for (final i in barItems)
                            NavigationRailDestination(icon: Icon(i.icon), label: Text(i.label(l))),
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
    final wide = MediaQuery.sizeOf(context).width >= 840;
    Widget menu(BuildContext ctx) => Material(
      color: Theme.of(ctx).colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320, maxHeight: MediaQuery.sizeOf(ctx).height - 32),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(l.more, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final group in navGroups)
              if (more.any((i) => navGroupOf(i.path) == group)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    group,
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(color: Theme.of(ctx).colorScheme.primary),
                  ),
                ),
                for (final item in more.where((i) => navGroupOf(i.path) == group))
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label(l)),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.go(item.path);
                    },
                  ),
              ],
          ],
        ),
      ),
    );

    if (wide) {
      final leftInset = MediaQuery.sizeOf(context).width >= 1200 ? 264.0 : 96.0;
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: l.more,
        barrierColor: Colors.black26,
        pageBuilder: (ctx, _, _) => SafeArea(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: leftInset, top: 16, bottom: 16),
              child: menu(ctx),
            ),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.72, child: menu(ctx)),
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
                  subtitle: Text('${approval.title} · waiting for your approval'),
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
                    leading: Icon(
                      notice.readAt == null ? Icons.notifications_active_outlined : Icons.notifications_none,
                    ),
                    title: Text(notice.title),
                    subtitle: Text(
                      '${notice.body}${notice.body.isEmpty ? '' : ' · '}${dateTimeFmt.format(notice.createdAt)}',
                    ),
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
  const _AssociationSwitcher({required this.session, required this.child});
  final Session session;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final associations = session.user.associations;
    if (associations.length < 2) return child;
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
            child: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ],
      child: child,
    );
  }
}

class _RoleSwitcher extends ConsumerWidget {
  const _RoleSwitcher({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chip = Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.only(right: 2),
      avatar: const Icon(Icons.badge_outlined, size: 16),
      label: Text(session.activeRole.label, style: const TextStyle(fontSize: 12)),
    );
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
      child: Chip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.only(right: 2),
        avatar: const Icon(Icons.swap_horiz, size: 16),
        label: Text(session.activeRole.label, style: const TextStyle(fontSize: 12)),
      ),
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
          case 'audit':
            context.go('/audit');
          case 'datatools':
            context.go('/data-tools');
          case 'help':
            showGlossary(context);
          case 'setpin':
            context.go('/set-pin');
          case 'removepin':
            final uid = session.user.id;
            DeviceLock.clear().then((_) => DeviceLock.skip(uid));
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
        if (const {Role.admin, Role.president, Role.secretary}.contains(session.activeRole))
          const PopupMenuItem(
            value: 'datatools',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.import_export),
              title: Text('Data import & export'),
            ),
          ),
        if (const {Role.admin, Role.president, Role.secretary}.contains(session.activeRole))
          const PopupMenuItem(
            value: 'audit',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history),
              title: Text('Audit log & export'),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'help',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.help_outline), title: Text('Help & terms')),
        ),
        if (backendEnabled) ...[
          const PopupMenuItem(
            value: 'setpin',
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.pin_outlined), title: Text('Set or change PIN')),
          ),
          const PopupMenuItem(
            value: 'removepin',
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.lock_open_outlined), title: Text('Turn off PIN')),
          ),
          const PopupMenuDivider(),
        ],
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
