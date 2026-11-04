import '../models/models.dart';
import 'backend.dart';

class VisitorRepo {
  static Future<List<(String id, String number)>> myFlats({required String associationId}) async {
    final rows = await db
        .from('memberships')
        .select('flat_id, flats(number)')
        .eq('association_id', associationId)
        .eq('user_id', db.auth.currentUser!.id)
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

  static VisitorRequest _fromRow(Map<String, dynamic> row) {
    final flat = row['flats'] as Map? ?? const {};
    final vehicles = List<Map<String, dynamic>>.from(flat['flat_vehicles'] as List? ?? const []);
    String? vehicle(String type) => vehicles
        .where((v) => v['vehicle_type'] == type)
        .map((v) => v['registration_number'] as String?)
        .firstOrNull;
    final slots = vehicles.map((v) => v['parking_slot'] as String?).whereType<String>();
    return VisitorRequest(
      id: row['id'] as String,
      hostFlat: flat['number'] as String? ?? '',
      guestName: row['guest_name'] as String,
      guestPhone: row['guest_phone'] as String?,
      expectedAt: DateTime.parse(row['expected_arrival'] as String).toLocal(),
      vehicleNumber: row['vehicle_number'] as String?,
      note: row['note'] as String? ?? '',
      status: _status(row['status']),
      hostName: row['host_name'] as String? ?? '',
      flatCarNumber: vehicle('car'),
      flatBikeNumber: vehicle('bike'),
      parkingSlot: slots.firstOrNull,
      guestCount: (row['guest_count'] as num?)?.toInt() ?? 1,
      passCode: row['pass_code'] as String?,
    );
  }

  static Future<List<VisitorRequest>> load({bool hostOnly = false, String? associationId}) async {
    const columns =
        'id, guest_name, guest_phone, expected_arrival, vehicle_number, note, status, host_name, guest_count, pass_code, '
        'flats(number, flat_vehicles(vehicle_type, registration_number, parking_slot))';
    final query = db
        .from('visitor_requests')
        .select(columns);
    final rows = await (hostOnly ? query.eq('host_id', db.auth.currentUser!.id) : query).order(
      'expected_arrival',
      ascending: false,
    );
    final visitors = [for (final row in rows) _fromRow(row)];
    if (!hostOnly || associationId == null) return visitors;

    final flatIds = (await myFlats(associationId: associationId)).map((flat) => flat.$1).toSet();
    if (flatIds.isEmpty) return visitors;
    final lobbyRows = await db
        .from('visitor_requests')
        .select(columns)
        .eq('association_id', associationId)
        .inFilter('flat_id', flatIds.toList())
        .eq('approval', 'lobby')
        .order('expected_arrival', ascending: false);
    final knownIds = visitors.map((visitor) => visitor.id).toSet();
    visitors.addAll([
      for (final row in lobbyRows)
        if (knownIds.add(row['id'] as String)) _fromRow(row),
    ]);
    visitors.sort((a, b) => b.expectedAt.compareTo(a.expectedAt));
    return visitors;
  }

  static Future<void> create({
    required String flatId,
    required String guestName,
    required String guestPhone,
    required DateTime expectedArrival,
    required String vehicleNumber,
    required String note,
    int guestCount = 1,
  }) async {
    await db.rpc(
      'create_visitor_request',
      params: {
        'p_flat': flatId,
        'p_guest_name': guestName,
        'p_guest_phone': guestPhone,
        'p_expected_arrival': expectedArrival.toUtc().toIso8601String(),
        'p_vehicle_number': vehicleNumber,
        'p_note': note,
        'p_guest_count': guestCount,
      },
    );
  }

  static Future<void> verify(String requestId, VisitorStatus status) async {
    final action = switch (status) {
      VisitorStatus.checkedIn => 'check_in',
      VisitorStatus.checkedOut => 'check_out',
      _ => throw ArgumentError.value(status, 'status', 'Unsupported visitor status transition'),
    };
    await db.rpc('verify_visitor_request', params: {'p_request': requestId, 'p_action': action});
  }
}

VisitorStatus _status(Object? status) => switch (status) {
  'checked_in' => VisitorStatus.checkedIn,
  'checked_out' => VisitorStatus.checkedOut,
  'cancelled' => VisitorStatus.cancelled,
  _ => VisitorStatus.expected,
};
