import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/attendance_repo.dart';
import '../backend/backend.dart';
import '../models/models.dart';
import 'app_state.dart';

class StaffAttendanceState {
  const StaffAttendanceState({
    required this.date,
    this.staff = const [],
    this.records = const {},
    this.loading = false,
    this.error,
  });

  final DateTime date;
  final List<StaffMember> staff;
  final Map<String, StaffAttendance> records;
  final bool loading;
  final String? error;

  StaffAttendanceState copyWith({
    DateTime? date,
    List<StaffMember>? staff,
    Map<String, StaffAttendance>? records,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => StaffAttendanceState(
    date: date ?? this.date,
    staff: staff ?? this.staff,
    records: records ?? this.records,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

final staffAttendanceProvider = NotifierProvider<StaffAttendanceNotifier, StaffAttendanceState>(
  StaffAttendanceNotifier.new,
);

class StaffAttendanceNotifier extends Notifier<StaffAttendanceState> {
  int _requestSequence = 0;

  @override
  StaffAttendanceState build() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (!backendEnabled) {
      return StaffAttendanceState(
        date: today,
        staff: const [
          StaffMember(id: 'demo-hk-1', name: 'Meera Nair', type: StaffType.housekeeping, area: 'Cleaning'),
          StaffMember(id: 'demo-hk-2', name: 'Raju Das', type: StaffType.housekeeping, area: 'Cleaning'),
          StaffMember(id: 'demo-stp-1', name: 'Biju Thomas', type: StaffType.stpOperator, area: 'STP'),
          StaffMember(id: 'demo-sec-1', name: 'Suresh Kumar', type: StaffType.security, area: 'Security'),
        ],
      );
    }
    final session = ref.watch(sessionProvider.select((s) => (s?.user.id, s?.user.associationId, s?.activeRole)));
    if (session.$1 != null) {
      final includeInactive = session.$3 == Role.president || session.$3 == Role.secretary;
      unawaited(Future<void>.delayed(Duration.zero, () => refresh(today, includeInactive: includeInactive)));
    }
    return StaffAttendanceState(date: today);
  }

  Future<void> refresh(DateTime date, {bool? includeInactive}) async {
    final day = DateUtils.dateOnly(date);
    final role = ref.read(sessionProvider)?.activeRole;
    final showInactive = includeInactive ?? (role == Role.president || role == Role.secretary);
    final request = ++_requestSequence;
    if (!backendEnabled) {
      state = state.copyWith(date: day, loading: false, clearError: true);
      return;
    }
    state = state.copyWith(date: day, loading: true, clearError: true);
    try {
      final data = await AttendanceRepo.load(day, includeInactive: showInactive).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Attendance could not be loaded within 15 seconds'),
      );
      if (request == _requestSequence) {
        state = state.copyWith(date: day, staff: data.staff, records: data.records, clearError: true);
      }
    } catch (error) {
      if (request == _requestSequence) state = state.copyWith(error: '$error');
    } finally {
      if (request == _requestSequence) state = state.copyWith(loading: false);
    }
  }

  Future<void> addStaff({
    required String name,
    required StaffType type,
    required String area,
    required StaffEmployerType employerType,
    required String agencyName,
    required int monthlySalary,
    required Uint8List proofBytes,
    required String proofExtension,
  }) async {
    if (backendEnabled) {
      await AttendanceRepo.addStaff(
        name: name,
        type: type,
        area: area,
        employerType: employerType,
        agencyName: agencyName,
        monthlySalary: monthlySalary,
        proofBytes: proofBytes,
        proofExtension: proofExtension,
      );
      return refresh(state.date, includeInactive: true);
    }
    state = state.copyWith(
      staff: [
        StaffMember(
          id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
          name: name.trim(),
          type: type,
          area: area,
          employerType: employerType,
          agencyName: employerType == StaffEmployerType.agency ? agencyName.trim() : null,
          monthlySalary: monthlySalary,
          idProofPath: 'demo:${DateTime.now().microsecondsSinceEpoch}',
        ),
        ...state.staff,
      ],
    );
  }

  Future<void> mark(StaffMember staff, AttendanceStatus status, {String note = ''}) async {
    if (state.date != DateUtils.dateOnly(DateTime.now())) {
      throw StateError('Attendance can only be marked for today');
    }
    if (backendEnabled) {
      await AttendanceRepo.mark(staffId: staff.id, date: state.date, status: status, note: note);
    }
    state = state.copyWith(
      records: {
        ...state.records,
        staff.id: StaffAttendance(
          staffId: staff.id,
          date: state.date,
          status: status,
          markedBy: ref.read(sessionProvider)?.user.name ?? 'Caretaker',
          note: note,
        ),
      },
    );
  }

  Future<void> updateStaff({
    required StaffMember staff,
    required String name,
    required StaffType type,
    required String area,
    required StaffEmployerType employerType,
    required String agencyName,
    required int monthlySalary,
    required bool active,
  }) async {
    if (backendEnabled) {
      await AttendanceRepo.updateStaff(
        id: staff.id,
        name: name,
        type: type,
        area: area,
        employerType: employerType,
        agencyName: agencyName,
        monthlySalary: monthlySalary,
        active: active,
      );
      return refresh(state.date);
    }
    state = state.copyWith(
      staff: [
        for (final current in state.staff)
          if (current.id == staff.id)
            StaffMember(
              id: current.id,
              name: name.trim(),
              type: type,
              area: area,
              active: active,
              employerType: employerType,
              agencyName: employerType == StaffEmployerType.agency ? agencyName.trim() : null,
              monthlySalary: monthlySalary,
              idProofPath: current.idProofPath,
            )
          else
            current,
      ],
    );
  }
}
