import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/sla.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';
import '../approvals/approval_tile.dart';
import '../complaints/complaint_tile.dart';
import '../finance/charts.dart';
import '../finance/finance_screen.dart' show bankBalance;

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionProvider)!;
    final body = switch (s.activeRole) {
      Role.president => const _PresidentDash(),
      Role.secretary || Role.jointSecretary || Role.vicePresident => const _SecretaryDash(),
      Role.treasurer => const _TreasurerDash(),
      Role.owner => const _OwnerDash(),
      Role.resident => const _ResidentDash(),
      Role.caretaker => const _CaretakerDash(),
      Role.monitor || Role.ecMember => const _MonitorDash(),
      Role.auditor => const _AuditorDash(),
    };
    return PageBody(
      children: [
        Text(
          '${l.welcome}, ${s.user.name.split(' ').first}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          '${s.activeRole.label} view${s.user.flatNumber != null ? ' · Flat ${s.user.flatNumber}' : ''}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}

class _SlaSummary extends ConsumerWidget {
  const _SlaSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider);
    final open = ref.watch(complaintsProvider).where((c) => c.slaApplies).toList();
    int n(SlaColor c) => open.where((x) => slaFor(x, now).color == c).length;
    Widget seg(SlaColor c, String label) => Expanded(
      flex: n(c) == 0 ? 1 : n(c) * 3,
      child: Container(
        height: 44,
        color: AppColors.sla(c),
        alignment: Alignment.center,
        child: Text(
          '$label ${n(c)}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(children: [seg(SlaColor.green, 'Green'), seg(SlaColor.amber, 'Amber'), seg(SlaColor.red, 'Red')]),
        ),
        const SizedBox(height: 8),
        for (final c in open.where((x) => slaFor(x, now).color == SlaColor.red)) ComplaintTile(complaint: c),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go('/complaints'),
            child: Text(AppLocalizations.of(context).viewAll),
          ),
        ),
      ],
    );
  }
}

class _ApprovalsCard extends ConsumerWidget {
  const _ApprovalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider)!;
    final mine = ref.watch(approvalsProvider).where((a) => a.awaits(s.activeRole, s.user.name)).toList();
    return SectionCard(
      title: 'Awaiting your approval (${mine.length})',
      action: TextButton(onPressed: () => context.go('/approvals'), child: Text(AppLocalizations.of(context).viewAll)),
      child: mine.isEmpty
          ? const EmptyState('All caught up')
          : Column(children: [for (final a in mine.take(4)) ApprovalTile(request: a)]),
    );
  }
}

class _MeetingsCard extends ConsumerWidget {
  const _MeetingsCard({this.generalBodyOnly = false});
  final bool generalBodyOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final ms = ref
        .watch(meetingsProvider)
        .where((m) => m.at.isAfter(now) && (!generalBodyOnly || m.type == 'General Body'))
        .take(3)
        .toList();
    return SectionCard(
      title: 'Upcoming meetings',
      action: TextButton(onPressed: () => context.go('/meetings'), child: Text(AppLocalizations.of(context).viewAll)),
      child: ms.isEmpty
          ? const EmptyState('No upcoming meetings')
          : Column(
              children: [
                for (final m in ms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text(m.title),
                    subtitle: Text('${dateTimeFmt.format(m.at)} · ${m.mode.name}'),
                    trailing: Text('${m.accepted}/${m.invited}'),
                  ),
              ],
            ),
    );
  }
}

