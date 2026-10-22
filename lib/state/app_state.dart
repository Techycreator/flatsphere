import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend.dart';
import '../backend/approvals_repo.dart';
import '../backend/complaints_repo.dart';
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

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  void login(DemoUser u) => state = Session(user: u, activeRole: u.roles.first);
  void switchRole(Role r) => state = state?.copyWith(activeRole: r);
  void logout() {
    if (backendEnabled) AuthService.signOut();
    state = null;
  }
}

final complaintsProvider = NotifierProvider<ComplaintsNotifier, List<Complaint>>(ComplaintsNotifier.new);

class ComplaintsNotifier extends Notifier<List<Complaint>> {
  @override
  List<Complaint> build() {
    if (!backendEnabled) return buildDemoComplaints(ref.read(clockProvider));
    if (ref.watch(sessionProvider.select((s) => s?.user.id)) != null) refresh();
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
}

class ChecklistState {
  const ChecklistState({required this.items, this.submitted = false, this.approved = false});
  final List<ChecklistItem> items;
  final bool submitted;
  final bool approved;

  int get doneCount => items.where((i) => i.done).length;
  double get progress => items.isEmpty ? 0 : doneCount / items.length;
}

final checklistProvider = NotifierProvider<ChecklistNotifier, ChecklistState>(ChecklistNotifier.new);

class ChecklistNotifier extends Notifier<ChecklistState> {
  @override
  ChecklistState build() => ChecklistState(items: buildDemoChecklist());

  void _items(List<ChecklistItem> items) =>
      state = ChecklistState(items: items, submitted: state.submitted, approved: state.approved);

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

  void add(ApprovalRequest a) {
    state = [a, ...state];
    if (backendEnabled) ApprovalsRepo.insert(a).catchError((_) => refresh());
  }

  /// Records [d] on the current step if it belongs to [role]/[userName].
  Future<void> decide(String id, Role role, String userName, Decision d, String? comment) async {
    if (backendEnabled) {
      try {
        await ApprovalsRepo.decide(id, d, comment);
      } finally {
        await refresh();
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
  const DuesState({required this.lines, this.reminded = const {}, this.bulkSentAt});
  final List<DueLine> lines;
  final Map<String, DateTime> reminded;
  final DateTime? bulkSentAt;

  int pendingFor(String flat) => lines.where((l) => l.flatNumber == flat).fold(0, (s, l) => s + l.pending);
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

final duesProvider = NotifierProvider<DuesNotifier, DuesState>(DuesNotifier.new);

class DuesNotifier extends Notifier<DuesState> {
  @override
  DuesState build() => DuesState(lines: buildDemoDues(ref.read(clockProvider)));

  bool canRemind(String flat) {
    final t = state.reminded[flat];
    return t == null || !_sameDay(t, DateTime.now());
  }

  bool get canBulk => state.bulkSentAt == null || !_sameDay(state.bulkSentAt!, DateTime.now());

  void remind(String flat) => state = DuesState(
    lines: state.lines,
    reminded: {...state.reminded, flat: DateTime.now()},
    bulkSentAt: state.bulkSentAt,
  );

  int remindAll() {
    final flats = {
      for (final l in state.lines)
        if (!l.isPaid) l.flatNumber,
    }.where(canRemind).toList();
    final now = DateTime.now();
    state = DuesState(
      lines: state.lines,
      reminded: {...state.reminded, for (final f in flats) f: now},
      bulkSentAt: now,
    );
    return flats.length;
  }

  String pay(String flat) {
    final receipt = 'RCT-${1300 + DateTime.now().millisecond}';
    state = DuesState(
      lines: [for (final l in state.lines) l.flatNumber == flat && !l.isPaid ? l.markPaid(receipt) : l],
      reminded: state.reminded,
      bulkSentAt: state.bulkSentAt,
    );
    return receipt;
  }
}

final expensesProvider = NotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

class ExpensesNotifier extends Notifier<List<Expense>> {
  @override
  List<Expense> build() => buildDemoExpenses(ref.read(clockProvider));

  void update(String id, Expense Function(Expense) f) => state = [for (final e in state) e.id == id ? f(e) : e];
}

final meetingsProvider = NotifierProvider<MeetingsNotifier, List<Meeting>>(MeetingsNotifier.new);

class MeetingsNotifier extends Notifier<List<Meeting>> {
  @override
  List<Meeting> build() => buildDemoMeetings(ref.read(clockProvider));

  void rsvp(String id, Rsvp r) => state = [for (final m in state) m.id == id ? m.withRsvp(r) : m];
  void add(Meeting m) => state = [...state, m]..sort((a, b) => a.at.compareTo(b.at));
}

final noticesProvider = Provider<List<Notice>>((ref) => buildDemoNotices(ref.read(clockProvider)));
