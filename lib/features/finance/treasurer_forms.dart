import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../backend/backend.dart';
import '../../backend/community_repo.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';

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
  final size = await f.length();
  if (size == null || size > maxSourceUploadBytes(f.extension ?? '')) {
    if (context.mounted) toast(context, 'File exceeds the supported source size');
    return null;
  }
  final bytes = await f.readAsBytes();
  return (bytes: bytes, ext: f.extension ?? 'jpg', name: f.name);
}

DateTime _fyStart(DateTime now, int startMonth) =>
    DateTime(now.month >= startMonth ? now.year : now.year - 1, startMonth, 1);

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
                for (final w in fields(set)) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
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
  final l = AppLocalizations.of(context);
  final cur = ref.read(duesProvider).opening;
  final account = TextEditingController(text: cur?.account ?? 'Bank account');
  final amount = TextEditingController(text: cur?.amount.toString() ?? '');
  final fiscalStart = ref.read(sessionProvider)?.user.association?.settings['fiscal_year_start_month'];
  final fiscalMonth = fiscalStart is num ? fiscalStart.toInt().clamp(1, 12).toInt() : 4;
  var asOf = cur?.asOf ?? _fyStart(DateTime.now(), fiscalMonth);
  final ok = await _form(
    context,
    title: l.openingBalance,
    action: l.save,
    validate: () => int.tryParse(amount.text.trim()) == null ? 'Enter the balance in rupees' : null,
    fields: (set) => [
      TextField(
        controller: account,
        decoration: InputDecoration(labelText: l.account, hintText: 'e.g. SBI current a/c ••••4521'),
      ),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: '${l.balance} *', prefixText: '₹ '),
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
  final l = AppLocalizations.of(context);
  final st = ref.read(duesProvider);
  final types = {for (final f in financeFlats(st)) f.$2}.toList()..sort();
  if (types.isEmpty) return toast(context, 'Add flats first in Flats & people');
  final now = DateTime.now();
  final head = TextEditingController(text: 'Maintenance – ${DateFormat('MMM yyyy').format(now)}');
  final rates = {
    for (final t in types) t: TextEditingController(text: backendEnabled ? '' : maintenanceRates[t]?.toString() ?? ''),
  };
  final configuredDueDay = ref.read(sessionProvider)?.user.association?.settings['default_due_day'];
  final defaultDueDay = configuredDueDay is num ? configuredDueDay.toInt().clamp(1, 28).toInt() : 10;
  var due = DateTime(now.year, now.month, defaultDueDay);
  int rate(String t) => int.tryParse(rates[t]!.text) ?? 0;
  final ok = await _form(
    context,
    title: l.raiseDues,
    action: l.raiseDues,
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
      Text(l.flatTypeAmount, style: const TextStyle(fontWeight: FontWeight.w600)),
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

Future<void> showRaiseDuesPerSqftForm(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final now = DateTime.now();
  final head = TextEditingController(text: 'Per-square-foot assessment – ${DateFormat('MMM yyyy').format(now)}');
  final rateController = TextEditingController();
  var dueDate = DateTime(now.year, now.month, 10);
  final ok = await _form(
    context,
    title: l.perSquareFootCharge,
    action: l.raiseDues,
    validate: () {
      if (head.text.trim().isEmpty) return 'Enter a dues name';
      final rate = double.tryParse(rateController.text.trim());
      if (rate == null || rate <= 0) return 'Enter a positive rate per square foot';
      return null;
    },
    fields: (set) => [
      TextField(
        controller: head,
        decoration: InputDecoration(labelText: '${l.duesName} *'),
      ),
      TextField(
        controller: rateController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
        decoration: InputDecoration(labelText: '${l.perSqFtRate} *', prefixText: '₹ '),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Due by ${dateFmt.format(dueDate)}'),
        onPressed: () async {
          final selected = await _pickDate(context, dueDate);
          if (selected != null) set(() => dueDate = selected);
        },
      ),
      const Text('Each flat is charged by recorded area; amounts are rounded to the nearest rupee.', style: _note),
    ],
  );
  if (ok != true || !context.mounted) return;
  final feeHead = head.text.trim();
  await _run(context, () async {
    final count = await ref
        .read(duesProvider.notifier)
        .raiseDuesPerSqft(feeHead, dueDate, double.parse(rateController.text.trim()));
    return count == 0 ? 'No new dues were created' : 'Raised "$feeHead" for $count flats';
  });
}

Future<void> showFixedLateFeeForm(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final feeName = TextEditingController(text: 'Late fee – ${DateFormat('MMM yyyy').format(DateTime.now())}');
  final amount = TextEditingController();
  var dueDate = DateTime.now().add(const Duration(days: 7));
  final ok = await _form(
    context,
    title: l.lateFeeFixed,
    action: l.applyLateFee,
    validate: () {
      if (feeName.text.trim().isEmpty) return 'Enter a fee name';
      if ((int.tryParse(amount.text.trim()) ?? 0) <= 0) return 'Enter a positive fixed amount';
      return null;
    },
    fields: (set) => [
      TextField(
        controller: feeName,
        decoration: InputDecoration(labelText: '${l.duesName} *'),
      ),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: '${l.fixedLateAmount} *', prefixText: '₹ '),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Due by ${dateFmt.format(dueDate)}'),
        onPressed: () async {
          final selected = await _pickDate(context, dueDate);
          if (selected != null) set(() => dueDate = selected);
        },
      ),
      const Text(
        'Applied once to each flat with a past-due unpaid charge. The fee name prevents duplicate application.',
        style: _note,
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  final name = feeName.text.trim();
  await _run(context, () async {
    final count = await ref.read(duesProvider.notifier).applyFixedLateFee(name, dueDate, int.parse(amount.text.trim()));
    return count == 0 ? 'No overdue flats were charged' : 'Applied "$name" to $count flats';
  });
}

Future<void> showPaymentForm(BuildContext context, WidgetRef ref, {String? flat}) async {
  final l = AppLocalizations.of(context);
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
    title: l.recordPaymentReceived,
    action: l.saveReceipt,
    validate: () => (int.tryParse(amount.text) ?? 0) <= 0 ? 'Enter the amount received' : null,
    fields: (set) => [
      DropdownButtonFormField<String>(
        initialValue: number,
        isExpanded: true,
        decoration: InputDecoration(labelText: l.directory),
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
        decoration: InputDecoration(labelText: l.myDues),
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
        decoration: InputDecoration(labelText: '${l.paymentReceived} *', prefixText: '₹ '),
      ),
      DropdownButtonFormField<String>(
        initialValue: mode,
        decoration: InputDecoration(labelText: l.paymentMode),
        items: [
          for (final e in paymentModes.entries)
            if (e.key != 'online') DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => set(() => mode = v ?? mode),
      ),
      TextField(
        controller: reference,
        decoration: InputDecoration(labelText: l.paymentReference, hintText: 'UPI ref, cheque no. or bank txn id'),
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
  var events = <CommunityEvent>[];
  if (backendEnabled) {
    try {
      events = await CommunityRepo.events();
    } catch (_) {}
  }
  var date = DateUtils.dateOnly(DateTime.now());
  var category = expenseCategories.first;
  String? eventId;
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
      if (events.isNotEmpty)
        DropdownButtonFormField<String?>(
          initialValue: eventId,
          decoration: const InputDecoration(labelText: 'Community event (optional)'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Not linked to an event')),
            for (final event in events)
              DropdownMenuItem<String?>(
                value: event.id,
                child: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => set(() => eventId = value),
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
          eventId: eventId,
        );
    return 'Expense submitted to the Treasurer';
  });
}
