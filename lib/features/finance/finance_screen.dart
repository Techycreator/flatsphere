import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';
import 'analysis_tab.dart';
import 'charts.dart';

const bankBalance = 485320;

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final full = role == Role.treasurer || role == Role.president || role == Role.secretary || role == Role.auditor;
    final tabs = <(String, Widget)>[
      ('Overview', const _Overview()),
      ('Analysis', const AnalysisTab()),
      if (full) ('Dues & follow-ups', const _DuesTab()),
      if (full) ('Expenses', const _ExpensesTab()),
      ('Fund requests', const _FundRequestsTab()),
      ('Statements', const _StatementsTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$1)]),
        ),
        if (role == Role.auditor)
          MaterialBanner(
            content: const Text('Read-only auditor access · FY 2025-26 · expires 31 Dec 2026'),
            leading: const Icon(Icons.lock_clock),
            actions: [TextButton(onPressed: () => toast(context, 'Auditor pack (Excel + PDF + documents zip) prepared'), child: const Text('Download auditor pack'))],
          ),
        Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
      ]),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dues = ref.watch(duesProvider);
    final collected = dues.lines.fold(0, (s, l) => s + l.paid);
    final pending = dues.lines.fold(0, (s, l) => s + l.pending);
    final defaulters = {for (final l in dues.lines) if (!l.isPaid) l.flatNumber}.length;
    final role = ref.watch(sessionProvider)!.activeRole;
    return PageBody(children: [
      StatGrid(children: [
        StatCard(label: 'Bank balance (SBI ••••4521)', value: inr.format(bankBalance), icon: Icons.account_balance),
        StatCard(label: 'Collected this period', value: inr.format(collected), icon: Icons.south_west, color: AppColors.green),
        StatCard(label: 'Pending dues', value: inr.format(pending), icon: Icons.pending_actions, color: AppColors.amber, sub: '$defaulters flats'),
        const StatCard(label: 'Spent this month', value: '₹1,49,000', icon: Icons.north_east, color: AppColors.red, sub: '62% of monthly budget'),
      ]),
      const SizedBox(height: 16),
      if (role == Role.ecMember || role == Role.monitor)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('EC view: summary level. Detailed ledgers are visible to office bearers as configured by the Secretary.'),
        ),
      const TwoCol(
        left: SectionCard(title: 'Income vs expenditure (last 6 months)', child: IncomeExpenseChart()),
        right: SectionCard(title: 'September expenditure by category', child: ExpensePie()),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Income by category (FY to date)',
        child: Column(children: [
          for (final (k, v) in const [
            ('Monthly maintenance', 1584000),
            ('Corpus fund', 600000),
            ('Advertisement (lift panels – AdVantage Media)', 36000),
            ('Sponsorship – Onam (Lulu Hypermarket, Muthoot Finance)', 75000),
            ('Party hall rental', 28500),
            ('Late fees', 4200),
            ('Bank interest', 11840),
          ])
            ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(k), trailing: Text(inr.format(v), style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
    ]);
  }
}

class _DuesTab extends ConsumerWidget {
  const _DuesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(duesProvider);
    final n = ref.read(duesProvider.notifier);
    final role = ref.watch(sessionProvider)!.activeRole;
    final canRemind = role == Role.treasurer || role == Role.secretary;
    final pendingFlats = {for (final l in st.lines) if (!l.isPaid) l.flatNumber};

    return PageBody(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${pendingFlats.length} flats have pending dues', style: Theme.of(context).textTheme.titleMedium),
                Text('Limit: 1 reminder per flat per day, 1 bulk reminder per day', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (canRemind)
              FilledButton.icon(
                onPressed: n.canBulk
                    ? () {
                        final c = n.remindAll();
                        toast(context, 'Reminder sent to $c flats (push + email; WhatsApp/SMS after 2nd reminder)');
                      }
                    : null,
                icon: const Icon(Icons.campaign),
                label: Text(n.canBulk ? 'Remind all pending' : 'Bulk sent today'),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Flat')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Owner')),
              DataColumn(label: Text('Maintenance')),
              DataColumn(label: Text('Corpus')),
              DataColumn(label: Text('Pending'), numeric: true),
              DataColumn(label: Text('Follow-up')),
            ],
            rows: [
              for (final f in demoFlats)
                () {
                  final lines = st.lines.where((l) => l.flatNumber == f.number).toList();
                  final maint = lines.where((l) => l.head.startsWith('Maintenance'));
                  final corpus = lines.where((l) => l.head.startsWith('Corpus'));
                  final pending = st.pendingFor(f.number);
                  Widget status(Iterable<DueLine> xs) => xs.every((l) => l.isPaid)
                      ? const Pill('Paid', color: AppColors.green)
                      : Pill('Due ${xs.where((l) => !l.isPaid).length}', color: AppColors.red);
                  return DataRow(cells: [
                    DataCell(Text(f.number, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(f.type)),
                    DataCell(Text(f.ownerName)),
                    DataCell(status(maint)),
                    DataCell(status(corpus)),
                    DataCell(Text(pending == 0 ? '–' : inr.format(pending))),
                    DataCell(pending == 0 || !canRemind
                        ? const SizedBox.shrink()
                        : n.canRemind(f.number)
                            ? TextButton.icon(
                                onPressed: () {
                                  n.remind(f.number);
                                  toast(context, 'Reminder sent to ${f.ownerName}');
                                },
                                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                                label: const Text('Remind'),
                              )
                            : const Text('Sent today', style: TextStyle(color: Colors.black45))),
                  ]);
                }(),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(expensesProvider);
    final n = ref.read(expensesProvider.notifier);
    final role = ref.watch(sessionProvider)!.activeRole;

    Future<void> sendBack(Expense e) async {
      final c = await promptText(context, title: 'Send back ${e.id}', hint: 'What is missing? (e.g. GST invoice)');
      if (c != null) n.update(e.id, (x) => x.copyWith(status: ExpenseStatus.sentBack, comment: c));
    }

    return PageBody(children: [
      Row(children: [
        const Expanded(child: Text('Entered by Secretary/Treasurer → Treasurer verifies documents → President approves')),
        if (role == Role.treasurer || role == Role.secretary)
          FilledButton.tonalIcon(onPressed: () => toast(context, 'Opens expense entry form with bill photo + OCR auto-fill'), icon: const Icon(Icons.add), label: const Text('Add expense')),
      ]),
      const SizedBox(height: 12),
      for (final e in list) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${e.category} · ${e.vendor}', style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(inr.format(e.amount), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text('${e.id} · ${dateFmt.format(e.date)} · ${e.description} · by ${e.enteredBy}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Pill(e.status.label, color: switch (e.status) {
                  ExpenseStatus.approved => AppColors.green,
                  ExpenseStatus.sentBack => AppColors.red,
                  _ => AppColors.amber,
                }),
                e.documents == 0
                    ? const Pill('No documents', color: AppColors.red, icon: Icons.attach_file)
                    : Pill('${e.documents} document(s)', color: Colors.blueGrey, icon: Icons.attach_file),
                if (e.flagged) const Pill('Flagged by President', color: AppColors.amber, icon: Icons.flag),
                if (e.comment != null) Text('“${e.comment}”', style: const TextStyle(fontStyle: FontStyle.italic)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (role == Role.treasurer && e.status == ExpenseStatus.awaitingTreasurer) ...[
                  FilledButton(
                    onPressed: e.documents == 0 ? null : () => n.update(e.id, (x) => x.copyWith(status: ExpenseStatus.awaitingPresident)),
                    child: const Text('Documents OK → President'),
                  ),
                  OutlinedButton(onPressed: () => sendBack(e), child: const Text('Send back')),
                ],
                if (role == Role.president && e.status == ExpenseStatus.awaitingPresident) ...[
                  FilledButton(onPressed: () => n.update(e.id, (x) => x.copyWith(status: ExpenseStatus.approved)), child: const Text('Approve')),
                  OutlinedButton(onPressed: () => sendBack(e), child: const Text('Send back')),
                ],
                if (role == Role.president)
                  TextButton.icon(
                    onPressed: () => n.update(e.id, (x) => x.copyWith(flagged: !x.flagged)),
                    icon: Icon(e.flagged ? Icons.flag : Icons.outlined_flag),
                    label: Text(e.flagged ? 'Unflag' : 'Flag for discussion'),
                  ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

class _FundRequestsTab extends ConsumerWidget {
  const _FundRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    return PageBody(children: [
      Row(children: [
        const Expanded(child: Text('New fund requests need President approval and an EC MOM before reaching owners.')),
        if (role == Role.secretary)
          FilledButton.tonalIcon(onPressed: () => toast(context, 'Opens fund request form (name, recurring/adhoc, amount optional)'), icon: const Icon(Icons.add), label: const Text('New fund request')),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final f in demoFundRequests)
            ListTile(
              leading: Icon(f.kind.startsWith('Recurring') ? Icons.repeat : Icons.celebration_outlined),
              title: Text(f.name),
              subtitle: Text('${f.kind} · ${f.basis}${f.dueDay != null ? ' · due ${f.dueDay}' : ''}'),
              trailing: Pill(f.status, color: f.status == 'Active' ? AppColors.green : (f.status == 'Draft' ? Colors.blueGrey : AppColors.amber)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Maintenance rates (by flat type)',
        child: Column(children: [
          for (final e in maintenanceRates.entries)
            ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(e.key), trailing: Text('${inr.format(e.value)} / month')),
          const Text('Basis can be switched to per sq ft (W17: Secretary + Treasurer → President, with EC MOM). Late fee: ₹100 after 15 days, cap ₹500.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
    ]);
  }
}

class _StatementsTab extends ConsumerWidget {
  const _StatementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    Widget sign(String who, bool ok) => Pill(who, color: ok ? AppColors.green : Colors.blueGrey, icon: ok ? Icons.check : Icons.schedule);
    return PageBody(children: [
      const Text('Statements are published to owners only after Treasurer, Secretary and President all approve. Published months are locked.'),
      const SizedBox(height: 12),
      for (final (month, t, s, p) in const [
        ('October 2026', true, false, false),
        ('September 2026', true, true, true),
        ('August 2026', true, true, true),
      ])
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(p ? Icons.lock : Icons.edit_document),
            title: Text('Income & expenditure – $month'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [sign('Treasurer', t), sign('Secretary', s), sign('President', p)]),
            ),
            trailing: p
                ? const Pill('Published', color: AppColors.green)
                : (role == Role.secretary || role == Role.president)
                    ? FilledButton(onPressed: () => toast(context, 'Approved. Waiting for remaining approvers before publishing.'), child: const Text('Approve'))
                    : const Pill('Draft', color: Colors.blueGrey),
          ),
        ),
    ]);
  }
}