class _PresidentDash extends ConsumerWidget {
  const _PresidentDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider);
    final s = ref.watch(sessionProvider)!;
    final pending = ref.watch(approvalsProvider).where((a) => a.awaits(s.activeRole, s.user.name)).length;
    final red = ref.watch(complaintsProvider).where((c) => c.slaApplies && slaFor(c, now).color == SlaColor.red).length;
    final dues = ref.watch(duesProvider).lines;
    final total = dues.fold(0, (a, x) => a + x.amount);
    final paid = dues.fold(0, (a, x) => a + x.paid);
    final flagged = ref.watch(expensesProvider).where((e) => e.flagged).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Pending approvals',
              value: '$pending',
              icon: Icons.verified_outlined,
              onTap: () => context.go('/approvals'),
            ),
            StatCard(
              label: 'Red complaints',
              value: '$red',
              icon: Icons.warning_amber,
              color: AppColors.red,
              onTap: () => context.go('/complaints'),
            ),
            StatCard(
              label: 'Collection',
              value: '${(paid / total * 100).round()}%',
              icon: Icons.savings_outlined,
              color: AppColors.green,
              sub: '${inr.format(paid)} of ${inr.format(total)}',
            ),
            StatCard(
              label: 'Bank balance',
              value: inr.format(bankBalance),
              icon: Icons.account_balance,
              onTap: () => context.go('/finance'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TwoCol(
          left: const _ApprovalsCard(),
          right: const SectionCard(title: 'Complaints by SLA', child: _SlaSummary()),
        ),
        const SizedBox(height: 16),
        TwoCol(
          left: const _MeetingsCard(),
          right: SectionCard(
            title: 'Flagged transactions',
            child: flagged.isEmpty
                ? const EmptyState('Nothing flagged')
                : Column(
                    children: [
                      for (final e in flagged)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.flag, color: AppColors.amber),
                          title: Text('${e.category} · ${inr.format(e.amount)}'),
                          subtitle: Text(e.comment ?? e.description),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SecretaryDash extends ConsumerWidget {
  const _SecretaryDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider)!;
    final role = session.activeRole;
    final now = ref.watch(clockProvider);
    final all = ref.watch(complaintsProvider);
    final open = all.where((c) => c.slaApplies).toList();
    final review = all.where((c) => c.inReview).toList();
    int n(SlaColor c) => open.where((x) => slaFor(x, now).color == c).length;
    final cl = ref.watch(checklistProvider);
    final pending = ref.watch(approvalsProvider).where((a) => a.awaits(role, session.user.name)).length;
    final byCat = <String, (int, int)>{};
    for (final i in cl.items) {
      final v = byCat[i.category] ?? (0, 0);
      byCat[i.category] = (v.$1 + (i.done ? 1 : 0), v.$2 + 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Pending approvals',
              value: '$pending',
              icon: Icons.verified_outlined,
              onTap: () => context.go('/approvals'),
            ),
            StatCard(
              label: 'Open complaints',
              value: '${open.length}',
              icon: Icons.report_problem_outlined,
              color: AppColors.amber,
              sub: 'G ${n(SlaColor.green)} · A ${n(SlaColor.amber)} · R ${n(SlaColor.red)}',
              onTap: () => context.go('/complaints'),
            ),
            StatCard(
              label: "Today's checklist",
              value: '${(cl.progress * 100).round()}%',
              icon: Icons.checklist_rtl,
              color: AppColors.green,
              sub: '${cl.doneCount} of ${cl.items.length} done',
              onTap: () => context.go('/checklist'),
            ),
            StatCard(
              label: 'Reports to review',
              value: '${review.length}',
              icon: Icons.rate_review_outlined,
              color: Colors.purple,
              sub: 'From EC members and caretaker',
              onTap: () => context.go('/complaints'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (review.isNotEmpty && (role == Role.secretary || role == Role.jointSecretary)) ...[
          SectionCard(
            title: 'Common-area reports awaiting your review',
            child: Column(children: [for (final c in review) ComplaintTile(complaint: c)]),
          ),
          const SizedBox(height: 16),
        ],
        const TwoCol(
          left: SectionCard(title: 'Complaints by SLA', child: _SlaSummary()),
          right: _ApprovalsCard(),
        ),
        const SizedBox(height: 16),
        TwoCol(
          left: SectionCard(
            title: 'Checklist progress by category',
            child: Column(
              children: [
                for (final e in byCat.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 150, child: Text(e.key)),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: e.value.$1 / e.value.$2,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${e.value.$1}/${e.value.$2}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          right: const _MeetingsCard(),
        ),
      ],
    );
  }
}

class _TreasurerDash extends ConsumerWidget {
  const _TreasurerDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dues = ref.watch(duesProvider);
    final paid = dues.lines.fold(0, (a, x) => a + x.paid);
    final pending = dues.lines.fold(0, (a, x) => a + x.pending);
    final defaulters = <String, int>{};
    for (final x in dues.lines.where((x) => !x.isPaid)) {
      defaulters[x.flatNumber] = (defaulters[x.flatNumber] ?? 0) + x.pending;
    }
    final top = defaulters.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final toVerify = ref.watch(expensesProvider).where((e) => e.status == ExpenseStatus.awaitingTreasurer).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(label: 'Collected', value: inr.format(paid), icon: Icons.south_west, color: AppColors.green),
            StatCard(
              label: 'Pending dues',
              value: inr.format(pending),
              icon: Icons.pending_actions,
              color: AppColors.amber,
              sub: '${defaulters.length} flats',
              onTap: () => context.go('/finance'),
            ),
            StatCard(
              label: 'Expenses to verify',
              value: '${toVerify.length}',
              icon: Icons.receipt_long,
              color: AppColors.red,
              onTap: () => context.go('/finance'),
            ),
            StatCard(label: 'Bank balance', value: inr.format(bankBalance), icon: Icons.account_balance),
          ],
        ),
        const SizedBox(height: 16),
        TwoCol(
          left: const SectionCard(title: 'Income vs expenditure', child: IncomeExpenseChart()),
          right: SectionCard(
            title: 'Expenses awaiting your verification',
            child: Column(
              children: [
                for (final e in toVerify)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long, color: e.documents == 0 ? AppColors.red : null),
                    title: Text('${e.category} · ${inr.format(e.amount)}'),
                    subtitle: Text(
                      e.documents == 0
                          ? 'No documents attached – send back'
                          : '${e.vendor} · ${e.documents} document(s)',
                    ),
                    onTap: () => context.go('/finance'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Top pending dues',
          child: Column(
            children: [
              for (final e in top.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Flat ${e.key}'),
                  trailing: Text(
                    inr.format(e.value),
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnerDash extends ConsumerWidget {
  const _OwnerDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider)!;
    final pending = ref.watch(duesProvider).pendingFor(s.user.flatNumber ?? '');
    final mine = visibleComplaints(ref);
    final notices = ref.watch(noticesProvider);
    final approvals = ref.watch(approvalsProvider);
    final consents = approvals.where((a) => a.awaits(Role.owner, s.user.name)).toList();
    final myRequests = approvals.where((a) => a.initiatorName == s.user.name).toList();
    final rented = demoFlats
        .where((f) => f.ownerName == s.user.name && f.occupancy != Occupancy.ownerOccupied)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in rented) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: Text('Your ${f.occupancy == Occupancy.rented ? 'rented' : 'vacant'} flat ${f.number}'),
              subtitle: Text(f.residentName != null ? 'Current tenant: ${f.residentName}' : 'No tenant'),
              trailing: FilledButton.tonal(
                onPressed: () => context.go('/approvals/new/resident'),
                child: const Text('Change tenant'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (myRequests.isNotEmpty) ...[
          SectionCard(
            title: 'My requests',
            child: Column(children: [for (final a in myRequests) ApprovalTile(request: a)]),
          ),
          const SizedBox(height: 16),
        ],
        if (consents.isNotEmpty) ...[
          SectionCard(
            title: 'Needs your consent as flat owner',
            child: Column(children: [for (final a in consents) ApprovalTile(request: a)]),
          ),
          const SizedBox(height: 16),
        ],
        StatGrid(
          children: [
            StatCard(
              label: 'My pending dues',
              value: inr.format(pending),
              icon: Icons.payments_outlined,
              color: pending > 0 ? AppColors.red : AppColors.green,
              sub: pending > 0 ? 'Tap to pay now' : 'All paid',
              onTap: () => context.go('/dues'),
            ),
            StatCard(
              label: 'My open complaints',
              value: '${mine.where((c) => c.status.isOpen).length}',
              icon: Icons.report_problem_outlined,
              onTap: () => context.go('/complaints'),
            ),
            const StatCard(
              label: 'Next General Body',
              value: 'AGM 2026',
              icon: Icons.groups_outlined,
              sub: '15th next month · Hybrid',
            ),
            StatCard(
              label: 'Notices',
              value: '${notices.length}',
              icon: Icons.campaign_outlined,
              onTap: () => context.go('/notices'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TwoCol(
          left: const SectionCard(title: 'September 2026 statement (published)', child: ExpensePie()),
          right: SectionCard(
            title: 'My complaints',
            action: TextButton.icon(
              onPressed: () => context.go('/complaints/new'),
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).raiseComplaint),
            ),
            child: mine.isEmpty
                ? const EmptyState('No complaints raised')
                : Column(children: [for (final c in mine.take(4)) ComplaintTile(complaint: c)]),
          ),
        ),
        const SizedBox(height: 16),
        const _MeetingsCard(generalBodyOnly: true),
      ],
    );
  }
}

class _ResidentDash extends ConsumerWidget {
  const _ResidentDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = visibleComplaints(ref);
    final notices = ref.watch(noticesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoCol(
          left: SectionCard(
            title: 'My complaints',
            action: TextButton.icon(
              onPressed: () => context.go('/complaints/new'),
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).raiseComplaint),
            ),
            child: mine.isEmpty
                ? const EmptyState('No complaints raised')
                : Column(children: [for (final c in mine) ComplaintTile(complaint: c)]),
          ),
          right: SectionCard(
            title: 'Latest notices',
            child: Column(
              children: [
                for (final n in notices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(n.title),
                    subtitle: Text(dateFmt.format(n.date)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Financial statements are visible to owners only.', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _CaretakerDash extends ConsumerWidget {
  const _CaretakerDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cl = ref.watch(checklistProvider);
    final now = ref.watch(clockProvider);
    final assigned = ref.watch(complaintsProvider).where((c) => c.status.isOpen).toList()
      ..sort((a, b) => slaFor(b, now).color.index.compareTo(slaFor(a, now).color.index));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: InkWell(
            onTap: () => context.go('/checklist'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.checklist, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('${cl.doneCount} of ${cl.items.length} done · submit before end of day'),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: cl.progress, minHeight: 14, borderRadius: BorderRadius.circular(8)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.go('/checklist'),
                    icon: const Icon(Icons.checklist_rtl),
                    label: const Padding(padding: EdgeInsets.all(10), child: Text('Open checklist')),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Open complaints (most urgent first)',
          child: Column(children: [for (final c in assigned) ComplaintTile(complaint: c)]),
        ),
      ],
    );
  }
}

class _MonitorDash extends ConsumerWidget {
  const _MonitorDash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider)!;
    final cats = s.user.monitorCategories;
    final cl = ref.watch(checklistProvider);
    final myItems = cl.items.where((i) => cats.contains(i.category)).toList();
    final myComplaints = ref
        .watch(complaintsProvider)
        .where((c) => c.status.isOpen && (cats.contains(c.category) || c.category == 'Lift'))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cats.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Your monitor categories:', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final c in cats) Chip(label: Text(c)),
                  const Text('· until 31 Dec 2026 (approved by President)'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        TwoCol(
          left: SectionCard(
            title: 'Checklist items in your categories',
            action: TextButton(
              onPressed: () => context.go('/checklist'),
              child: Text(cl.submitted ? 'Review' : 'View'),
            ),
            child: Column(
              children: [
                for (final i in myItems)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      i.done ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: i.done ? AppColors.green : Colors.grey,
                    ),
                    title: Text(i.title),
                    subtitle: Text('${i.category} · ${i.timeWindow}'),
                  ),
              ],
            ),
          ),
          right: SectionCard(
            title: 'Open complaints in your areas',
            child: myComplaints.isEmpty
                ? const EmptyState('None')
                : Column(children: [for (final c in myComplaints) ComplaintTile(complaint: c)]),
          ),
        ),
        const SizedBox(height: 16),
        const _MeetingsCard(),
      ],
    );
  }
}

class _AuditorDash extends StatelessWidget {
  const _AuditorDash();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StatGrid(
          children: [
            StatCard(label: 'FY 2025-26 income', value: '₹38,42,600', icon: Icons.south_west, color: AppColors.green),
            StatCard(
              label: 'FY 2025-26 expenditure',
              value: '₹31,18,450',
              icon: Icons.north_east,
              color: AppColors.red,
            ),
            StatCard(label: 'Vouchers', value: '1,284', icon: Icons.receipt_long),
            StatCard(
              label: 'Supporting documents',
              value: '1,251',
              icon: Icons.folder_open,
              sub: '33 vouchers missing documents',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_clock),
            title: const Text('Read-only access · expires 31 Dec 2026'),
            subtitle: const Text(
              'Receipts & payments, income & expenditure, balance sheet, ledgers. Export to Excel / PDF / Tally XML.',
            ),
            trailing: FilledButton(onPressed: () => context.go('/finance'), child: const Text('Open finance')),
          ),
        ),
      ],
    );
  }
}
