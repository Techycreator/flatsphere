import '../backend/pin_vault.dart';
import '../backend/compliance_repo.dart';

import 'package:flutter/gestures.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend.dart';
import '../backend/approvals_repo.dart';
import '../backend/complaints_repo.dart';
import '../backend/checklist_repo.dart';
import '../backend/finance_repo.dart';
import '../backend/birthday_repo.dart';
import '../backend/meetings_repo.dart';
import '../backend/notifications_repo.dart';
import '../models/models.dart';
import 'demo_data.dart';

final clockProvider = Provider<DateTime>((ref) => DateTime.now());

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  void set(Locale l) => state = l;
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

final firstAssociationSignupProvider = NotifierProvider<FirstAssociationSignupNotifier, String?>(
  FirstAssociationSignupNotifier.new,
);

class FirstAssociationSignupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setEmail(String email) => state = email.trim();

  void clear() => state = null;
}

final birthdayWishProvider = FutureProvider.autoDispose<bool>((ref) async {
  final member = ref.watch(sessionProvider.select((session) => (session?.user.id, session?.user.associationId)));
  if (!backendEnabled || member.$1 == null || member.$2 == null) return false;
  return BirthdayRepo.claimIfDue();
});

final appNotificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final member = ref.watch(sessionProvider.select((session) => (session?.user.id, session?.user.associationId)));
  if (!backendEnabled || member.$1 == null || member.$2 == null) return const [];
  return NotificationsRepo.load();
});

final annualBudgetsProvider = FutureProvider.autoDispose<List<AnnualBudget>>((ref) async {
  final member = ref.watch(sessionProvider.select((session) => (session?.user.id, session?.user.associationId)));
  if (!backendEnabled || member.$1 == null || member.$2 == null) return const [];
  return FinanceRepo.annualBudgets();
});

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  void login(DemoUser u) {
    state = Session(user: u, activeRole: u.roles.first);
    ref.read(firstAssociationSignupProvider.notifier).clear();
  }

  Future<void> switchAssociation(String associationId) async {
    if (!backendEnabled) return;
    final user = await AuthService.loadUser(associationId: associationId);
    if (user == null) throw StateError('No active membership in that association');
    state = Session(user: user, activeRole: user.roles.first);
  }

  void switchRole(Role r) => state = state?.copyWith(activeRole: r);

  /// Idle timeout: with PIN unlock on, lock instead of signing out.
  void lockOrLogout() {
    if (backendEnabled && PinVault.pinEnabled) {
      PinVault.lockNow();
      state = null;
    } else {
      logout();
    }
  }

  void logout() {
    if (backendEnabled) AuthService.signOut();
    state = null;
    ref.read(firstAssociationSignupProvider.notifier).clear();
  }
}

final complaintsProvider = NotifierProvider<ComplaintsNotifier, List<Complaint>>(ComplaintsNotifier.new);

class ComplaintsNotifier extends Notifier<List<Complaint>> {
  @override
  List<Complaint> build() {
    if (!backendEnabled) return buildDemoComplaints(ref.read(clockProvider));
    if (ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId))).$1 != null) refresh();
    return const [];
  }

  Future<void> refresh() async => state = await ComplaintsRepo.fetchAll();

  String nextId() {
    final maxN = state.map((c) => int.tryParse(c.id.split('-').last) ?? 0).fold(0, (a, b) => a > b ? a : b);
    return 'CMP-2026-${(maxN + 1).toString().padLeft(4, '0')}';
  }

  void add(Complaint c) {
    state = [c, ...state];
    if (backendEnabled) ComplaintsRepo.insert(c).catchError((_) => refresh());
  }

  void update(String id, Complaint Function(Complaint) f) {
    final before = state.where((c) => c.id == id).firstOrNull;
    if (before == null) return;
    final after = f(before);
    state = [for (final c in state) c.id == id ? after : c];
    if (backendEnabled) ComplaintsRepo.update(before, after).catchError((_) => refresh());
  }

  Future<void> setStatus(String id, TicketStatus status, String note) async {
    if (backendEnabled) {
      await ComplaintsRepo.setStatus(id, status, note);
      return refresh();
    }
    update(
      id,
      (complaint) => complaint.copyWith(
        status: status,
        remarks: [
          ...complaint.remarks,
          TicketRemark(
            by: ref.read(sessionProvider)?.user.name ?? 'Demo user',
            at: DateTime.now(),
            text: '[${status.label}] $note',
          ),
        ],
      ),
    );
  }
}

