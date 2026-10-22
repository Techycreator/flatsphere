import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';
import 'analysis_data.dart';
import 'analysis_tab.dart';
import 'charts.dart';
import 'treasurer_forms.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final full = role.isOfficeBearer || role == Role.auditor;
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
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: t.$1)],
            ),
          ),
          if (role == Role.auditor)
            MaterialBanner(
              content: const Text('Read-only auditor access · FY 2025-26 · expires 31 Dec 2026'),
              leading: const Icon(Icons.lock_clock),
              actions: [
                TextButton(
                  onPressed: () => toast(context, 'Auditor pack (Excel + PDF + documents zip) prepared'),
                  child: const Text('Download auditor pack'),
                ),
              ],
            ),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
        ],
      ),
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
    final defaulters = {
      for (final l in dues.lines)
        if (!l.isPaid) l.flatNumber,
    }.length;
    final role = ref.watch(sessionProvider)!.activeRole;
    final today = ref.watch(clockProvider);
    final thisMonth = DateFormat('MMM yyyy').format(today);
    final bal = ref.watch(bankBalanceProvider);
    final spent = ref
        .watch(expensesProvider)
        .where((e) => e.status == ExpenseStatus.approved && e.date.year == today.year && e.date.month == today.month)
        .fold(0, (s, e) => s + e.amount);
    return PageBody(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(avatar: const Icon(Icons.date_range, size: 18), label: Text('$currentFy · Apr 2026 – Mar 2027')),
            Chip(avatar: const Icon(Icons.update, size: 18), label: Text('Figures as of ${dateFmt.format(today)}')),
          ],
        ),
        const SizedBox(height: 12),
        StatGrid(
          children: [
            StatCard(
              label: backendEnabled
                  ? 'Bank balance · ${dues.opening?.account ?? 'not set'}'
                  : 'Bank balance (SBI ••••4521)',
              value: bal == null ? 'Not set' : inr.format(bal),
              icon: Icons.account_balance,
              sub: bal == null ? 'Treasurer: set the opening balance under Dues' : 'As of ${dateFmt.format(today)}',
            ),
            StatCard(
              label: 'Dues collected',
              value: inr.format(collected),
              icon: Icons.south_west,
              color: AppColors.green,
              sub: '$thisMonth bills, arrears & corpus',
            ),
            StatCard(
              label: 'Pending dues',
              value: inr.format(pending),
              icon: Icons.pending_actions,
              color: AppColors.amber,
              sub: '$defaulters flats · as of ${dateFmt.format(today)}',
            ),
            StatCard(
              label: 'Spent – $thisMonth (to date)',
              value: backendEnabled ? inr.format(spent) : '₹1,49,000',
              icon: Icons.north_east,
              color: AppColors.red,
              sub: backendEnabled ? 'Approved expenses' : '62% of monthly budget',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (role == Role.ecMember || role == Role.monitor)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'EC view: summary level. Detailed ledgers are visible to office bearers as configured by the Secretary.',
            ),
          ),
        if (backendEnabled)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'The charts, income breakdown and Analysis tab still show sample figures. '
              'They will switch to your records once a few months of data are entered.',
            ),
          ),
        const TwoCol(
          left: SectionCard(title: 'Income vs expenditure (May – Oct 2026)', child: IncomeExpenseChart()),
          right: SectionCard(title: 'Expenditure by category – Sep 2026 (last closed month)', child: ExpensePie()),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Income by category – $currentFy to date (Apr – Oct 2026)',
          child: Column(
            children: [
              for (final (k, v) in const [
                ('Monthly maintenance', 1584000),
                ('Corpus fund', 600000),
                ('Advertisement (lift panels – AdVantage Media)', 36000),
                ('Sponsorship – Onam (Lulu Hypermarket, Muthoot Finance)', 75000),
                ('Party hall rental', 28500),
                ('Late fees', 4200),
                ('Bank interest', 11840),
              ])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(k),
                  trailing: Text(inr.format(v), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DuesTab extends ConsumerWidget {
  const _DuesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(duesProvider);
    final n = ref.read(duesProvider.notifier);
    final role = ref.watch(sessionProvider)!.activeRole;
    final canRemind = role == Role.treasurer || role == Role.jointTreasurer || role == Role.secretary;
    final canRecord = role == Role.treasurer || role == Role.jointTreasurer;
    final flats = financeFlats(st);
    final owners = backendEnabled ? const <String, String>{} : {for (final f in demoFlats) f.number: f.ownerName};
    final pendingFlats = {
      for (final l in st.lines)
        if (!l.isPaid) l.flatNumber,
    };
    final o = st.opening;
    final recent = st.payments.reversed.take(10).toList();

    return PageBody(
      children: [
        if (canRecord) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => showPaymentForm(context, ref),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Record payment'),
              ),
              OutlinedButton.icon(
                onPressed: () => showRaiseDuesForm(context, ref),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Raise dues'),
              ),
              OutlinedButton.icon(
                onPressed: () => showOpeningBalanceForm(context, ref),
                icon: const Icon(Icons.account_balance),
                label: Text(o == null ? 'Set opening balance' : 'Edit opening balance'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (backendEnabled)
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text(
                o == null ? 'Opening balance not set yet' : 'Opening balance ${inr.format(o.amount)} · ${o.account}',
              ),
              subtitle: Text(
                o == null
                    ? 'The Treasurer enters the bank balance on the day records start (e.g. 1 Apr).'
                    : 'At the start of ${dateFmt.format(o.asOf)}. Bank balance = opening + payments received '
                          '− approved expenses since then.',
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pendingFlats.length} flats have pending dues',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Limit: 1 reminder per flat per day, 1 bulk reminder per day',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (canRemind)
                  FilledButton.icon(
                    onPressed: n.canBulk && pendingFlats.isNotEmpty
                        ? () {
                            final c = n.remindAll();
                            toast(context, 'Reminder sent to $c flats (push + email; WhatsApp/SMS after 2nd reminder)');
                          }
                        : null,
                    icon: const Icon(Icons.campaign),
                    label: Text(n.canBulk ? 'Remind all pending' : 'Bulk sent today'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (flats.isEmpty)
          const EmptyState('No flats yet. Add them in Flats & people.', icon: Icons.apartment_outlined)
        else if (backendEnabled && st.lines.isEmpty)
          EmptyState(
            canRecord
                ? 'No dues raised yet. Use "Raise dues" to bill every flat, e.g. Maintenance for this month.'
                : 'No dues raised yet.',
            icon: Icons.receipt_long_outlined,
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Flat')),
                  const DataColumn(label: Text('Type')),
                  if (owners.isNotEmpty) const DataColumn(label: Text('Owner')),
                  const DataColumn(label: Text('Charged'), numeric: true),
                  const DataColumn(label: Text('Paid'), numeric: true),
                  const DataColumn(label: Text('Pending'), numeric: true),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('Actions')),
                ],
                rows: [
                  for (final (number, type) in flats)
                    () {
                      final lines = st.lines.where((l) => l.flatNumber == number).toList();
                      final charged = lines.fold(0, (s, l) => s + l.amount);
                      final paid = lines.fold(0, (s, l) => s + l.paid);
                      final pending = st.pendingFor(number);
                      final open = lines.where((l) => !l.isPaid).length;
                      return DataRow(
                        cells: [
                          DataCell(Text(number, style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(type)),
                          if (owners.isNotEmpty) DataCell(Text(owners[number] ?? '–')),
                          DataCell(Text(charged == 0 ? '–' : inr.format(charged))),
                          DataCell(Text(paid == 0 ? '–' : inr.format(paid))),
                          DataCell(Text(pending <= 0 ? '–' : inr.format(pending))),
                          DataCell(
                            lines.isEmpty
                                ? const Text('No dues')
                                : open == 0
                                ? const Pill('Paid', color: AppColors.green)
                                : Pill('$open due', color: AppColors.red),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canRecord)
                                  TextButton.icon(
                                    onPressed: () => showPaymentForm(context, ref, flat: number),
                                    icon: const Icon(Icons.receipt_long, size: 18),
                                    label: const Text('Record'),
                                  ),
                                if (pending > 0 && canRemind)
                                  n.canRemind(number)
                                      ? TextButton.icon(
                                          onPressed: () {
                                            n.remind(number);
                                            toast(context, 'Reminder sent to $number');
                                          },
                                          icon: const Icon(Icons.notifications_active_outlined, size: 18),
                                          label: const Text('Remind'),
                                        )
                                      : const Text('Sent today', style: TextStyle(color: Colors.black45)),
                              ],
                            ),
                          ),
                        ],
                      );
                    }(),
                ],
              ),
            ),
          ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Recent receipts',
            padding: false,
            child: Column(
              children: [
                for (final p in recent)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.receipt_outlined),
                    title: Text('${p.receiptNo} · ${p.flatNumber}${p.head == null ? ' · advance' : ' · ${p.head}'}'),
                    subtitle: Text(
                      '${dateFmt.format(p.paidOn)} · ${paymentModes[p.mode] ?? p.mode}'
                      '${p.reference == null ? '' : ' · ref ${p.reference}'}',
                    ),
                    trailing: Text(inr.format(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(expensesProvider);
    final n = ref.read(expensesProvider.notifier);
    final role = ref.watch(sessionProvider)!.activeRole;
    final canEnter = const {Role.treasurer, Role.jointTreasurer, Role.secretary, Role.jointSecretary}.contains(role);

    void fail(Object err) {
      if (context.mounted) toast(context, friendlyError(err));
    }

    Future<void> act(Expense e, String action, [String? comment]) async {
      try {
        await n.decide(e, action, comment);
      } catch (err) {
        fail(err);
      }
    }

    Future<void> sendBack(Expense e) async {
      final c = await promptText(context, title: 'Send back ${e.id}', hint: 'What is missing? (e.g. GST invoice)');
      if (c != null) await act(e, 'send_back', c);
    }

    Future<void> attach(Expense e) async {
      final f = await pickBill(context);
      if (f == null) return;
      try {
        await n.attachBill(e, f.bytes, f.ext);
        if (context.mounted) toast(context, 'Bill attached to ${e.id}');
      } catch (err) {
        fail(err);
      }
    }

    Future<void> view(String path) async {
      try {
        final url = await n.billUrl(path);
        if (url == null) {
          if (context.mounted) toast(context, 'Demo mode: files are not stored');
          return;
        }
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      } catch (err) {
        fail(err);
      }
    }

    return PageBody(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Entered by Secretary/Treasurer → Treasurer verifies the bill → President approves. '
                'Nobody can verify or approve an expense they entered.',
              ),
            ),
            if (canEnter)
              FilledButton.tonalIcon(
                onPressed: () => showExpenseForm(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty) const EmptyState('No expenses recorded yet.', icon: Icons.receipt_long_outlined),
        for (final e in list) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${e.category} · ${e.vendor}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        inr.format(e.amount),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${e.id} · ${dateFmt.format(e.date)}${e.description.isEmpty ? '' : ' · ${e.description}'} · by ${e.enteredBy}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Pill(
                        e.status.label,
                        color: switch (e.status) {
                          ExpenseStatus.approved => AppColors.green,
                          ExpenseStatus.sentBack => AppColors.red,
                          _ => AppColors.amber,
                        },
                      ),
                      if (e.billPaths.isNotEmpty)
                        for (final (i, path) in e.billPaths.indexed)
                          ActionChip(
                            avatar: const Icon(Icons.receipt, size: 16),
                            label: Text('Bill ${i + 1}'),
                            tooltip: 'Open (link valid 60 seconds)',
                            onPressed: () => view(path),
                          )
                      else if (e.documents == 0)
                        const Pill('No bill attached', color: AppColors.red, icon: Icons.attach_file)
                      else
                        Pill('${e.documents} document(s)', color: Colors.blueGrey, icon: Icons.attach_file),
                      if (e.flagged) const Pill('Flagged by President', color: AppColors.amber, icon: Icons.flag),
                      if (e.comment != null)
                        Text('“${e.comment}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (role == Role.treasurer && e.status == ExpenseStatus.awaitingTreasurer) ...[
                        FilledButton(
                          onPressed: e.documents == 0 ? null : () => act(e, 'verify'),
                          child: const Text('Bill OK → President'),
                        ),
                        OutlinedButton(onPressed: () => sendBack(e), child: const Text('Send back')),
                      ],
                      if (role == Role.president && e.status == ExpenseStatus.awaitingPresident) ...[
                        FilledButton(onPressed: () => act(e, 'approve'), child: const Text('Approve')),
                        OutlinedButton(onPressed: () => sendBack(e), child: const Text('Send back')),
                      ],
                      if ((canEnter || role == Role.treasurer) &&
                          (e.status == ExpenseStatus.awaitingTreasurer || e.status == ExpenseStatus.sentBack))
                        TextButton.icon(
                          onPressed: () => attach(e),
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Attach bill'),
                        ),
                      if (canEnter && e.status == ExpenseStatus.sentBack)
                        TextButton.icon(
                          onPressed: () => act(e, 'resubmit'),
                          icon: const Icon(Icons.send),
                          label: const Text('Resubmit'),
                        ),
                      if (role == Role.president)
                        TextButton.icon(
                          onPressed: () => act(e, 'flag'),
                          icon: Icon(e.flagged ? Icons.flag : Icons.outlined_flag),
                          label: Text(e.flagged ? 'Unflag' : 'Flag for discussion'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _FundRequestsTab extends ConsumerWidget {
  const _FundRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    return PageBody(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('New fund requests need President approval and an EC MOM before reaching owners.'),
            ),
            if (role == Role.secretary)
              FilledButton.tonalIcon(
                onPressed: () => toast(context, 'Opens fund request form (name, recurring/adhoc, amount optional)'),
                icon: const Icon(Icons.add),
                label: const Text('New fund request'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final f in demoFundRequests)
                ListTile(
                  leading: Icon(f.kind.startsWith('Recurring') ? Icons.repeat : Icons.celebration_outlined),
                  title: Text(f.name),
                  subtitle: Text('${f.kind} · ${f.basis}${f.dueDay != null ? ' · due ${f.dueDay}' : ''}'),
                  trailing: Pill(
                    f.status,
                    color: f.status == 'Active'
                        ? AppColors.green
                        : (f.status == 'Draft' ? Colors.blueGrey : AppColors.amber),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Maintenance rates (by flat type)',
          child: Column(
            children: [
              for (final e in maintenanceRates.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key),
                  trailing: Text('${inr.format(e.value)} / month'),
                ),
              const Text(
                'Basis can be switched to per sq ft (W17: Secretary + Treasurer → President, with EC MOM). Late fee: ₹100 after 15 days, cap ₹500.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementsTab extends ConsumerWidget {
  const _StatementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    Widget sign(String who, bool ok) =>
        Pill(who, color: ok ? AppColors.green : Colors.blueGrey, icon: ok ? Icons.check : Icons.schedule);
    return PageBody(
      children: [
        const Text(
          'Statements are published to owners only after Treasurer, Secretary and President all approve. Published months are locked.',
        ),
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
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [sign('Treasurer', t), sign('Secretary', s), sign('President', p)],
                ),
              ),
              trailing: p
                  ? const Pill('Published', color: AppColors.green)
                  : (role == Role.secretary || role == Role.president)
                  ? FilledButton(
                      onPressed: () => toast(context, 'Approved. Waiting for remaining approvers before publishing.'),
                      child: const Text('Approve'),
                    )
                  : const Pill('Draft', color: Colors.blueGrey),
            ),
          ),
      ],
    );
  }
}
