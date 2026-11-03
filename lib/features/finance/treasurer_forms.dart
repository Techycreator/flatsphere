import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;

import '../../widgets/tr_text.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../backend/backend.dart';
import '../../backend/bill_parser.dart';
import '../../backend/bill_reader.dart';
import '../../backend/finance_repo.dart';
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
      const SizedBox(height: 12),
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

Future<void> showDuesScheduleForm(BuildContext context, WidgetRef ref) async {
  final types = {for (final f in financeFlats(ref.read(duesProvider))) f.$2}.toList()..sort();
  Map<String, dynamic>? cur;
  try {
    cur = await FinanceRepo.duesSchedule();
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  final savedRates = (cur?['rates'] as Map?) ?? const {};
  var enabled = cur?['enabled'] as bool? ?? true;
  var perSqft = cur?['mode'] == 'per_sqft';
  var lateFee = cur?['late_fee_enabled'] as bool? ?? false;
  var billDay = (cur?['bill_day'] as num?)?.toInt() ?? 1;
  var dueDay = (cur?['due_day'] as num?)?.toInt() ?? 10;
  final prefix = TextEditingController(text: cur?['head_prefix'] as String? ?? 'Maintenance');
  final sqft = TextEditingController(text: cur?['rate_per_sqft']?.toString() ?? '');
  final fee = TextEditingController(text: cur?['late_fee_amount']?.toString() ?? '');
  final grace = TextEditingController(text: '${cur?['late_fee_grace_days'] ?? 5}');
  final rates = {for (final t in types) t: TextEditingController(text: savedRates[t]?.toString() ?? '')};
  Widget day(String label, int value, void Function(int) on) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('Day $d of the month'))],
    onChanged: (v) => on(v ?? value),
  );
  final ok = await _form(
    context,
    title: 'Automatic monthly bills',
    action: 'Save',
    validate: () {
      if (prefix.text.trim().isEmpty) return 'Enter a bill name, e.g. Maintenance';
      if (dueDay < billDay) return 'Due day must be on or after the bill day';
      if (enabled && !perSqft && rates.values.every((c) => (int.tryParse(c.text) ?? 0) <= 0)) {
        return 'Enter an amount for at least one flat type';
      }
      if (enabled && perSqft && (double.tryParse(sqft.text) ?? 0) <= 0) return 'Enter the rate per square foot';
      if (lateFee && (int.tryParse(fee.text) ?? 0) <= 0) return 'Enter the late fee amount';
      return null;
    },
    fields: (set) => [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: enabled,
        title: const Text('Raise maintenance bills every month'),
        onChanged: (v) => set(() => enabled = v),
      ),
      TextField(
        controller: prefix,
        decoration: const InputDecoration(
          labelText: 'Bill name *',
          helperText: 'Shown as e.g. "Maintenance – Nov 2026"',
        ),
      ),
      day('Raise bill on', billDay, (v) => set(() => billDay = v)),
      day('Due by', dueDay, (v) => set(() => dueDay = v)),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('By flat type')),
          ButtonSegment(value: true, label: Text('Per sq. ft')),
        ],
        selected: {perSqft},
        onSelectionChanged: (v) => set(() => perSqft = v.first),
      ),
      if (perSqft)
        TextField(
          controller: sqft,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate per sq. ft', prefixText: '₹ '),
        )
      else
        for (final t in types)
          TextField(
            controller: rates[t],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: t, prefixText: '₹ '),
          ),
      const Divider(height: 24),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: lateFee,
        title: const Text('Add a late fee if unpaid'),
        onChanged: (v) => set(() => lateFee = v),
      ),
      if (lateFee) ...[
        TextField(
          controller: fee,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Late fee amount', prefixText: '₹ '),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: grace,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Days after due date before the fee is added'),
        ),
      ],
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Runs every morning (India time). A flat never gets the same bill twice. Reminders and receipts work as usual.',
          style: _note,
        ),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    await FinanceRepo.saveDuesSchedule(
      enabled: enabled,
      mode: perSqft ? 'per_sqft' : 'flat_type',
      rates: {
        for (final e in rates.entries)
          if ((int.tryParse(e.value.text) ?? 0) > 0) e.key: int.parse(e.value.text),
      },
      ratePerSqft: perSqft ? double.tryParse(sqft.text) : null,
      headPrefix: prefix.text.trim(),
      billDay: billDay,
      dueDay: dueDay,
      lateFeeEnabled: lateFee,
      lateFeeAmount: lateFee ? int.tryParse(fee.text) : null,
      graceDays: (int.tryParse(grace.text) ?? 5).clamp(0, 60),
    );
    return enabled ? 'Automatic bills on: raised on day $billDay, due on day $dueDay' : 'Automatic bills turned off';
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: '${l.paymentReceived} *', prefixText: '₹ '),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: mode,
        decoration: InputDecoration(labelText: l.paymentMode),
        items: [
          for (final e in paymentModes.entries)
            if (e.key != 'online') DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => set(() => mode = v ?? mode),
      ),
      const SizedBox(height: 12),
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