class ChecklistState {
  const ChecklistState({required this.items, this.submitted = false, this.approved = false, this.error});
  final List<ChecklistItem> items;
  final bool submitted;
  final bool approved;
  final String? error;

  int get doneCount => items.where((i) => i.done).length;
  double get progress => items.isEmpty ? 0 : doneCount / items.length;

  ChecklistState copyWith({
    List<ChecklistItem>? items,
    bool? submitted,
    bool? approved,
    String? error,
    bool clearError = false,
  }) => ChecklistState(
    items: items ?? this.items,
    submitted: submitted ?? this.submitted,
    approved: approved ?? this.approved,
    error: clearError ? null : (error ?? this.error),
  );
}

final checklistProvider = NotifierProvider<ChecklistNotifier, ChecklistState>(ChecklistNotifier.new);

class ChecklistNotifier extends Notifier<ChecklistState> {
  @override
  ChecklistState build() {
    if (backendEnabled) {
      final session = ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId)));
      if (session.$1 != null) _loadCloud();
      return const ChecklistState(items: []);
    }
    return ChecklistState(items: buildDemoChecklist());
  }

  Future<void> _loadCloud() async {
    try {
      final items = await ChecklistRepo.items();
      state = state.copyWith(items: items, clearError: true);
      await refreshProofs(DateUtils.dateOnly(DateTime.now()));
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  /// Secretary / President / JS maintain the caretaker's daily items.
  Future<void> addItem(ChecklistItem item) async {
    if (backendEnabled) {
      await ChecklistRepo.addItem(item, state.items.length);
      return _loadCloud();
    }
    state = state.copyWith(items: [...state.items, item]);
  }

  Future<void> removeItem(String id) async {
    if (backendEnabled) {
      await ChecklistRepo.removeItem(id);
      return _loadCloud();
    }
    state = state.copyWith(items: state.items.where((i) => i.id != id).toList());
  }

  Future<void> refreshProofs(DateTime date) async {
    if (!backendEnabled) return;
    try {
      final proofs = await ChecklistRepo.proofs(date);
      state = state.copyWith(
        items: [for (final item in state.items) item.copyWith(photoProofPaths: proofs[item.id] ?? const [])],
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> uploadPhotoProof(String itemId, DateTime date, Uint8List bytes) async {
    final role = ref.read(sessionProvider)?.activeRole;
    if (role != Role.caretaker || state.submitted || state.approved) {
      throw StateError('Only the caretaker can add proofs before submission');
    }
    final item = state.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null || !item.proofRequired) throw StateError('This checklist item does not require photo proof');
    final proofPath = backendEnabled
        ? await ChecklistRepo.uploadPhoto(itemId: itemId, date: date, source: bytes)
        : 'demo:${DateTime.now().microsecondsSinceEpoch}';
    state = state.copyWith(
      items: [
        for (final current in state.items)
          if (current.id == itemId)
            current.copyWith(photoProofPaths: [...current.photoProofPaths, proofPath])
          else
            current,
      ],
      clearError: true,
    );
  }

  Future<String?> proofUrl(String path) async => backendEnabled ? ChecklistRepo.viewUrl(path) : null;

  void _items(List<ChecklistItem> items) => state = state.copyWith(items: items);

  void toggle(String id, bool done) {
    if (state.approved) return;
    _items([for (final i in state.items) i.id == id ? i.copyWith(done: done, clearRejection: true) : i]);
  }

  void setNote(String id, String note, bool voice) =>
      _items([for (final i in state.items) i.id == id ? i.copyWith(note: note, hasVoiceNote: voice) : i]);

  void submit() => state = ChecklistState(items: state.items, submitted: true);

  void approveAll() => state = ChecklistState(items: state.items, submitted: true, approved: true);

  void reject(String id, String reason) => state = ChecklistState(
    items: [for (final i in state.items) i.id == id ? i.copyWith(rejectedReason: reason) : i],
    submitted: false,
  );
}

final approvalsProvider = NotifierProvider<ApprovalsNotifier, List<ApprovalRequest>>(ApprovalsNotifier.new);

class ApprovalsNotifier extends Notifier<List<ApprovalRequest>> {
  @override
  List<ApprovalRequest> build() {
    if (!backendEnabled) return buildDemoApprovals(ref.read(clockProvider));
    final user = ref.watch(sessionProvider.select((s) => s?.user));
    if (user != null) refresh(user);
    return const [];
  }

  Future<void> refresh([DemoUser? me]) async {
    final u = me ?? ref.read(sessionProvider)?.user;
    if (u != null) state = await ApprovalsRepo.fetchAll(u);
  }

  String nextId() {
    // Other users' requests may be invisible here, so cloud refs must not depend on local state.
    if (backendEnabled) return 'APR-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    final maxN = state.map((a) => int.tryParse(a.id.split('-').last) ?? 0).fold(0, (a, b) => a > b ? a : b);
    return 'APR-${(maxN + 1).toString().padLeft(3, '0')}';
  }

  Future<String?> add(ApprovalRequest a) async {
    if (backendEnabled) {
      final id = await ApprovalsRepo.insert(a);
      state = [a, ...state];
      ref.invalidate(appNotificationsProvider);
      return id;
    }
    state = [a, ...state];
    return null;
  }

  /// Records [d] on the current step if it belongs to [role]/[userName].
  Future<void> decide(String id, Role role, String userName, Decision d, String? comment) async {
    if (backendEnabled) {
      try {
        await ApprovalsRepo.decide(id, d, comment);
      } finally {
        await refresh();
        ref.invalidate(appNotificationsProvider);
      }
      return;
    }
    state = [
      for (final a in state)
        if (a.id == id && a.currentStep != null && a.currentStep!.matches(role, userName))
          a.copyWith(
            steps: [
              for (final s in a.steps)
                if (identical(s, a.currentStep))
                  s.copyWith(decision: d, comment: comment, decidedBy: '$userName (${role.label})')
                else
                  s,
            ],
          )
        else
          a,
    ];
  }

  void flag(String id) {
    state = [for (final a in state) a.id == id ? a.copyWith(flagged: !a.flagged) : a];
    if (backendEnabled) ApprovalsRepo.toggleFlag(id).catchError((_) => refresh());
  }
}

/// Reminder limits from spec Section 8.3: 1 per flat per day, 1 bulk run per day.
class DuesState {
  const DuesState({
    required this.lines,
    this.reminded = const {},
    this.bulkSentAt,
    this.payments = const [],
    this.flats = const [],
    this.opening,
    this.error,
  });
  final List<DueLine> lines;
  final Map<String, DateTime> reminded;
  final DateTime? bulkSentAt;
  final List<PaymentRecord> payments;

  /// Cloud mode only (demo screens use the demo flat list).
  final List<FlatInfo> flats;
  final OpeningBalance? opening;
  final String? error;

  int pendingFor(String flat) => lines.where((l) => l.flatNumber == flat).fold(0, (s, l) => s + l.pending);

  DuesState copyWith({
    List<DueLine>? lines,
    Map<String, DateTime>? reminded,
    DateTime? bulkSentAt,
    List<PaymentRecord>? payments,
    List<FlatInfo>? flats,
    OpeningBalance? opening,
    String? error,
  }) => DuesState(
    lines: lines ?? this.lines,
    reminded: reminded ?? this.reminded,
    bulkSentAt: bulkSentAt ?? this.bulkSentAt,
    payments: payments ?? this.payments,
    flats: flats ?? this.flats,
    opening: opening ?? this.opening,
    error: error,
  );
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

final duesProvider = NotifierProvider<DuesNotifier, DuesState>(DuesNotifier.new);

class DuesNotifier extends Notifier<DuesState> {
  @override
  DuesState build() {
    if (!backendEnabled) return DuesState(lines: buildDemoDues(ref.read(clockProvider)));
    if (ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId))).$1 != null) refresh();
    return const DuesState(lines: []);
  }

  Future<void> refresh() async {
    if (!backendEnabled) return;
    try {
      final d = await FinanceRepo.dues();
      state = state.copyWith(lines: d.lines, payments: d.payments, flats: d.flats, opening: d.opening);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  bool canRemind(String flat) {
    final t = state.reminded[flat];
    return t == null || !_sameDay(t, DateTime.now());
  }

  bool get canBulk => state.bulkSentAt == null || !_sameDay(state.bulkSentAt!, DateTime.now());

  /// Cloud: sends an in-app reminder to the flat's owners (server allows one per flat per day).
  Future<void> remind(String flat) async {
    if (backendEnabled) {
      final id = state.flats.where((f) => f.number == flat).firstOrNull?.id;
      if (id != null) await FinanceRepo.sendDuesReminders([id]);
    }
    state = state.copyWith(reminded: {...state.reminded, flat: DateTime.now()});
  }

  Future<int> remindAll() async {
    final flats = {
      for (final l in state.lines)
        if (!l.isPaid) l.flatNumber,
    }.where(canRemind).toList();
    final now = DateTime.now();
    state = state.copyWith(reminded: {...state.reminded, for (final f in flats) f: now}, bulkSentAt: now);
    if (backendEnabled) {
      final ids = [
        for (final f in state.flats)
          if (flats.contains(f.number)) f.id!,
      ];
      return FinanceRepo.sendDuesReminders(ids);
    }
    return flats.length;
  }

  /// Demo-only online payment.
  String pay(String flat) {
    final receipt = 'RCT-${1300 + DateTime.now().millisecond}';
    state = state.copyWith(
      lines: [for (final l in state.lines) l.flatNumber == flat && !l.isPaid ? l.markPaid(receipt) : l],
    );
    return receipt;
  }

  Future<void> saveOpening(OpeningBalance o) async {
    if (backendEnabled) {
      await FinanceRepo.saveOpening(o);
      return refresh();
    }
    state = state.copyWith(opening: o);
  }

  /// Adds [head] for every flat whose type has a rate; flats that already have it are skipped. Returns the count.
  Future<int> raiseDues(String head, DateTime dueDate, Map<String, int> rates) async {
    if (backendEnabled) {
      final n = await FinanceRepo.raiseDues(head, dueDate, rates);
      await refresh();
      return n;
    }
    final added = [
      for (final f in demoFlats)
        if ((rates[f.type] ?? 0) > 0 && !state.lines.any((l) => l.flatNumber == f.number && l.head == head))
          DueLine(flatNumber: f.number, head: head, amount: rates[f.type]!, paid: 0, dueDate: dueDate),
    ];
    state = state.copyWith(lines: [...state.lines, ...added]);
    return added.length;
  }

  Future<int> raiseDuesPerSqft(String head, DateTime dueDate, double ratePerSqft) async {
    if (backendEnabled) {
      final count = await FinanceRepo.raiseDuesPerSqft(head, dueDate, ratePerSqft);
      await refresh();
      return count;
    }
    final added = [
      for (final flat in demoFlats)
        if (flat.sqft > 0 && !state.lines.any((line) => line.flatNumber == flat.number && line.head == head))
          DueLine(
            flatNumber: flat.number,
            head: head,
            amount: (flat.sqft * ratePerSqft).round(),
            paid: 0,
            dueDate: dueDate,
          ),
    ];
    state = state.copyWith(lines: [...state.lines, ...added]);
    return added.length;
  }

  Future<int> applyFixedLateFee(String head, DateTime dueDate, int amount) async {
    if (backendEnabled) {
      final count = await FinanceRepo.applyFixedLateFee(head, dueDate, amount);
      await refresh();
      return count;
    }
    final overdue = {
      for (final line in state.lines)
        if (!line.isPaid && line.dueDate.isBefore(DateTime.now())) line.flatNumber,
    };
    final added = [
      for (final flat in overdue)
        if (!state.lines.any((line) => line.flatNumber == flat && line.head == head))
          DueLine(flatNumber: flat, head: head, amount: amount, paid: 0, dueDate: dueDate),
    ];
    state = state.copyWith(lines: [...state.lines, ...added]);
    return added.length;
  }

  /// Returns the receipt number.
  Future<String> recordPayment({
    required String flatNumber,
    DueLine? due,
    required int amount,
    required String mode,
    String? reference,
    required DateTime paidOn,
  }) async {
    if (backendEnabled) {
      final flatId = due?.flatId ?? state.flats.firstWhere((f) => f.number == flatNumber).id!;
      final r = await FinanceRepo.recordPayment(
        flatId: flatId,
        dueId: due?.id,
        amount: amount,
        mode: mode,
        reference: reference,
        paidOn: paidOn,
      );
      FinanceRepo.emailReceipt(r).ignore();
      await refresh();
      return r;
    }
    final receipt = 'RCT-${5001 + state.payments.length}';
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          identical(l, due)
              ? DueLine(
                  flatNumber: l.flatNumber,
                  head: l.head,
                  amount: l.amount,
                  paid: l.paid + amount,
                  dueDate: l.dueDate,
                  receiptNo: receipt,
                )
              : l,
      ],
      payments: [
        ...state.payments,
        PaymentRecord(
          flatNumber: flatNumber,
          amount: amount,
          paidOn: paidOn,
          receiptNo: receipt,
          mode: mode,
          reference: reference,
          head: due?.head,
        ),
      ],
    );
    return receipt;
  }
}

/// Opening balance + payments received − approved expenses since the opening date; null until it is set.
final bankBalanceProvider = Provider<int?>((ref) {
  if (!backendEnabled) return 485320;
  final d = ref.watch(duesProvider);
  final o = d.opening;
  if (o == null) return null;
  final inflow = d.payments.where((p) => !p.paidOn.isBefore(o.asOf)).fold(0, (s, p) => s + p.amount);
  final outflow = ref
      .watch(expensesProvider)
      .where((e) => e.status == ExpenseStatus.approved && !e.date.isBefore(o.asOf))
      .fold(0, (s, e) => s + e.amount);
  return o.amount + inflow - outflow;
});

class IncomeState {
  const IncomeState({this.categories = const [], this.entries = const [], this.loading = false, this.error});

  final List<IncomeCategory> categories;
  final List<IncomeEntry> entries;
  final bool loading;
  final String? error;

  IncomeState copyWith({List<IncomeCategory>? categories, List<IncomeEntry>? entries, bool? loading, String? error}) =>
      IncomeState(
        categories: categories ?? this.categories,
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        error: error,
      );
}

final incomeProvider = NotifierProvider<IncomeNotifier, IncomeState>(IncomeNotifier.new);

class IncomeNotifier extends Notifier<IncomeState> {
  @override
  IncomeState build() {
    if (!backendEnabled) {
      return IncomeState(
        categories: const [
          IncomeCategory(
            id: 'demo-advertisement',
            name: 'Advertisement',
            status: IncomeCategoryStatus.active,
            requestRef: 'DEMO',
          ),
          IncomeCategory(
            id: 'demo-sponsorship',
            name: 'Sponsorship',
            status: IncomeCategoryStatus.active,
            requestRef: 'DEMO',
          ),
          IncomeCategory(
            id: 'demo-rental',
            name: 'Hall rental',
            status: IncomeCategoryStatus.active,
            requestRef: 'DEMO',
          ),
        ],
      );
    }
    final user = ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId)));
    if (user.$1 != null) refresh();
    return IncomeState(loading: user.$1 != null);
  }

  Future<void> refresh() async {
    if (!backendEnabled) return;
    try {
      final data = await FinanceRepo.income();
      state = IncomeState(categories: data.categories, entries: data.entries);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<String> requestCategory(String name) async {
    final requestRef = ref.read(approvalsProvider.notifier).nextId();
    if (backendEnabled) {
      final createdRef = await FinanceRepo.requestIncomeCategory(name, requestRef);
      await refresh();
      await ref.read(approvalsProvider.notifier).refresh();
      return createdRef;
    }
    state = state.copyWith(
      categories: [
        IncomeCategory(
          id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
          name: name.trim(),
          status: IncomeCategoryStatus.pending,
          requestRef: requestRef,
        ),
        ...state.categories,
      ],
    );
    return requestRef;
  }

  Future<void> record({
    required String categoryId,
    required DateTime receivedOn,
    required int amount,
    required String source,
    required String description,
  }) async {
    if (backendEnabled) {
      await FinanceRepo.recordIncome(
        categoryId: categoryId,
        receivedOn: receivedOn,
        amount: amount,
        source: source,
        description: description,
      );
      return refresh();
    }
    final category = state.categories.firstWhere((c) => c.id == categoryId && c.status == IncomeCategoryStatus.active);
    state = state.copyWith(
      entries: [
        IncomeEntry(
          id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
          categoryId: category.id,
          categoryName: category.name,
          receivedOn: receivedOn,
          amount: amount,
          source: source.trim().isEmpty ? null : source.trim(),
          description: description.trim(),
          recordedBy: ref.read(sessionProvider)?.user.name ?? 'Demo user',
        ),
        ...state.entries,
      ],
    );
  }
}

final expensesProvider = NotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

class ExpensesNotifier extends Notifier<List<Expense>> {
  @override
  List<Expense> build() {
    if (!backendEnabled) return buildDemoExpenses(ref.read(clockProvider));
    if (ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId))).$1 != null) refresh();
    return const [];
  }

  Future<void> refresh() async {
    if (!backendEnabled) return;
    try {
      state = await FinanceRepo.expenses();
    } catch (_) {
      // Roles without finance access simply see no expenses.
    }
  }

  void update(String id, Expense Function(Expense) f) => state = [for (final e in state) e.id == id ? f(e) : e];

  Future<void> add({
    required DateTime date,
    required String category,
    required String vendor,
    required String description,
    required int amount,
    required String enteredBy,
    Uint8List? bill,
    String? ext,
    String? eventId,
  }) async {
    if (backendEnabled) {
      await FinanceRepo.addExpense(
        date: date,
        category: category,
        vendor: vendor,
        description: description,
        amount: amount,
        bill: bill,
        ext: ext,
        eventId: eventId,
      );
      return refresh();
    }
    state = [
      Expense(
        id: 'EXP-${1001 + state.length}',
        date: date,
        category: category,
        vendor: vendor,
        description: description,
        amount: amount,
        status: ExpenseStatus.awaitingTreasurer,
        enteredBy: enteredBy,
        documents: bill == null ? 0 : 1,
        eventId: eventId,
      ),
      ...state,
    ];
  }

  /// Actions: verify, approve, send_back, resubmit, flag. The server enforces who may do what.
  Future<void> decide(Expense e, String action, [String? comment]) async {
    if (backendEnabled) {
      await FinanceRepo.decide(e.dbId!, action, comment);
      return refresh();
    }
    update(
      e.id,
      (x) => switch (action) {
        'verify' => x.copyWith(status: ExpenseStatus.awaitingPresident),
        'approve' => x.copyWith(status: ExpenseStatus.approved),
        'send_back' => x.copyWith(status: ExpenseStatus.sentBack, comment: comment),
        'resubmit' => x.copyWith(status: ExpenseStatus.awaitingTreasurer),
        'flag' => x.copyWith(flagged: !x.flagged),
        _ => x,
      },
    );
  }

  Future<void> attachBill(Expense e, Uint8List bytes, String ext) async {
    if (backendEnabled) {
      await FinanceRepo.attachBill(e.dbId!, bytes, ext);
      return refresh();
    }
    update(e.id, (x) => x.copyWith(documents: x.documents + 1));
  }

  /// A 60-second link; null in demo mode (files are not stored).
  Future<String?> billUrl(String path) async => backendEnabled ? FinanceRepo.billUrl(path) : null;
}

