import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'directory_repo.dart' show mimeFor;
import 'upload_preparation.dart';

String _date(DateTime d) => d.toIso8601String().substring(0, 10);

int _int(Object? v) => (v as num).toInt();

ExpenseStatus _status(Object? s) => switch (s) {
  'awaiting_president' => ExpenseStatus.awaitingPresident,
  'approved' => ExpenseStatus.approved,
  'sent_back' => ExpenseStatus.sentBack,
  _ => ExpenseStatus.awaitingTreasurer,
};

typedef DuesData = ({List<DueLine> lines, List<PaymentRecord> payments, List<FlatInfo> flats, OpeningBalance? opening});
typedef IncomeData = ({List<IncomeCategory> categories, List<IncomeEntry> entries});

/// Dues, payments, opening balance and expenses. Row-level security limits what each role reads;
/// expense decisions go through `decide_expense`, which enforces maker-checker.
class FinanceRepo {
  static const _bucket = 'bills';

  static Future<IncomeData> income() async {
    final categoryRows = await db
        .from('income_categories')
        .select('id, name, status, request_ref')
        .order('created_at', ascending: false);
    final entryRows = await db
        .from('income_entries')
        .select('id, category_id, received_on, amount, source, description, recorded_by_name, income_categories(name)')
        .order('received_on', ascending: false)
        .order('created_at', ascending: false);
    return (
      categories: [
        for (final row in categoryRows)
          IncomeCategory(
            id: row['id'] as String,
            name: row['name'] as String,
            status: switch (row['status']) {
              'active' => IncomeCategoryStatus.active,
              'rejected' => IncomeCategoryStatus.rejected,
              'sent_back' => IncomeCategoryStatus.sentBack,
              _ => IncomeCategoryStatus.pending,
            },
            requestRef: row['request_ref'] as String,
          ),
      ],
      entries: [
        for (final row in entryRows)
          IncomeEntry(
            id: row['id'] as String,
            categoryId: row['category_id'] as String,
            categoryName: (row['income_categories'] as Map?)?['name'] as String? ?? 'Income',
            receivedOn: DateTime.parse(row['received_on'] as String),
            amount: _int(row['amount']),
            recordedBy: row['recorded_by_name'] as String? ?? '',
            source: row['source'] as String?,
            description: row['description'] as String? ?? '',
          ),
      ],
    );
  }

  static Future<String> requestIncomeCategory(String name, String requestRef) async =>
      await db.rpc('request_income_category', params: {'p_name': name, 'p_ref': requestRef}) as String;

  static Future<void> recordIncome({
    required String categoryId,
    required DateTime receivedOn,
    required int amount,
    required String source,
    required String description,
  }) => db.rpc(
    'record_income',
    params: {
      'p_category': categoryId,
      'p_received_on': _date(receivedOn),
      'p_amount': amount,
      'p_source': source,
      'p_description': description,
    },
  );

