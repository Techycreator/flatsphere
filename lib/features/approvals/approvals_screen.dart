import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'approval_tile.dart';
import 'membership_request_screen.dart';

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionProvider)!;
    final all = ref.watch(approvalsProvider);
    final mine = all.where((a) => a.needsAction(s.activeRole, s.user.name)).toList();
    final canStart = s.user.canInitiateMembership(s.activeRole);
    final raised = all.where((a) => a.initiatorName.contains(s.user.name)).toList();
    final done = all.where((a) => a.overall != Decision.pending).toList();

    Widget list(List<ApprovalRequest> xs, String empty) => xs.isEmpty
        ? Card(child: EmptyState(empty))
        : Card(
            child: Column(
              children: [
                for (final a in xs) ...[ApprovalTile(request: a), if (a != xs.last) const Divider(height: 1)],
              ],
            ),
          );

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Awaiting me (${mine.length})'),
                Tab(text: 'Raised by me (${raised.length})'),
                Tab(text: 'Completed (${done.length})'),
                Tab(text: 'All (${all.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                PageBody(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l.pendingApprovals, style: Theme.of(context).textTheme.titleLarge)),
                        if (canStart)
                          PopupMenuButton<MembershipRequestType>(
                            onSelected: (t) => context.go('/approvals/new/${t.name}'),
                            itemBuilder: (_) => [
                              for (final t in MembershipRequestType.values)
                                PopupMenuItem(
                                  value: t,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(t.label),
                                    subtitle: Text(t.hint),
                                  ),
                                ),
                            ],
                            child: const Chip(avatar: Icon(Icons.add, size: 18), label: Text('New request')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('You can never approve a request you raised yourself (maker-checker).'),
                    const SizedBox(height: 12),
                    list(mine, 'Nothing waiting for you'),
                  ],
                ),
                PageBody(children: [list(raised, 'You have not raised any requests')]),
                PageBody(children: [list(done, 'No completed requests yet')]),
                PageBody(children: [list(all, 'No requests')]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
