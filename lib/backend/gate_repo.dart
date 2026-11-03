import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'backend.dart';
import 'upload_preparation.dart';

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
  String? photoPath,
  String? guardName,
});

class GateRepo {
  static final _requestIdRandom = Random.secure();

  static String newWalkInRequestId() {
    final bytes = List<int>.generate(16, (_) => _requestIdRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

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
    photoPath: r['photo_path'] as String?,
    guardName: r['guard_name'] as String?,
  );

  static const _cols =
      'id, guest_name, guest_phone, status, approval, entry_type, vehicle_number, pass_code, expected_arrival, photo_path, guard_name, flats(number)';

  /// Visitors expected or at the gate from yesterday onwards.
  static Future<List<GateVisitor>> today({required String associationId, bool hostOnly = false}) async {
    final since = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
    final query = db
        .from('visitor_requests')
        .select(_cols)
        .eq('association_id', associationId)
        .gte('expected_arrival', since);
    final rows = await (hostOnly ? query.eq('host_id', db.auth.currentUser!.id) : query)
        .order('expected_arrival');
    final visitors = [for (final r in rows) _row(r)];
    if (!hostOnly) return visitors;
    final flatRows = await db
        .from('memberships')
        .select('flat_id')
        .eq('association_id', associationId)
        .eq('user_id', db.auth.currentUser!.id)
        .isFilter('ended_at', null)
        .inFilter('role', ['owner', 'resident']);
    final flatIds = {
      for (final r in flatRows)
        if (r['flat_id'] case final String id) id,
    };
    final walkIns = flatIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await db
              .from('visitor_requests')
              .select(_cols)
              .eq('association_id', associationId)
              .inFilter('flat_id', flatIds.toList())
              .eq('approval', 'awaiting')
              .gte('expected_arrival', since)
              .order('expected_arrival');
    final knownIds = visitors.map((v) => v.id).toSet();
    visitors.addAll([for (final r in walkIns) if (!knownIds.contains(r['id'])) _row(r)]);
    visitors.sort((a, b) => a.arrival.compareTo(b.arrival));
    return visitors;
  }

  /// Active flat numbers for walk-in suggestions; cached on the phone for offline use.
  static Future<List<String>> flatNumbers({required String associationId}) async {
    final rows = await db
        .from('flats')
        .select('number')
        .eq('association_id', associationId)
        .isFilter('retired_at', null)
        .order('number');
    return [for (final r in rows) r['number'] as String];
  }

  static Future<List<GateVisitor>> history({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();
    final rows = await db
        .from('visitor_requests')
        .select(_cols)
        .gte('expected_arrival', since)
        .order('expected_arrival', ascending: false)
        .limit(500);
    return [for (final r in rows) _row(r)];
  }

  static Future<String?> checkPass(String code) async {
    final rows = await db.rpc('gate_check_pass', params: {'p_code': code.trim()}) as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map;
    return '${r['guest_name']} for flat ${r['flat_number']} (invited by ${r['host_name']})';
  }

  static Future<String> walkIn({
    required String requestId,
    required String flat,
    required String name,
    String phone = '',
    String type = 'guest',
    String vehicle = '',
  }) async => await db.rpc(
    'gate_walk_in',
    params: {
      'p_flat': flat,
      'p_name': name,
      'p_phone': phone,
      'p_type': type,
      'p_vehicle': vehicle,
      'p_request_id': requestId,
    },
  ) as String;

  static Future<void> attachPhoto(String id, Uint8List bytes) async {
    final prepared = await prepareUpload(bytes, 'jpg');
    final assoc = await db.rpc('my_association') as String;
    final path = '$assoc/$id.${prepared.extension}';
    await db.storage
        .from('visitor-photos')
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    await db.rpc('set_visitor_photo', params: {'p_request': id, 'p_path': path});
  }

  static Future<String> photoUrl(String path) => db.storage.from('visitor-photos').createSignedUrl(path, 300);

  static Future<List<({String name, String role, String mobile})>> flatContacts(String flat) async {
    final rows = await db.rpc('gate_flat_contacts', params: {'p_flat': flat.trim()}) as List;
    return [
      for (final r in rows.cast<Map>())
        (name: r['name'] as String, role: r['role'] as String, mobile: r['mobile'] as String),
    ];
  }

  static Future<List<({String id, String name})>> guards() async {
    final rows = await db.from('gate_guards').select('id, name').eq('active', true).order('name');
    return [for (final r in rows) (id: r['id'] as String, name: r['name'] as String)];
  }

  static Future<void> saveGuard(String name, String pin, {String? id}) =>
      db.rpc('save_gate_guard', params: {'p_id': id, 'p_name': name, 'p_pin': pin});

  static Future<void> removeGuard(String id) => db.rpc('remove_gate_guard', params: {'p_id': id});

  /// Returns the guard's name, or an error such as a wrong PIN or a lockout.
  static Future<({String? name, String? error})> startShift(String id, String pin) async {
    final r = await db.rpc('gate_start_shift', params: {'p_guard': id, 'p_pin': pin}) as Map;
    return r['ok'] == true ? (name: r['name'] as String, error: null) : (name: null, error: r['error'] as String?);
  }

  static Future<String?> currentShift(String associationId) =>
      AssociationContext.run(() async {
        if (await db.rpc('my_association') != associationId) {
          throw StateError('The active association changed. Reload the gate to continue.');
        }
        return await db.rpc('gate_current_shift') as String?;
      });

  /// Deletes visitor photos older than 60 days (runs when the Gate screen opens).
  static Future<void> purgeOldPhotos() async {
    final paths = [for (final p in await db.rpc('expired_visitor_photos') as List) p as String];
    if (paths.isEmpty) return;
    await db.storage.from('visitor-photos').remove(paths);
    await db.rpc('clear_visitor_photos', params: {'p_paths': paths});
  }

  static Future<void> decide(String id, bool approve) =>
      db.rpc('decide_gate_visitor', params: {'p_request': id, 'p_approve': approve});
}
