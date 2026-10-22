import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../backend/backend.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';

const _maxBillBytes = 5 * 1024 * 1024;

typedef PickedFile = ({Uint8List bytes, String ext, String name});

/// Flats for finance screens: from the database in cloud mode, otherwise the demo list.
List<(String number, String type)> financeFlats(DuesState st) =>
    backendEnabled ? [for (final f in st.flats) (f.number, f.type)] : [for (final f in demoFlats) (f.number, f.type)];

Future<PickedFile?> pickBill(BuildContext context) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
  );
  if (files.isEmpty) return null;
  final f = files.first;
  final bytes = await f.readAsBytes();
  if (bytes.length > _maxBillBytes) {
    if (context.mounted) toast(context, 'That file is larger than 5 MB');
    return null;
  }
  return (bytes: bytes, ext: f.extension ?? 'jpg', name: f.name);
}

DateTime _fyStart(DateTime now) => DateTime(now.month >= 4 ? now.year : now.year - 1, 4, 1);

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2015), lastDate: DateTime(2040));

const _note = TextStyle(fontSize: 12);

Future<bool?> _form(
  BuildContext context, {
  required String title,
  required String action,
  required List<Widget> Function(StateSetter set) fields,
  required String? Function() validate,
}) {
  String? error;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...fields(set),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final e = validate();
              if (e != null) return set(() => error = e);
              Navigator.pop(ctx, true);
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

Future<void> _run(BuildContext context, Future<String> Function() f) async {
  try {
    final msg = await f();
    if (context.mounted) toast(context, msg);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

Future<void> showOpeningBalanceForm(BuildContext context, WidgetRef ref) async {
  final cur = ref.read(duesProvider).opening;
  final account = TextEditingController(text: cur?.account ?? 'Bank account');
  final amount = TextEditingController(text: cur?.amount.toString() ?? '');
  var asOf = cur?.asOf ?? _fyStart(DateTime.now());
  final ok = await _form(
    context,
    title: 'Opening balance',
    action: 'Save',
    validate: () => int.tryParse(amount.text.trim()) == null ? 'Enter the balance in rupees' : null,
    fields: (set) => [
      TextField(
        controller: account,
        decoration: const InputDecoration(labelText: 'Account', hintText: 'e.g. SBI current a/c ••••4521'),
      ),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Balance *', prefixText: '₹ '),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('At the start of ${dateFmt.format(asOf)}'),
        onPressed: () async {
          final d = await _pickDate(context, asOf);
          if (d != null) set(() => asOf = d);
        },
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Use the bank statement balance on the day you start recording in FlatSphere, usually 1 April. '
          'Payments received and approved expenses from that day on are added to it.',
          style: _note,
        ),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    await ref
        .read(duesProvider.notifier)
        .saveOpening(
          OpeningBalance(
            account: account.text.trim().isEmpty ? 'Bank account' : account.text.trim(),
            amount: int.parse(amount.text.trim()),
            asOf: asOf,
          ),
        );
    return 'Opening balance saved';
  });
}

Future<void> showRaiseDuesForm(BuildContext context, WidgetRef ref) async {
  final st = ref.read(duesProvider);
  final types = {for (final f in financeFlats(st)) f.$2}.toList()..sort();
  if (types.isEmpty) return toast(context, 'Add flats first in Flats & people');
  final now = DateTime.now();
  final head = TextEditingController(text: 'Maintenance – ${DateFormat('MMM yyyy').format(now)}');
  final rates = {
    for (final t in types) t: TextEditingController(text: backendEnabled ? '' : maintenanceRates[t]?.toString() ?? ''),
  };
  var due = DateTime(now.year, now.month, 10);
  int rate(String t) => int.tryParse(rates[t]!.text) ?? 0;
  final ok = await _form(
    context,
    title: 'Raise dues for all flats',
    action: 'Raise',
    validate: () {
      if (head.text.trim().isEmpty) return 'Enter a name, e.g. Maintenance – Nov 2026';
      if (types.every((t) => rate(t) <= 0)) return 'Enter an amount for at least one flat type';
      return null;
    },
    fields: (set) => [
      TextField(
        controller: head,
        decoration: const InputDecoration(
          labelText: 'Name *',
          helperText: 'Owners see this, e.g. Maintenance – Nov 2026 or Corpus fund (instalment 3)',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Due by ${dateFmt.format(due)}'),
        onPressed: () async {
          final d = await _pickDate(context, due);
          if (d != null) set(() => due = d);
        },
      ),
      const SizedBox(height: 12),
      const Text('Amount per flat type (leave empty to skip)', style: TextStyle(fontWeight: FontWeight.w600)),
      for (final t in types)
        TextField(
          controller: rates[t],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: t, prefixText: '₹ '),
        ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Flats that already have dues with this name are skipped, so it is safe to run again.',
          style: _note,
        ),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  final name = head.text.trim();
  await _run(context, () async {
    final n = await ref.read(duesProvider.notifier).raiseDues(name, due, {
      for (final t in types)
        if (rate(t) > 0) t: rate(t),
    });
    return n == 0 ? 'No new dues: every flat already has "$name"' : 'Raised "$name" for $n flats';
  });
}

Future<void> showPaymentForm(BuildContext context, WidgetRef ref, {String? flat}) async {
  final st = ref.read(duesProvider);
  final flats = [for (final f in financeFlats(st)) f.$1];
  if (flats.isEmpty) return toast(context, 'Add flats first in Flats & people');
  var number = flat ?? flats.first;
  List<DueLine> open(String f) => st.lines.where((l) => l.flatNumber == f && !l.isPaid).toList();
  var due = open(number).firstOrNull;
  final amount = TextEditingController(text: due?.pending.toString() ?? '');
  final reference = TextEditingController();
  var mode = 'upi';
  var paidOn = DateUtils.dateOnly(DateTime.now());
  final ok = await _form(
    context,
    title: 'Record payment received',
    action: 'Save & issue receipt',
    validate: () => (int.tryParse(amount.text) ?? 0) <= 0 ? 'Enter the amount received' : null,
    fields: (set) => [
      DropdownButtonFormField<String>(
        initialValue: number,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Flat'),
        items: [for (final f in flats) DropdownMenuItem(value: f, child: Text(f))],
        onChanged: (v) => set(() {
          number = v ?? number;
          due = open(number).firstOrNull;
          amount.text = due?.pending.toString() ?? '';
        }),
      ),
      DropdownButtonFormField<DueLine?>(
        key: ValueKey(number),
        initialValue: due,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Against'),
        items: [
          for (final l in open(number))
            DropdownMenuItem(value: l, child: Text('${l.head} · ${inr.format(l.pending)} pending')),
          const DropdownMenuItem(value: null, child: Text('Advance / other (not against a due)')),
        ],
        onChanged: (v) => set(() {
          due = v;
          if (v != null) amount.text = v.pending.toString();
        }),
      ),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Amount received *', prefixText: '₹ '),
      ),
      DropdownButtonFormField<String>(
        initialValue: mode,
        decoration: const InputDecoration(labelText: 'Mode'),
        items: [
          for (final e in paymentModes.entries)
            if (e.key != 'online') DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => set(() => mode = v ?? mode),
      ),
      TextField(
        controller: reference,
        decoration: const InputDecoration(labelText: 'Reference', hintText: 'UPI ref, cheque no. or bank txn id'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Received on ${dateFmt.format(paidOn)}'),
        onPressed: () async {
          final d = await _pickDate(context, paidOn);
          if (d != null) set(() => paidOn = d);
        },
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    final r = await ref
        .read(duesProvider.notifier)
        .recordPayment(
          flatNumber: number,
          due: due,
          amount: int.parse(amount.text),
          mode: mode,
          reference: reference.text.trim().isEmpty ? null : reference.text.trim(),
          paidOn: paidOn,
        );
    return 'Receipt $r recorded for $number';
  });
}

Future<void> showExpenseForm(BuildContext context, WidgetRef ref) async {
  final s = ref.read(sessionProvider)!;
  var date = DateUtils.dateOnly(DateTime.now());
  var category = expenseCategories.first;
  final vendor = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  PickedFile? bill;
  final ok = await _form(
    context,
    title: 'Add expense',
    action: 'Submit for verification',
    validate: () {
      if (vendor.text.trim().isEmpty) return 'Enter the vendor or payee';
      if ((int.tryParse(amount.text) ?? 0) <= 0) return 'Enter the amount';
      return null;
    },
    fields: (set) => [
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Spent on ${dateFmt.format(date)}'),
        onPressed: () async {
          final d = await _pickDate(context, date);
          if (d != null) set(() => date = d);
        },
      ),
      DropdownButtonFormField<String>(
        initialValue: category,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => set(() => category = v ?? category),
      ),
      TextField(
        controller: vendor,
        decoration: const InputDecoration(labelText: 'Vendor / payee *'),
      ),
      TextField(
        controller: description,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Amount *', prefixText: '₹ '),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: Icon(bill == null ? Icons.add_a_photo_outlined : Icons.check_circle),
        label: Text(bill == null ? 'Attach bill photo or PDF' : bill!.name),
        onPressed: () async {
          final b = await pickBill(context);
          if (b != null) set(() => bill = b);
        },
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'The Treasurer can only verify an expense once a bill is attached. '
          'You cannot verify or approve an expense you entered.',
          style: _note,
        ),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    await ref
        .read(expensesProvider.notifier)
        .add(
          date: date,
          category: category,
          vendor: vendor.text.trim(),
          description: description.text.trim(),
          amount: int.parse(amount.text),
          enteredBy: s.user.name,
          bill: bill?.bytes,
          ext: bill?.ext,
        );
    return 'Expense submitted to the Treasurer';
  });
}