final pettyCashBalanceProvider = FutureProvider.autoDispose<int?>(
  (ref) async => backendEnabled ? FinanceRepo.pettyCashBalance() : null,
);

Future<void> showPettyCashForm(BuildContext context, WidgetRef ref) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  var date = DateUtils.dateOnly(DateTime.now());
  final ok = await _form(
    context,
    title: 'Give petty cash to caretaker',
    action: 'Save',
    validate: () => (int.tryParse(amount.text) ?? 0) <= 0 ? 'Enter the amount' : null,
    fields: (set) => [
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Amount *', prefixText: '₹ '),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('Given on ${dateFmt.format(date)}'),
        onPressed: () async {
          final d = await _pickDate(context, date);
          if (d != null) set(() => date = d);
        },
      ),
      TextField(
        controller: note,
        decoration: const InputDecoration(labelText: 'Note (e.g. cash from office)'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    await FinanceRepo.addPettyCash(int.parse(amount.text), date, note.text.trim());
    ref.invalidate(pettyCashBalanceProvider);
    return 'Petty cash recorded';
  });
}

Future<void> showExpenseForm(BuildContext context, WidgetRef ref, {bool pettyCash = false}) async {
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
  var reading = false;
  String? readNote;
  final ok = await _form(
    context,
    title: pettyCash ? 'Petty cash expense' : 'Add expense',
    action: 'Submit for verification',
    validate: () {
      if (vendor.text.trim().isEmpty) return 'Enter the vendor or payee';
      if ((int.tryParse(amount.text) ?? 0) <= 0) return 'Enter the amount';
      return null;
    },
    fields: (set) => [
      FilledButton.tonalIcon(
        icon: reading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(bill == null ? Icons.document_scanner_outlined : Icons.check_circle),
        label: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            reading ? 'Reading the bill…' : (bill == null ? 'Add bill photo first (fills the form)' : bill!.name),
          ),
        ),
        onPressed: reading
            ? null
            : () async {
                final b = await pickBill(context);
                if (b == null) return;
                set(() {
                  bill = b;
                  readNote = null;
                });
                if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(b.ext.toLowerCase())) return;
                set(() => reading = true);
                final text = await readBillText(b.bytes);
                final g = text == null ? const BillGuess() : parseBill(text);
                set(() {
                  reading = false;
                  if (g.isEmpty) {
                    readNote = 'Could not read details from this photo. Please fill them in.';
                    return;
                  }
                  if (g.vendor != null && vendor.text.trim().isEmpty) vendor.text = g.vendor!;
                  if (g.amount != null) amount.text = '${g.amount}';
                  if (g.date != null) date = g.date!;
                  final extra = [
                    if (g.invoiceNo != null) 'Invoice ${g.invoiceNo}',
                    if (g.gstin != null) 'GSTIN ${g.gstin}',
                  ].join(' · ');
                  if (extra.isNotEmpty && description.text.trim().isEmpty) description.text = extra;
                  readNote = 'Filled from the bill. Please check every field before submitting.';
                });
              },
      ),
      if (readNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(readNote!, style: _note),
        ),
      const SizedBox(height: 8),
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
      const SizedBox(height: 12),
      TextField(
        controller: vendor,
        decoration: const InputDecoration(labelText: 'Vendor / payee *'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: description,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Amount *', prefixText: '₹ '),
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
          paidFrom: pettyCash ? 'petty_cash' : 'association',
        );
    ref.invalidate(pettyCashBalanceProvider);
    return 'Expense submitted to the Treasurer';
  });
}
