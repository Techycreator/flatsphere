import 'dart:typed_data';

import '../models/models.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';
import 'upload_preparation.dart';

typedef AttendanceData = ({List<StaffMember> staff, Map<String, StaffAttendance> records});

class AttendanceRepo {
  static Future<List<(String id, String number)>> myResidentialFlats() async {
    final userId = db.auth.currentUser!.id;
    final rows = await db
        .from('memberships')
        .select('flat_id, flats(number)')
        .eq('user_id', userId)
        .isFilter('ended_at', null)
        .inFilter('role', ['owner', 'resident']);
    final unique = <String, String>{};
    for (final row in rows) {
      if (row['flat_id'] case final String id) {
        unique[id] = ((row['flats'] as Map?)?['number'] as String?) ?? '';
      }
    }
    return [for (final e in unique.entries) (e.key, e.value)];
  }

  static Future<List<StaffAttendance>> history(String staffId, DateTime from, DateTime to) async {
    final rows = await db
        .from('staff_attendance')
        .select('staff_id, attendance_date, status, note, marked_by_name')
        .eq('staff_id', staffId)
        .gte('attendance_date', _date(from))
        .lte('attendance_date', _date(to))
        .order('attendance_date');
    return [
      for (final row in rows)
        StaffAttendance(
          staffId: row['staff_id'] as String,
          date: DateTime.parse(row['attendance_date'] as String),
          status: _attendanceStatus(row['status']),
          markedBy: row['marked_by_name'] as String? ?? '',
          note: row['note'] as String? ?? '',
        ),
    ];
  }

  static Future<AttendanceData> load(DateTime date, {bool includeInactive = false}) async {
    final day = _date(date);
    var staffQuery = db
        .from('staff_members')
        .select(
          'id, full_name, staff_type, area, active, '
          'staff_private_details(employer_type, agency_name, monthly_salary, id_proof_path)',
        );
    if (!includeInactive) staffQuery = staffQuery.eq('active', true);
    final staffRows = await staffQuery.order('full_name');
    final records = await db
        .from('staff_attendance')
        .select('staff_id, attendance_date, status, note, marked_by_name')
        .eq('attendance_date', day);
    return (
      staff: [
        for (final row in staffRows)
          () {
            final privateDetails = row['staff_private_details'] as Map? ?? const {};
            return StaffMember(
              id: row['id'] as String,
              name: row['full_name'] as String,
              type: _staffType(row['staff_type']),
              area: row['area'] as String,
              active: row['active'] as bool? ?? true,
              employerType: privateDetails['employer_type'] == 'agency'
                  ? StaffEmployerType.agency
                  : StaffEmployerType.association,
              agencyName: privateDetails['agency_name'] as String?,
              monthlySalary: (privateDetails['monthly_salary'] as num?)?.toInt(),
              idProofPath: privateDetails['id_proof_path'] as String?,
            );
          }(),
      ],
      records: {
        for (final row in records)
          row['staff_id'] as String: StaffAttendance(
            staffId: row['staff_id'] as String,
            date: DateTime.parse(row['attendance_date'] as String),
            status: _attendanceStatus(row['status']),
            markedBy: row['marked_by_name'] as String? ?? '',
            note: row['note'] as String? ?? '',
          ),
      },
    );
  }

  static Future<void> addStaff({
    required String name,
    required StaffType type,
    required String area,
    required StaffEmployerType employerType,
    required String agencyName,
    required int monthlySalary,
    required Uint8List proofBytes,
    required String proofExtension,
  }) async {
    final prepared = await prepareUpload(proofBytes, proofExtension);
    final association = await db.rpc('my_association') as String;
    final path = '$association/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from('staff-proofs')
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    try {
      await db.rpc(
        'add_staff_member',
        params: {
          'p_name': name.trim(),
          'p_type': _staffTypeDb(type),
          'p_area': area,
          'p_employer_type': employerType == StaffEmployerType.agency ? 'agency' : 'association',
          'p_agency_name': employerType == StaffEmployerType.agency ? agencyName.trim() : null,
          'p_monthly_salary': monthlySalary,
          'p_id_proof_path': path,
        },
      );
    } catch (_) {
      await db.storage.from('staff-proofs').remove([path]);
      rethrow;
    }
  }

