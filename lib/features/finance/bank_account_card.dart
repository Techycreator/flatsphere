import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/bank_repo.dart';
import '../../widgets/common.dart';
import '../../widgets/tr_text.dart';
import '../../widgets/mom.dart';

final bankOverviewProvider = FutureProvider.autoDispose<BankOverview>((ref) => BankRepo.overview());

/// Shows the association's receiving bank account; the Treasurer can start an approved change.
class BankAccountCard extends ConsumerWidget {
  const BankAccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendEnabled) return const SizedBox.shrink();
    final data = ref.watch(bankOverviewProvider);
    return data.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => const SizedBox.shrink(),
      data: (b) {
        final acc = b.account;
        final pen = b.pending;
        Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(k, style: const TextStyle(color: Colors.black54)),
              ),
              Expanded(
                child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'Association bank account',
              action: b.canChange && pen == null
                  ? TextButton.icon(
                      onPressed: () => _requestChange(context, ref),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Change bank account'),
                    )
                  : null,
              child: acc == null
                  ? const Text('No bank account is set.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        row('Bank', '${acc.bankName}${acc.branch.isEmpty ? '' : ' \u00b7 ${acc.branch}'}'),
                        row('Account name', acc.accountName),
                        Row(
                          children: [
                            Expanded(child: row('Account number', acc.accountNumber)),
                            IconButton(
                              tooltip: 'Copy account number',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: acc.accountNumber));
                                toast(context, 'Account number copied');
                              },
                            ),
                          ],
                        ),
                        row('IFSC', acc.ifsc),
                        if (acc.isSample) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Sample details. The Treasurer replaces them with the real account using Change bank account.',
                            style: TextStyle(color: AppColors.amber, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
            ),
            if (pen != null) ...[
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFFFEF3C7),
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top_outlined, color: AppColors.amber),
                  title: Text('Bank change requested: ${pen.bankName} ${pen.maskedNumber}'),
                  subtitle: Text(
                    pen.status == 'cooling' && pen.effectiveAt != null
                        ? 'Approved. Takes effect after the 48-hour wait, on ${dateTimeFmt.format(pen.effectiveAt!)}.'
                        : 'Waiting for approval: Secretary, President, then EC vote.',
                  ),
                  trailing: pen.approvalRef == null
                      ? null
                      : TextButton(
                          onPressed: () => context.go('/approvals/${pen.approvalRef}'),
                          child: const Text('View approval'),
                        ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _requestChange(BuildContext context, WidgetRef ref) async {
    final bank = TextEditingController();
    final branch = TextEditingController();
    final holder = TextEditingController();
    final number = TextEditingController();
    final ifsc = TextEditingController();
    final reason = TextEditingController();
    final mom = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Change bank account'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This starts an approval: Secretary, President, then an EC vote. The new account becomes active 48 hours after the final approval.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bank,
                    decoration: const InputDecoration(labelText: 'Bank name *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: branch,
                    decoration: const InputDecoration(labelText: 'Branch'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: holder,
                    decoration: const InputDecoration(labelText: 'Account holder name *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: number,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Account number *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ifsc,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'IFSC code *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Reason for the change *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'MOM – approved meeting minutes *',
                      helperText: approvedMomOptions(context).isEmpty
                          ? 'No approved minutes yet. Approve the EC meeting minutes in Meetings first.'
                          : null,
                      helperMaxLines: 2,
                    ),
                    items: [
                      for (final o in approvedMomOptions(context))
                        DropdownMenuItem(
                          value: o,
                          child: Text(o, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => mom.text = v ?? '',
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final msg = bank.text.trim().isEmpty || holder.text.trim().isEmpty
                    ? 'Enter the bank and account holder name'
                    : !RegExp(r'^\d{9,18}$').hasMatch(number.text.trim())
                    ? 'Account number must be 9 to 18 digits'
                    : !RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc.text.trim().toUpperCase())
                    ? 'Enter a valid IFSC code'
                    : reason.text.trim().length < 5
                    ? 'Enter the reason for the change'
                    : mom.text.trim().length < 3
                    ? 'Enter the MOM reference'
                    : null;
                if (msg != null) return set(() => err = msg);
                Navigator.pop(ctx, true);
              },
              child: const Text('Submit for approval'),
            ),
          ],
        ),
      ),
    );
    final values = (bank.text, branch.text, holder.text, number.text, ifsc.text.toUpperCase(), reason.text, mom.text);
    for (final c in [bank, branch, holder, number, ifsc, reason, mom]) {
      c.dispose();
    }
    if (ok != true || !context.mounted) return;
    try {
      await BankRepo.requestChange(
        bankName: values.$1.trim(),
        branch: values.$2.trim(),
        accountName: values.$3.trim(),
        accountNumber: values.$4.trim(),
        ifsc: values.$5.trim(),
        reason: values.$6.trim(),
        momRef: values.$7.trim(),
      );
      ref.invalidate(bankOverviewProvider);
      if (context.mounted) toast(context, 'Sent for approval. All committee members have been notified.');
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    }
  }
}