  static Future<List<FundRequestRecord>> fundRequests() async {
    final rows = await db
        .from('fund_requests')
        .select('id,title,request_type,amount,basis,due_day,mom_ref,status')
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        FundRequestRecord(
          id: row['id'] as String,
          title: row['title'] as String,
          type: row['request_type'] as String,
          amount: (row['amount'] as num?)?.toInt(),
          basis: row['basis'] as String? ?? '',
          dueDay: row['due_day'] as String?,
          momRef: row['mom_ref'] as String,
          status: row['status'] as String,
        ),
    ];
  }

  static Future<void> requestFund({
    required String title,
    required String type,
    required int? amount,
    required String basis,
    required String dueDay,
    required String momRef,
    required String requestRef,
  }) => db.rpc(
    'request_fund',
    params: {
      'p_title': title,
      'p_type': type,
      'p_amount': amount,
      'p_basis': basis,
      'p_due_day': dueDay,
      'p_mom_ref': momRef,
      'p_ref': requestRef,
    },
  );

  static Future<DuesData> dues() async {
    // Scope to the active association: a person can belong to several, and RLS alone would mix their dues.
    final assoc = await db.rpc('my_association') as String;
    final flatRows = await db
        .from('flats')
        .select('id, number, block, flat_type')
        .eq('association_id', assoc)
        .order('number');
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
    final dueRows = await db
        .from('dues')
        .select('id, flat_id, head, amount, due_date')
        .eq('association_id', assoc)
        .order('due_date');
    final payRows = await db
        .from('payments')
        .select('flat_id, due_id, amount, paid_on, mode, reference, receipt_no')
        .eq('association_id', assoc)
        .order('paid_on')
        .order('created_at');
    final ob = await db
        .from('opening_balances')
        .select('account_name, amount, as_of')
        .eq('association_id', assoc)
        .maybeSingle();
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

  static Future<int> raiseDuesPerSqft(String head, DateTime dueDate, double ratePerSqft) async => _int(
    await db.rpc(
      'raise_dues_per_sqft',
      params: {'p_head': head, 'p_due_date': _date(dueDate), 'p_rate_per_sqft': ratePerSqft},
    ),
  );

  static Future<int> applyFixedLateFee(String head, DateTime dueDate, int amount) async => _int(
    await db.rpc('apply_fixed_late_fee', params: {'p_head': head, 'p_due_date': _date(dueDate), 'p_amount': amount}),
  );

  static Future<List<MonthlyStatement>> statements() async {
    final rows = await db.rpc('list_monthly_statements') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        MonthlyStatement(
          id: row['id'] as String,
          periodStart: DateTime.parse(row['period_start'] as String),
          periodEnd: DateTime.parse(row['period_end'] as String),
          status: row['status'] as String,
          snapshot: Map<String, dynamic>.from(row['snapshot'] as Map? ?? const {}),
          createdBy: row['created_by'] as String,
          treasurerApprovedBy: row['treasurer_approved_by'] as String?,
          secretaryApprovedBy: row['secretary_approved_by'] as String?,
          presidentApprovedBy: row['president_approved_by'] as String?,
          rejectionNote: row['rejection_note'] as String?,
        ),
    ];
  }

  static Future<void> createMonthlyStatement(DateTime month) =>
      db.rpc('create_monthly_statement', params: {'p_period_start': _date(month)});

  static Future<void> decideMonthlyStatement(String id, String action, [String? note]) =>
      db.rpc('decide_monthly_statement', params: {'p_statement': id, 'p_action': action, 'p_note': note});

  static Future<List<AnnualBudget>> annualBudgets() async {
    final rows = await db.rpc('list_annual_budgets') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        AnnualBudget(
          id: row['id'] as String,
          fiscalYearStart: DateTime.parse(row['fiscal_year_start'] as String),
          fiscalYearEnd: DateTime.parse(row['fiscal_year_end'] as String),
          categoryAmounts: {
            for (final entry in Map<String, dynamic>.from(row['category_amounts'] as Map? ?? const {}).entries)
              entry.key: (entry.value as num).toInt(),
          },
          resolutionRef: row['gbm_resolution_ref'] as String,
          resolutionDate: DateTime.parse(row['gbm_resolution_date'] as String),
          status: row['status'] as String,
          createdBy: row['created_by'] as String,
          secretaryApprovedBy: row['secretary_approved_by'] as String?,
          presidentApprovedBy: row['president_approved_by'] as String?,
          rejectionNote: row['rejection_note'] as String?,
        ),
    ];
  }

  static Future<void> submitAnnualBudget({
    required DateTime fiscalYearStart,
    required DateTime fiscalYearEnd,
    required Map<String, int> categoryAmounts,
    required String resolutionRef,
    required DateTime resolutionDate,
  }) => db.rpc(
    'submit_annual_budget',
    params: {
      'p_fiscal_year_start': _date(fiscalYearStart),
      'p_fiscal_year_end': _date(fiscalYearEnd),
      'p_category_amounts': categoryAmounts,
      'p_gbm_resolution_ref': resolutionRef,
      'p_gbm_resolution_date': _date(resolutionDate),
    },
  );

  static Future<void> decideAnnualBudget(String id, String action, [String? note]) =>
      db.rpc('decide_annual_budget', params: {'p_budget': id, 'p_action': action, 'p_note': note});

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
          'id, ref_no, spent_on, category, vendor, description, amount, status, bill_paths, entered_by_name, flagged, flag_reason, flag_resolution, comment, event_id, paid_from',
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
          flagReason: r['flag_reason'] as String?,
          flagResolution: r['flag_resolution'] as String?,
          eventId: r['event_id'] as String?,
          paidFrom: r['paid_from'] as String? ?? 'association',
        ),
    ];
  }

  static Future<Map<String, dynamic>?> duesSchedule() async => await db.from('dues_schedules').select().maybeSingle();

  static Future<void> saveDuesSchedule({
    required bool enabled,
    required String mode,
    required Map<String, int> rates,
    double? ratePerSqft,
    required String headPrefix,
    required int billDay,
    required int dueDay,
    required bool lateFeeEnabled,
    int? lateFeeAmount,
    required int graceDays,
  }) => db.rpc(
    'save_dues_schedule',
    params: {
      'p_enabled': enabled,
      'p_mode': mode,
      'p_rates': rates,
      'p_rate_per_sqft': ratePerSqft,
      'p_head_prefix': headPrefix,
      'p_bill_day': billDay,
      'p_due_day': dueDay,
      'p_late_fee_enabled': lateFeeEnabled,
      'p_late_fee_amount': lateFeeAmount,
      'p_late_fee_grace_days': graceDays,
    },
  );

  static Future<int?> pettyCashBalance() async => (await db.rpc('petty_cash_balance') as num?)?.toInt();

  static Future<void> addPettyCash(int amount, DateTime givenOn, String note) =>
      db.from('petty_cash_topups').insert({'amount': amount, 'given_on': _date(givenOn), 'note': note});

  static Future<String> _upload(Uint8List bytes, String ext) async {
    final prepared = await prepareUpload(bytes, ext);
    final assoc = await db.rpc('my_association') as String;
    final path = '$assoc/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from(_bucket)
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
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
    String? eventId,
    String paidFrom = 'association',
  }) async {
    final paths = [if (bill != null) await _upload(bill, ext ?? 'jpg')];
    await db.from('expenses').insert({
      'spent_on': _date(date),
      'category': category,
      'vendor': vendor,
      'description': description,
      'amount': amount,
      'bill_paths': paths,
      'event_id': eventId,
      'paid_from': paidFrom,
    });
  }

  static Future<void> attachBill(String id, Uint8List bytes, String ext) async {
    final path = await _upload(bytes, ext);
    await db.rpc('add_expense_bill', params: {'p_id': id, 'p_path': path});
  }

  static Future<void> decide(String id, String action, String? comment) =>
      db.rpc('decide_expense', params: {'p_id': id, 'p_action': action, 'p_comment': comment});

  /// Agenda lines for open flagged expenses (Admin, President, Secretary only).
  static Future<List<String>> flaggedAgenda() async =>
      List<String>.from(await db.rpc('flagged_expense_agenda') as List? ?? const []);

  static Future<String> billUrl(String path) => db.storage.from(_bucket).createSignedUrl(path, 60);

  /// Returns how many flats were reminded (flats already reminded today or with nothing pending are skipped).
  static Future<int> sendDuesReminders(List<String> flatIds) async =>
      ((await db.rpc('send_dues_reminders', params: {'p_flats': flatIds})) as num).toInt();

  /// Active reminders for the signed-in owner's flats; they stay until the dues are paid.
  static Future<List<({String flat, int pending, int count, DateTime lastSent})>> myDueReminders() async {
    final rows = await db.rpc('my_due_reminders') as List;
    return [
      for (final r in rows)
        (
          flat: r['flat_number'] as String,
          pending: (r['pending'] as num).toInt(),
          count: (r['reminder_count'] as num).toInt(),
          lastSent: DateTime.parse(r['last_sent_on'] as String),
        ),
    ];
  }

  /// Emails the receipt to the flat's owners from noreply.flatsphere@gmail.com (Edge Function).
  static Future<void> emailReceipt(String receiptNo) =>
      db.functions.invoke('send-receipt-email', body: {'receipt_no': receiptNo});
}
