import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/finance_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';
import 'analysis_data.dart';
import 'analysis_tab.dart';
import 'charts.dart';
import 'income_screen.dart';
import 'treasurer_forms.dart';

final monthlyStatementsProvider = FutureProvider.autoDispose<List<MonthlyStatement>>((ref) async =>
  backendEnabled ? FinanceRepo.statements() : const []);
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final l = AppLocalizations.of(context);
    final full = role.isOfficeBearer || role == Role.auditor;
    final tabs = <(String, Widget)>[
      ('Overview', const _Overview()),
      if (full) ('Income', const IncomeScreen()),
      ('Analysis', const AnalysisTab()),
      if (full) ('Dues & follow-ups', const _DuesTab()),
      if (full) ('Expenses', const _ExpensesTab()),
      ('Fund requests', const _FundRequestsTab()),
      ('Statements', const StatementsScreen()),
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
                  onPressed: () => _exportLedger(context, ref),
                    child: Text(l.exportLedgerCsv),
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
    final fiscalValue = ref.watch(sessionProvider)!.user.association?.settings['fiscal_year_start_month'];
    final fiscalStartMonth = fiscalValue is num ? fiscalValue.toInt().clamp(1, 12).toInt() : 4;
    final thisMonth = DateFormat('MMM yyyy').format(today);
    final fyStart = DateTime(today.month >= fiscalStartMonth ? today.year : today.year - 1, fiscalStartMonth, 1);
    final fiscalStartYear = today.month >= fiscalStartMonth ? today.year : today.year - 1;
    final currentFyLabel = 'FY $fiscalStartYear-${(fiscalStartYear + 1).toString().substring(2)}';
    final incomeByCategory = <String, int>{};
    for (final entry in ref.watch(incomeProvider).entries.where((e) => !e.receivedOn.isBefore(fyStart))) {
      incomeByCategory.update(entry.categoryName, (value) => value + entry.amount, ifAbsent: () => entry.amount);
    }
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
            Chip(avatar: const Icon(Icons.date_range, size: 18), label: Text('$currentFyLabel · ${DateFormat('MMM').format(fyStart)} $fiscalStartYear – ${DateFormat('MMM').format(DateTime(fiscalStartYear + 1, fiscalStartMonth, 0))} ${fiscalStartYear + 1}')),
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
              'Overview trend charts still show illustrative figures. The Analysis tab and ledger exports use recorded association data.',
            ),
          ),
        const TwoCol(
          left: SectionCard(title: 'Income vs expenditure (May – Oct 2026)', child: IncomeExpenseChart()),
          right: SectionCard(title: 'Expenditure by category – Sep 2026 (last closed month)', child: ExpensePie()),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Income by category – $currentFyLabel to date',
          child: incomeByCategory.isEmpty
              ? const EmptyState('No income entries recorded this financial year.', icon: Icons.south_west)
              : Column(
                  children: [
                    for (final entry in incomeByCategory.entries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.key),
                        trailing: Text(inr.format(entry.value), style: const TextStyle(fontWeight: FontWeight.w600)),
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
    final l = AppLocalizations.of(context);
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
                label: Text(l.recordPayment),
              ),
              OutlinedButton.icon(
                onPressed: () => showRaiseDuesForm(context, ref),
                icon: const Icon(Icons.playlist_add),
                label: Text(l.raiseDues),
              ),
              OutlinedButton.icon(
                onPressed: () => showRaiseDuesPerSqftForm(context, ref),
                icon: const Icon(Icons.square_foot),
                label: const Text('Per-square-foot charge'),
              ),
              OutlinedButton.icon(
                onPressed: () => showFixedLateFeeForm(context, ref),
                icon: const Icon(Icons.schedule_send_outlined),
                label: const Text('Apply late fee'),
              ),
              OutlinedButton.icon(
                onPressed: () => showOpeningBalanceForm(context, ref),
                icon: const Icon(Icons.account_balance),
                label: Text(o == null ? l.setOpeningBalance : l.editOpeningBalance),
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
                                ? Text(l.noDues)
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

final fundRequestsProvider = FutureProvider.autoDispose<List<FundRequestRecord>>((ref) async {
  if (backendEnabled) return FinanceRepo.fundRequests();
  return [
    for (final request in demoFundRequests)
      FundRequestRecord(
        id: request.name,
        title: request.name,
        type: request.kind.toLowerCase().startsWith('recurring') ? 'recurring' : 'ad_hoc',
        status: request.status.toLowerCase(),
        amount: null,
        basis: request.basis,
        dueDay: request.dueDay,
        momRef: 'Demo MOM',
      ),
  ];
});

class _FundRequestsTab extends ConsumerWidget {
  const _FundRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final l = AppLocalizations.of(context);
    final records = ref.watch(fundRequestsProvider);
    final canRequest = role == Role.secretary || role == Role.jointSecretary || role == Role.treasurer || role == Role.jointTreasurer;

    Future<void> addRequest() async {
      final draft = await _fundRequestDialog(context);
      if (draft == null || !context.mounted) return;
      try {
        if (backendEnabled) {
          await FinanceRepo.requestFund(
            title: draft.title,
            type: draft.type,
            amount: draft.amount,
            basis: draft.basis,
            dueDay: draft.dueDay,
            momRef: draft.momRef,
            requestRef: ref.read(approvalsProvider.notifier).nextId(),
          );
          await ref.read(approvalsProvider.notifier).refresh();
        }
        ref.invalidate(fundRequestsProvider);
        if (context.mounted) toast(context, 'Fund request submitted for President approval');
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    return PageBody(
      children: [
        Row(
          children: [
            const Expanded(child: Text('Fund requests require President approval and an EC MOM reference.')),
            if (canRequest)
              FilledButton.tonalIcon(onPressed: addRequest, icon: const Icon(Icons.add), label: const Text('New request')),
          ],
        ),
        const SizedBox(height: 12),
        if (records.isLoading) const LinearProgressIndicator(),
        if (records.hasError) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${records.error}'))),
        if (records.hasValue && records.value!.isEmpty)
          const EmptyState('No fund requests yet.', icon: Icons.request_quote_outlined),
        if (records.hasValue)
          for (final request in records.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(request.type == 'recurring' ? Icons.repeat : Icons.campaign_outlined),
                title: Text(request.title),
                subtitle: Text(
                  '${request.type == 'recurring' ? 'Recurring' : 'Ad hoc'} · ${request.basis}'
                  '${request.amount == null ? '' : ' · ${inr.format(request.amount)}'}'
                  '${request.dueDay == null ? '' : ' · due ${request.dueDay}'} · MOM ${request.momRef}',
                ),
                isThreeLine: true,
                trailing: Pill(
                  request.status,
                  color: request.status == 'active'
                      ? AppColors.green
                      : request.status == 'rejected'
                      ? AppColors.red
                      : AppColors.amber,
                ),
              ),
            ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Maintenance rates (by flat type)',
          child: Column(
            children: [
              for (final e in maintenanceRates.entries)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(e.key), trailing: Text('${inr.format(e.value)} / month')),
              const Text(
                'Per-square-foot billing and late-fee rules will be configured and approved separately.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FundRequestDraft {
  const _FundRequestDraft({required this.title, required this.type, required this.amount, required this.basis, required this.dueDay, required this.momRef});
  final String title;
  final String type;
  final int? amount;
  final String basis;
  final String dueDay;
  final String momRef;
}

Future<_FundRequestDraft?> _fundRequestDialog(BuildContext context) async {
  final title = TextEditingController();
  final amount = TextEditingController();
  final basis = TextEditingController();
  final dueDay = TextEditingController();
  final momRef = TextEditingController();
  var type = 'ad_hoc';
  String? error;
  final draft = await showDialog<_FundRequestDraft>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('New fund request'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Request name *')),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [DropdownMenuItem(value: 'ad_hoc', child: Text('Ad hoc')), DropdownMenuItem(value: 'recurring', child: Text('Recurring'))],
                onChanged: (value) => set(() => type = value ?? type),
              ),
              TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Amount (optional)', prefixText: '₹ ')),
              TextField(controller: basis, decoration: const InputDecoration(labelText: 'Basis / per-flat details')),
              if (type == 'recurring') TextField(controller: dueDay, decoration: const InputDecoration(labelText: 'Due day / schedule')),
              TextField(controller: momRef, decoration: const InputDecoration(labelText: 'EC MOM reference *')),
              if (error != null) Align(alignment: Alignment.centerLeft, child: Text(error!)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (title.text.trim().isEmpty || momRef.text.trim().isEmpty) return set(() => error = 'Name and MOM reference are required');
            Navigator.pop(ctx, _FundRequestDraft(title: title.text.trim(), type: type, amount: int.tryParse(amount.text), basis: basis.text.trim(), dueDay: dueDay.text.trim(), momRef: momRef.text.trim()));
          }, child: const Text('Submit')),
        ],
      ),
    ),
  );
  title.dispose(); amount.dispose(); basis.dispose(); dueDay.dispose(); momRef.dispose();
  return draft;
}

class StatementsScreen extends ConsumerWidget {
  const StatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final l = AppLocalizations.of(context);
    final currentUserId = ref.watch(sessionProvider)!.user.id;
    final statements = ref.watch(monthlyStatementsProvider);
    final budgets = ref.watch(annualBudgetsProvider);
    final canGenerate = backendEnabled && (role == Role.treasurer || role == Role.jointTreasurer);

    Future<void> generate() async {
      final now = DateTime.now();
      final selected = await showDatePicker(
        context: context,
        initialDate: DateTime(now.year, now.month, 1),
        firstDate: DateTime(2015),
        lastDate: DateUtils.dateOnly(now),
        helpText: 'Choose any day in the statement month',
      );
      if (selected == null || !context.mounted) return;
      try {
        await FinanceRepo.createMonthlyStatement(DateTime(selected.year, selected.month, 1));
        ref.invalidate(monthlyStatementsProvider);
          ref.invalidate(appNotificationsProvider);
          if (context.mounted) toast(context, l.statementAwaitingTreasurer);
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    Future<void> decide(MonthlyStatement statement, String action) async {
      String? note;
      if (action == 'reject') {
          note = await promptText(context, title: l.rejected, hint: 'Reason (required)');
        if (note == null) return;
      }
      try {
        await FinanceRepo.decideMonthlyStatement(statement.id, action, note);
        ref.invalidate(monthlyStatementsProvider);
        ref.invalidate(appNotificationsProvider);
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    Future<void> submitBudget() async {
      final draft = await _annualBudgetDialog(context, ref);
      if (draft == null || !context.mounted) return;
      try {
        await FinanceRepo.submitAnnualBudget(
          fiscalYearStart: draft.fiscalYearStart,
          fiscalYearEnd: draft.fiscalYearEnd,
          categoryAmounts: draft.amounts,
          resolutionRef: draft.resolutionRef,
          resolutionDate: draft.resolutionDate,
        );
        ref.invalidate(annualBudgetsProvider);
        ref.invalidate(appNotificationsProvider);
        if (context.mounted) toast(context, 'Annual budget submitted for Secretary review');
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    Future<void> decideBudget(AnnualBudget budget, String action) async {
      String? note;
      if (action == 'reject') {
        note = await promptText(context, title: l.rejected, hint: 'Reason (required)');
        if (note == null) return;
      }
      try {
        await FinanceRepo.decideAnnualBudget(budget.id, action, note);
        ref.invalidate(annualBudgetsProvider);
        ref.invalidate(appNotificationsProvider);
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    Widget sign(String who, bool ok) =>
        Pill(who, color: ok ? AppColors.green : Colors.blueGrey, icon: ok ? Icons.check : Icons.schedule);
    return PageBody(
      children: [
        Row(
          children: [
              Expanded(child: Text(l.monthlyStatementDescription)),
            if (canGenerate)
                FilledButton.icon(onPressed: generate, icon: const Icon(Icons.add), label: Text(l.createStatement)),
          ],
        ),
        const SizedBox(height: 12),
          if (role.isOfficeBearer || role == Role.auditor)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _exportLedger(context, ref),
                icon: const Icon(Icons.download_outlined),
                  label: Text(l.exportLedgerCsv),
              ),
            ),
            Text(l.statementApprovalDescription),
          const SizedBox(height: 12),
          if (statements.isLoading) const LinearProgressIndicator(),
          if (statements.hasError)
            Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${statements.error}'))),
          if (statements.hasValue && statements.value!.isEmpty)
              EmptyState(l.noStatements, icon: Icons.receipt_long_outlined),
          if (statements.hasValue)
          for (final statement in statements.value!)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
                leading: Icon(statement.status == 'published' ? Icons.lock : Icons.edit_document),
                title: Text('Income & expenditure · ${DateFormat('MMMM yyyy').format(statement.periodStart)}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          sign('Treasurer', statement.treasurerApprovedBy != null),
                          sign('Secretary', statement.secretaryApprovedBy != null),
                          sign('President', statement.presidentApprovedBy != null),
                        ],
                      ),
                      if (statement.snapshot['totals'] case final Map totals)
                        Text(
                            '${l.incomeTotal} ${inr.format((totals['income'] as num?)?.toInt() ?? 0)} · '
                            '${l.approvedExpenses} ${inr.format((totals['approved_expenses'] as num?)?.toInt() ?? 0)} · '
                            '${l.paymentsReceived} ${inr.format((totals['payments_received'] as num?)?.toInt() ?? 0)}',
                        ),
                      if (statement.status == 'rejected' && statement.rejectionNote != null)
                        Text('Rejected: ${statement.rejectionNote}'),
                    ],
                  ),
                ),
                  trailing: _statementAction(role, currentUserId, statement, decide),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text(l.annualBudget, style: Theme.of(context).textTheme.titleMedium)),
              if (canGenerate) FilledButton.icon(onPressed: submitBudget, icon: const Icon(Icons.add), label: Text(l.submitBudget)),
            ],
          ),
          const SizedBox(height: 8),
          if (budgets.isLoading) const LinearProgressIndicator(),
          if (budgets.hasError) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${budgets.error}'))),
          if (budgets.hasValue && budgets.value!.isEmpty)
            EmptyState(l.annualBudgetNoRecords, icon: Icons.account_balance_outlined),
          if (budgets.hasValue)
            for (final budget in budgets.value!)
              _AnnualBudgetCard(
                budget: budget,
                role: role,
                currentUserId: currentUserId,
                onDecision: (action) => decideBudget(budget, action),
              ),
      ],
    );
  }

  Widget _statementAction(
    Role role,
    String currentUserId,
    MonthlyStatement statement,
    Future<void> Function(MonthlyStatement, String) decide,
  ) {
    final l = AppLocalizations.of(context);
    final canApprove = switch (statement.status) {
      'awaiting_treasurer' => role == Role.treasurer || role == Role.jointTreasurer,
      'awaiting_secretary' => role == Role.secretary,
      'awaiting_president' => role == Role.president,
      _ => false,
    };
    if (statement.status == 'published') return Pill(l.published, color: AppColors.green);
    if (statement.status == 'rejected') return Pill(l.rejected, color: AppColors.red);
    if (canApprove && statement.createdBy == currentUserId) {
      return Pill(AppLocalizations.of(context).differentReviewerRequired, color: AppColors.amber);
    }
    if (!canApprove) {
      final label = switch (statement.status) {
        'awaiting_treasurer' => l.statementAwaitingTreasurer,
        'awaiting_secretary' => l.statementAwaitingSecretary,
        _ => l.statementAwaitingPresident,
      };
      return Pill(label, color: AppColors.amber);
    }
    return Wrap(
      spacing: 4,
      children: [
        FilledButton(onPressed: () => decide(statement, 'approve'), child: const Text('Approve')),
        IconButton(tooltip: 'Reject', onPressed: () => decide(statement, 'reject'), icon: const Icon(Icons.close)),
      ],
    );
  }
}

class _AnnualBudgetDraft {
  const _AnnualBudgetDraft({
    required this.fiscalYearStart,
    required this.fiscalYearEnd,
    required this.amounts,
    required this.resolutionRef,
    required this.resolutionDate,
  });

  final DateTime fiscalYearStart;
  final DateTime fiscalYearEnd;
  final Map<String, int> amounts;
  final String resolutionRef;
  final DateTime resolutionDate;
}

Future<_AnnualBudgetDraft?> _annualBudgetDialog(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final now = DateTime.now();
  final configured = ref.read(sessionProvider)?.user.association?.settings['fiscal_year_start_month'];
  final startMonth = configured is num ? configured.toInt().clamp(1, 12).toInt() : 4;
  final startYear = now.month >= startMonth ? now.year : now.year - 1;
  final fiscalYearStart = DateTime(startYear, startMonth, 1);
  final fiscalYearEnd = DateTime(startYear + 1, startMonth, 0);
  final amounts = {for (final category in expenseCategories) category: TextEditingController()};
  final resolutionRef = TextEditingController();
  var resolutionDate = DateUtils.dateOnly(now);
  String? error;
  final draft = await showDialog<_AnnualBudgetDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('${l.annualBudget} · ${dateFmt.format(fiscalYearStart)} – ${dateFmt.format(fiscalYearEnd)}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in amounts.entries)
                  TextField(
                    controller: entry.value,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: entry.key, prefixText: '₹ '),
                  ),
                TextField(
                  controller: resolutionRef,
                  decoration: InputDecoration(labelText: '${l.annualBudgetReference} *'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: dialogContext,
                      initialDate: resolutionDate,
                      firstDate: DateTime(2015),
                      lastDate: DateUtils.dateOnly(now),
                    );
                    if (selected != null) setDialogState(() => resolutionDate = selected);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${l.annualBudgetDate} · ${dateFmt.format(resolutionDate)}'),
                ),
                if (error != null) Align(alignment: Alignment.centerLeft, child: Text(error!)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final values = {
                for (final entry in amounts.entries)
                  if ((int.tryParse(entry.value.text.trim()) ?? 0) > 0) entry.key: int.parse(entry.value.text.trim()),
              };
              if (values.isEmpty) return setDialogState(() => error = l.annualBudgetRequiredCategory);
              if (resolutionRef.text.trim().isEmpty) return setDialogState(() => error = '${l.annualBudgetReference} is required');
              Navigator.pop(dialogContext, _AnnualBudgetDraft(
                fiscalYearStart: fiscalYearStart,
                fiscalYearEnd: fiscalYearEnd,
                amounts: values,
                resolutionRef: resolutionRef.text.trim(),
                resolutionDate: resolutionDate,
              ));
            },
            child: Text(l.submitBudgetReview),
          ),
        ],
      ),
    ),
  );
  for (final controller in amounts.values) {
    controller.dispose();
  }
  resolutionRef.dispose();
  return draft;
}

