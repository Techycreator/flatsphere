import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'directory_repo.dart' show mimeFor;

String _date(DateTime d) => d.toIso8601String().substring(0, 10);

int _int(Object? v) => (v as num).toInt();

ExpenseStatus _status(Object? s) => switch (s) {
  'awaiting_president' => ExpenseStatus.awaitingPresident,
  'approved' => ExpenseStatus.approved,
  'sent_back' => ExpenseStatus.sentBack,
  _ => ExpenseStatus.awaitingTreasurer,
};

typedef DuesData = ({List<DueLine> lines, List<PaymentRecord> payments, List<FlatInfo> flats, OpeningBalance? opening});

/// Dues, payments, opening balance and expenses. Row-level security limits what each role reads;
/// expense decisions go through `decide_expense`, which enforces maker-checker.
class FinanceRepo {
  static const _bucket = 'bills';

  static Future<DuesData> dues() async {
    final flatRows = await db.from('flats').select('id, number, block, flat_type').order('number');
    final flats = [
      for (final r in flatRows)
        FlatInfo(
          id: r['id'] as String,
          number: r['number'] as String,
          block: r['block'] as String? ?? '',
          type: r['flat_type'] as String,
        ),
    ];
    final numberOf = {for (final f in flats) f.id: f.number};
    final dueRows = await db.from('dues').select('id, flat_id, head, amount, due_date').order('due_date');
    final payRows = await db
        .from('payments')
        .select('flat_id, due_id, amount, paid_on, mode, reference, receipt_no')
        .order('paid_on')
        .order('created_at');
    final ob = await db.from('opening_balances').select('account_name, amount, as_of').maybeSingle();
    final heads = {for (final r in dueRows) r['id'] as String: r['head'] as String};
    final paid = <String, int>{};
    final receipt = <String, String>{};
    final payments = <PaymentRecord>[];
    for (final r in payRows) {
      final due = r['due_id'] as String?;
      final amount = _int(r['amount']);
      if (due != null) {
        paid[due] = (paid[due] ?? 0) + amount;
        receipt[due] = r['receipt_no'] as String;
      }
      payments.add(
        PaymentRecord(
          flatNumber: numberOf[r['flat_id']] ?? '?',
          amount: amount,
          paidOn: DateTime.parse(r['paid_on'] as String),
          receiptNo: r['receipt_no'] as String,
          mode: r['mode'] as String,
          reference: r['reference'] as String?,
          head: heads[due],
        ),
      );
    }
    return (
      lines: [
        for (final r in dueRows)
          DueLine(
            id: r['id'] as String,
            flatId: r['flat_id'] as String,
            flatNumber: numberOf[r['flat_id']] ?? '?',
            head: r['head'] as String,
            amount: _int(r['amount']),
            paid: paid[r['id']] ?? 0,
            dueDate: DateTime.parse(r['due_date'] as String),
            receiptNo: receipt[r['id']],
          ),
      ],
      payments: payments,
      flats: flats,
      opening: ob == null
          ? null
          : OpeningBalance(
              account: ob['account_name'] as String,
              amount: _int(ob['amount']),
              asOf: DateTime.parse(ob['as_of'] as String),
            ),
    );
  }

  static Future<void> saveOpening(OpeningBalance o) async {
    final assoc = await db.rpc('my_association') as String;
    await db.from('opening_balances').upsert({
      'association_id': assoc,
      'account_name': o.account,
      'amount': o.amount,
      'as_of': _date(o.asOf),
      'entered_by': db.auth.currentUser!.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<int> raiseDues(String head, DateTime dueDate, Map<String, int> rates) async =>
      _int(await db.rpc('raise_dues', params: {'p_head': head, 'p_due_date': _date(dueDate), 'p_rates': rates}));

  static Future<String> recordPayment({
    required String flatId,
    String? dueId,
    required int amount,
    required String mode,
    String? reference,
    required DateTime paidOn,
  }) async {
    final row = await db
        .from('payments')
        .insert({
          'flat_id': flatId,
          'due_id': dueId,
          'amount': amount,
          'mode': mode,
          'reference': reference,
          'paid_on': _date(paidOn),
        })
        .select('receipt_no')
        .single();
    return row['receipt_no'] as String;
  }

  static Future<List<Expense>> expenses() async {
    final rows = await db
        .from('expenses')
        .select(
          'id, ref_no, spent_on, category, vendor, description, amount, status, bill_paths, entered_by_name, flagged, comment',
        )
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        Expense(
          id: r['ref_no'] as String,
          dbId: r['id'] as String,
          date: DateTime.parse(r['spent_on'] as String),
          category: r['category'] as String,
          vendor: r['vendor'] as String,
          description: r['description'] as String? ?? '',
          amount: _int(r['amount']),
          status: _status(r['status']),
          enteredBy: r['entered_by_name'] as String? ?? '',
          billPaths: List<String>.from(r['bill_paths'] as List? ?? const []),
          documents: (r['bill_paths'] as List? ?? const []).length,
          flagged: r['flagged'] as bool? ?? false,
          comment: r['comment'] as String?,
        ),
    ];
  }

  static Future<String> _upload(Uint8List bytes, String ext) async {
    final assoc = await db.rpc('my_association') as String;
    final path = '$assoc/${DateTime.now().microsecondsSinceEpoch}.${ext.toLowerCase()}';
    await db.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeFor(ext)));
    return path;
  }

  static Future<void> addExpense({
    required DateTime date,
    required String category,
    required String vendor,
    required String description,
    required int amount,
    Uint8List? bill,
    String? ext,
  }) async {
    final paths = [if (bill != null) await _upload(bill, ext ?? 'jpg')];
    await db.from('expenses').insert({
      'spent_on': _date(date),
      'category': category,
      'vendor': vendor,
      'description': description,
      'amount': amount,
      'bill_paths': paths,
    });
  }

  static Future<void> attachBill(String id, Uint8List bytes, String ext) async {
    final path = await _upload(bytes, ext);
    await db.rpc('add_expense_bill', params: {'p_id': id, 'p_path': path});
  }

  static Future<void> decide(String id, String action, String? comment) =>
      db.rpc('decide_expense', params: {'p_id': id, 'p_action': action, 'p_comment': comment});

  static Future<String> billUrl(String path) => db.storage.from(_bucket).createSignedUrl(path, 60);
}
