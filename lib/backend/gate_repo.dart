import 'backend.dart';

typedef GateVisitor = ({
  String id,
  String guest,
  String? phone,
  String flat,
  String status,
  String approval,
  String type,
  String? vehicle,
  String? passCode,
  DateTime arrival,
});

class GateRepo {
  static GateVisitor _row(Map<String, dynamic> r) => (
    id: r['id'] as String,
    guest: r['guest_name'] as String,
    phone: r['guest_phone'] as String?,
    flat: (r['flats'] as Map?)?['number'] as String? ?? '',
    status: r['status'] as String,
    approval: r['approval'] as String? ?? 'pre_approved',
    type: r['entry_type'] as String? ?? 'guest',
    vehicle: r['vehicle_number'] as String?,
    passCode: r['pass_code'] as String?,
    arrival: DateTime.parse(r['expected_arrival'] as String).toLocal(),
  );

  static const _cols =
      'id, guest_name, guest_phone, status, approval, entry_type, vehicle_number, pass_code, expected_arrival, flats(number)';

  /// Visitors expected or at the gate from yesterday onwards.
  static Future<List<GateVisitor>> today() async {
    final since = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
    final rows = await db
        .from('visitor_requests')
        .select(_cols)
        .gte('expected_arrival', since)
        .order('expected_arrival');
    return [for (final r in rows) _row(r)];
  }

  static Future<String?> checkPass(String code) async {
    final rows = await db.rpc('gate_check_pass', params: {'p_code': code.trim()}) as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map;
    return '${r['guest_name']} for flat ${r['flat_number']} (invited by ${r['host_name']})';
  }

  static Future<void> walkIn({
    required String flat,
    required String name,
    String phone = '',
    String type = 'guest',
    String vehicle = '',
  }) => db.rpc(
    'gate_walk_in',
    params: {'p_flat': flat, 'p_name': name, 'p_phone': phone, 'p_type': type, 'p_vehicle': vehicle},
  );

  static Future<void> decide(String id, bool approve) =>
      db.rpc('decide_gate_visitor', params: {'p_request': id, 'p_approve': approve});
}