class _AnnualBudgetCard extends StatelessWidget {
  const _AnnualBudgetCard({
    required this.budget,
    required this.role,
    required this.currentUserId,
    required this.onDecision,
  });

  final AnnualBudget budget;
  final Role role;
  final String currentUserId;
  final ValueChanged<String> onDecision;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isAwaitingSecretary = budget.status == 'awaiting_secretary';
    final isAwaitingPresident = budget.status == 'awaiting_president';
    final canApprove = (isAwaitingSecretary && role == Role.secretary) ||
        (isAwaitingPresident && role == Role.president);
    final sameReviewer = budget.createdBy == currentUserId || budget.secretaryApprovedBy == currentUserId;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('FY ${budget.fiscalYearStart.year}-${budget.fiscalYearEnd.year}',
                    style: Theme.of(context).textTheme.titleMedium)),
                Pill(switch (budget.status) {
                  'awaiting_secretary' => l.awaitingSecretary,
                  'awaiting_president' => l.awaitingPresident,
                  'approved' => l.approve,
                  _ => l.rejected,
                },
                    color: budget.status == 'approved' ? AppColors.green : AppColors.amber),
              ],
            ),
            Text('AGM/GBM ${budget.resolutionRef} · ${dateFmt.format(budget.resolutionDate)}'),
            for (final entry in budget.categoryAmounts.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key),
                trailing: Text(inr.format(entry.value)),
              ),
            if (budget.rejectionNote != null) Text('Rejected: ${budget.rejectionNote}'),
            if (canApprove && sameReviewer) Text(l.reviewerDifferent),
            if (canApprove && !sameReviewer)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(onPressed: () => onDecision('approve'), child: const Text('Approve')),
                  OutlinedButton(onPressed: () => onDecision('reject'), child: const Text('Reject')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _exportLedger(BuildContext context, WidgetRef ref) async {
  final dues = ref.read(duesProvider);
  final income = ref.read(incomeProvider);
  final expenses = ref.read(expensesProvider);
  String cell(Object? value) => '"${'${value ?? ''}'.replaceAll('"', '""')}"';
  final rows = <List<Object?>>[
    ['record_type', 'date', 'flat', 'category_or_head', 'description', 'amount', 'paid', 'pending', 'reference', 'status'],
    for (final due in dues.lines)
      ['due', DateFormat('yyyy-MM-dd').format(due.dueDate), due.flatNumber, due.head, '', due.amount, due.paid, due.pending, due.receiptNo, due.isPaid ? 'paid' : 'open'],
    for (final payment in dues.payments)
      ['receipt', DateFormat('yyyy-MM-dd').format(payment.paidOn), payment.flatNumber, payment.head ?? 'Advance', payment.mode, payment.amount, payment.amount, 0, '${payment.receiptNo}${payment.reference == null ? '' : ' / ${payment.reference}'}', 'received'],
    for (final entry in income.entries)
      ['income', DateFormat('yyyy-MM-dd').format(entry.receivedOn), '', entry.categoryName, entry.description, entry.amount, entry.amount, 0, entry.source ?? '', 'received'],
    for (final expense in expenses)
      ['expense', DateFormat('yyyy-MM-dd').format(expense.date), '', expense.category, '${expense.vendor} · ${expense.description}', expense.amount, 0, 0, expense.id, expense.status.label],
  ];
  final csv = rows.map((row) => row.map(cell).join(',')).join('\r\n');
  try {
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Export finance ledger',
      fileName: 'flatsphere-ledger-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (context.mounted && saved != null) toast(context, 'Ledger CSV exported');
  } catch (error) {
    if (context.mounted) toast(context, 'Could not export ledger: $error');
  }
}