final meetingsProvider = NotifierProvider<MeetingsNotifier, List<Meeting>>(MeetingsNotifier.new);

class MeetingsNotifier extends Notifier<List<Meeting>> {
  @override
  List<Meeting> build() {
    if (!backendEnabled) return buildDemoMeetings(ref.read(clockProvider));
    if (ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId))).$1 != null) refresh();
    return const [];
  }

  Future<void> refresh() async {
    if (backendEnabled) state = await MeetingsRepo.load();
  }

  Future<void> rsvp(String id, Rsvp r) async {
    if (backendEnabled) {
      await MeetingsRepo.rsvp(id, r);
      return refresh();
    }
    state = [for (final m in state) m.id == id ? m.withRsvp(r) : m];
  }

  Future<void> add(Meeting m) async {
    if (backendEnabled) {
      await MeetingsRepo.create(m);
      await refresh();
      ref.invalidate(appNotificationsProvider);
      return;
    }
    state = [...state, m]..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<void> setLink(String id, String? link) async {
    if (backendEnabled) {
      await MeetingsRepo.setLink(id, link);
      return refresh();
    }
    state = [for (final meeting in state) meeting.id == id ? meeting.copyWith(link: link) : meeting];
  }

  Future<void> saveMinutes(String id, String text) async {
    if (backendEnabled) {
      await MeetingsRepo.saveMinutes(id, text);
      return refresh();
    }
    state = [
      for (final meeting in state)
        meeting.id == id ? meeting.copyWith(minutesStatus: 'draft', minutesText: text) : meeting,
    ];
  }

  Future<void> submitMinutes(String id) async {
    if (backendEnabled) {
      await MeetingsRepo.submitMinutes(id);
      return refresh();
    }
    state = [
      for (final meeting in state) meeting.id == id ? meeting.copyWith(minutesStatus: 'pending_approval') : meeting,
    ];
  }

  Future<void> approveMinutes(String id) async {
    if (backendEnabled) {
      await MeetingsRepo.approveMinutes(id);
      return refresh();
    }
    state = [for (final meeting in state) meeting.id == id ? meeting.copyWith(minutesStatus: 'approved') : meeting];
  }

  Future<void> reschedule(String id, DateTime at) async {
    if (backendEnabled) {
      await MeetingsRepo.reschedule(id, at);
      return refresh();
    }
    state = [for (final meeting in state) meeting.id == id ? meeting.copyWith(at: at) : meeting]
      ..sort((a, b) => a.at.compareTo(b.at));
  }
}

final noticesProvider = Provider<List<Notice>>((ref) => buildDemoNotices(ref.read(clockProvider)));

final privacyAcceptedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final userId = ref.watch(sessionProvider.select((s) => s?.user.id));
  if (!backendEnabled || userId == null) return true;
  return ComplianceRepo.privacyAccepted();
});

/// Committee roles are logged out after 30 minutes without any tap or click.
final idleLogoutProvider = Provider.autoDispose<void>((ref) {
  final role = ref.watch(sessionProvider.select((s) => s?.activeRole));
  if (!backendEnabled || role == null || !(role.isCommittee || role == Role.admin)) return;
  Timer? timer;
  void reset([PointerEvent? _]) {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 30), () => ref.read(sessionProvider.notifier).lockOrLogout());
  }

  reset();
  GestureBinding.instance.pointerRouter.addGlobalRoute(reset);
  ref.onDispose(() {
    timer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(reset);
  });
});