  static Future<void> updateStaff({
    required String id,
    required String name,
    required StaffType type,
    required String area,
    required StaffEmployerType employerType,
    required String agencyName,
    required int monthlySalary,
    required bool active,
  }) => db.rpc(
    'update_staff_member',
    params: {
      'p_staff': id,
      'p_name': name.trim(),
      'p_type': _staffTypeDb(type),
      'p_area': area,
      'p_employer_type': employerType == StaffEmployerType.agency ? 'agency' : 'association',
      'p_agency_name': employerType == StaffEmployerType.agency ? agencyName.trim() : null,
      'p_monthly_salary': monthlySalary,
      'p_active': active,
    },
  );

  static Future<String> staffProofUrl(String path) => db.storage.from('staff-proofs').createSignedUrl(path, 60);

  static Future<String> housekeepingProofUrl(String path) =>
      db.storage.from('housekeeping-proofs').createSignedUrl(path, 60);

  static Future<List<FlatHousekeepingWorker>> flatHousekeeping() async {
    final rows = await db
        .from('flat_housekeeping_workers')
        .select('id, flats(number), full_name, id_proof_path, usual_in, usual_out, resides_in_flat, active')
        .eq('active', true)
        .order('full_name');
    return [
      for (final row in rows)
        FlatHousekeepingWorker(
          id: row['id'] as String,
          flatNumber: ((row['flats'] as Map?)?['number'] as String?) ?? '',
          name: row['full_name'] as String,
          idProofPath: row['id_proof_path'] as String,
          usualIn: row['usual_in'] as String,
          usualOut: row['usual_out'] as String,
          residesInFlat: row['resides_in_flat'] as bool? ?? false,
          active: row['active'] as bool? ?? true,
        ),
    ];
  }

  static Future<List<FlatHousekeepingWorker>> householdStaffOverview() async {
    final rows = await db.rpc('household_staff_overview') as List;
    return [
      for (final row in rows)
        FlatHousekeepingWorker(
          id: row['id'] as String,
          flatNumber: row['flat_number'] as String? ?? '',
          name: row['full_name'] as String,
          idProofPath: '',
          usualIn: row['usual_in'] as String,
          usualOut: row['usual_out'] as String,
          residesInFlat: row['resides_in_flat'] as bool? ?? false,
          active: true,
        ),
    ];
  }

  static Future<void> addFlatHousekeeping({
    required String flatId,
    required String name,
    required String usualIn,
    required String usualOut,
    required bool residesInFlat,
    required Uint8List proofBytes,
    required String proofExtension,
  }) async {
    final prepared = await prepareUpload(proofBytes, proofExtension);
    final association = await db.rpc('my_association') as String;
    final path = '$association/$flatId/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from('housekeeping-proofs')
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    try {
      await db.rpc(
        'add_flat_housekeeping_worker',
        params: {
          'p_flat_id': flatId,
          'p_name': name.trim(),
          'p_usual_in': usualIn,
          'p_usual_out': usualOut,
          'p_resides_in_flat': residesInFlat,
          'p_id_proof_path': path,
        },
      );
    } catch (_) {
      await db.storage.from('housekeeping-proofs').remove([path]);
      rethrow;
    }
  }

  static Future<void> mark({
    required String staffId,
    required DateTime date,
    required AttendanceStatus status,
    String note = '',
  }) async {
    await db.rpc(
      'mark_staff_attendance',
      params: {'p_staff': staffId, 'p_date': _date(date), 'p_status': _attendanceStatusDb(status), 'p_note': note},
    );
  }
}

StaffType _staffType(Object? value) => switch (value) {
  'stp_operator' => StaffType.stpOperator,
  'security' => StaffType.security,
  _ => StaffType.housekeeping,
};

String _staffTypeDb(StaffType value) => switch (value) {
  StaffType.housekeeping => 'housekeeping',
  StaffType.stpOperator => 'stp_operator',
  StaffType.security => 'security',
};

AttendanceStatus _attendanceStatus(Object? value) => switch (value) {
  'absent' => AttendanceStatus.absent,
  'leave' => AttendanceStatus.leave,
  _ => AttendanceStatus.present,
};

String _attendanceStatusDb(AttendanceStatus value) => switch (value) {
  AttendanceStatus.present => 'present',
  AttendanceStatus.absent => 'absent',
  AttendanceStatus.leave => 'leave',
};

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
