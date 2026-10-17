import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'charts.dart';

class MyDuesScreen extends ConsumerWidget {
  const MyDuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionProvider)!;
    final flat = s.user.flatNumber ?? '';
    final lines = ref.watch(duesProvider).lines.where((x) => x.flatNumber == flat).toList();
    final pending = lines.fold(0, (a, x) => a + x.pending);

    Future<void> pay() async {
      final method = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Pay ${inr.format(pending)}'),
          children: [
            for (final (m, icon) in const [('UPI (GPay / PhonePe / Paytm)', Icons.qr_code_2), ('Debit / credit card', Icons.credit_card), ('Net banking', Icons.account_balance)])
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, m), child: ListTile(leading: Icon(icon), title: Text(m))),
            const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 0), child: Text('Demo: no real payment. Money settles directly to the association bank account.', style: TextStyle(fontSize: 12))),
          ],
        ),
      );
      if (method == null) return;
      final receipt = ref.read(duesProvider.notifier).pay(flat);
      if (context.mounted) toast(context, 'Payment successful via $method. Receipt $receipt sent by email/WhatsApp.');
    }

    return PageBody(maxWidth: 900, children: [
      Card(
        color: pending > 0 ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Flat $flat · total pending', style: Theme.of(context).textTheme.bodyMedium),
                Text(inr.format(pending), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (pending == 0) const Text('All dues cleared. Thank you!'),
              ]),
            ),
            if (pending > 0) FilledButton.icon(onPressed: pay, icon: const Icon(Icons.bolt), label: Padding(padding: const EdgeInsets.all(8), child: Text(l.payNow))),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Dues ledger',
        child: Column(children: [
          for (final x in lines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(x.head),
              subtitle: Text(x.isPaid ? 'Paid · receipt ${x.receiptNo}' : 'Due ${dateFmt.format(x.dueDate)}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inr.format(x.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                x.isPaid ? const Pill('Paid', color: AppColors.green) : const Pill('Pending', color: AppColors.red),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      const SectionCard(title: 'September 2026 statement (published)', child: ExpensePie()),
      const SizedBox(height: 8),
      Text('Approved by Treasurer, Secretary and President. Visible to owners only.', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
