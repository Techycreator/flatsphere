import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;

import '../../widgets/tr_text.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

typedef _IncomeDraft = ({String categoryId, DateTime receivedOn, int amount, String source, String description});

class IncomeScreen extends ConsumerWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(incomeProvider);
    final role = ref.watch(sessionProvider)!.activeRole;
    final canRecord = role == Role.secretary || role == Role.treasurer;
    final active = state.categories.where((c) => c.status == IncomeCategoryStatus.active).toList();
    final pending = state.categories.where((c) => c.status != IncomeCategoryStatus.active).toList();

    Future<void> requestCategory() async {
      final name = await promptText(context, title: 'New income category', hint: 'e.g. Hall rental');
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      try {
        final refCode = await ref.read(incomeProvider.notifier).requestCategory(name.trim());
        if (context.mounted) toast(context, '$refCode submitted for President approval');
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    Future<void> recordIncome() async {
      final draft = await _incomeDialog(context, active);
      if (draft == null || !context.mounted) return;
      try {
        await ref
            .read(incomeProvider.notifier)
            .record(
              categoryId: draft.categoryId,
              receivedOn: draft.receivedOn,
              amount: draft.amount,
              source: draft.source,
              description: draft.description,
            );
        if (context.mounted) toast(context, 'Income recorded');
      } catch (error) {
        if (context.mounted) toast(context, friendlyError(error));
      }
    }

    return PageBody(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Income records', style: Theme.of(context).textTheme.headlineSmall),
            if (canRecord) ...[
              OutlinedButton.icon(
                onPressed: requestCategory,
                icon: const Icon(Icons.category_outlined),
                label: const Text('New category'),
              ),
              FilledButton.icon(
                onPressed: active.isEmpty ? null : recordIncome,
                icon: const Icon(Icons.add),
                label: const Text('Record income'),
              ),
            ],
          ],
        ),
        if (state.error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.error_outline), title: Text(state.error!)),
          ),
        if (state.loading) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Income categories',
          child: state.categories.isEmpty
              ? const EmptyState('No income categories yet. Request one to get started.', icon: Icons.category_outlined)
              : Column(
                  children: [
                    for (final category in [...active, ...pending])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          category.status == IncomeCategoryStatus.active ? Icons.check_circle_outline : Icons.schedule,
                          color: category.status == IncomeCategoryStatus.active ? AppColors.green : AppColors.amber,
                        ),
                        title: Text(category.name),
                        subtitle: category.status == IncomeCategoryStatus.active
                            ? null
                            : Text('${_statusLabel(category.status)} · ${category.requestRef}'),
                        trailing: Pill(
                          _statusLabel(category.status),
                          color: category.status == IncomeCategoryStatus.active
                              ? AppColors.green
                              : category.status == IncomeCategoryStatus.rejected
                              ? AppColors.red
                              : AppColors.amber,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        const _DuesCollections(),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Received income',
          padding: false,
          child: state.entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: EmptyState('No income has been recorded yet.', icon: Icons.south_west),
                )
              : Column(
                  children: [
                    for (final entry in state.entries)
                      ListTile(
                        leading: const Icon(Icons.south_west, color: AppColors.green),
                        title: Text('${entry.categoryName} · ${inr.format(entry.amount)}'),
                        subtitle: Text(
                          '${dateFmt.format(entry.receivedOn)} · ${entry.source ?? 'Source not specified'}'
                          '${entry.description.isEmpty ? '' : ' · ${entry.description}'}\nRecorded by ${entry.recordedBy}',
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

String _statusLabel(IncomeCategoryStatus status) => switch (status) {
  IncomeCategoryStatus.pending => 'Pending approval',
  IncomeCategoryStatus.active => 'Active',
  IncomeCategoryStatus.rejected => 'Rejected',
  IncomeCategoryStatus.sentBack => 'Sent back',
};

Future<_IncomeDraft?> _incomeDialog(BuildContext context, List<IncomeCategory> categories) async {
  if (categories.isEmpty) return null;
  final amount = TextEditingController();
  final source = TextEditingController();
  final description = TextEditingController();
  var categoryId = categories.first.id;
  var receivedOn = DateUtils.dateOnly(DateTime.now());
  String? error;
  final draft = await showDialog<_IncomeDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Record income'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Category *'),
                  items: [
                    for (final category in categories) DropdownMenuItem(value: category.id, child: Text(category.name)),
                  ],
                  onChanged: (value) => setState(() => categoryId = value ?? categoryId),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Amount in rupees *', prefixText: '₹ '),
                ),
                const SizedBox(height: 12),
                ChoiceOrOtherField(
                  controller: source,
                  label: 'Source / sponsor',
                  options: const [
                    'Hall booking',
                    'Sponsorship',
                    'Advertisement',
                    'Bank interest',
                    'Event collection',
                    'Donation',
                    'Scrap sale',
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: receivedOn,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) setState(() => receivedOn = date);
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Received ${dateFmt.format(receivedOn)}'),
                  ),
                ),
                if (error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsedAmount = int.tryParse(amount.text.trim());
              if (parsedAmount == null || parsedAmount <= 0) {
                return setState(() => error = 'Enter an amount greater than zero');
              }
              Navigator.pop(dialogContext, (
                categoryId: categoryId,
                receivedOn: receivedOn,
                amount: parsedAmount,
                source: source.text.trim(),
                description: description.text.trim(),
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  source.dispose();
  description.dispose();
  return draft;
}

/// Maintenance and other dues receipts, added here automatically when the Treasurer records a payment.
class _DuesCollections extends ConsumerWidget {
  const _DuesCollections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byMonth = <DateTime, (int, int)>{};
    for (final p in ref.watch(duesProvider).payments) {
      final m = DateTime(p.paidOn.year, p.paidOn.month);
      final cur = byMonth[m] ?? (0, 0);
      byMonth[m] = (cur.$1 + p.amount, cur.$2 + (p.amount > 0 && !p.reversed ? 1 : 0));
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return SectionCard(
      title: 'Maintenance & dues collections',
      child: months.isEmpty
          ? const EmptyState('No dues payments recorded yet.', icon: Icons.receipt_long_outlined)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Added automatically from each payment the Treasurer records under Dues. Reversed payments are deducted.',
                  style: TextStyle(fontSize: 12),
                ),
                for (final m in months.take(12))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.south_west, color: AppColors.green),
                    title: Text(DateFormat('MMMM yyyy').format(m)),
                    subtitle: Text('${byMonth[m]!.$2} receipts'),
                    trailing: Text(inr.format(byMonth[m]!.$1), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
    );
  }
}
