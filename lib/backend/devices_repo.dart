import 'backend.dart';

class DevicesRepo {
  static Future<String> register(String label, String method) async =>
      await db.rpc('register_trusted_device', params: {'p_label': label, 'p_method': method}) as String;

  static Future<bool> touch(String id) async =>
      await db.rpc('touch_trusted_device', params: {'p_device': id}) as bool? ?? false;

  static Future<List<({String id, String label, String method, DateTime lastUsed})>> list() async {
    final rows = await db.rpc('list_trusted_devices') as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (
          id: r['id'] as String,
          label: r['label'] as String,
          method: r['method'] as String,
          lastUsed: DateTime.parse(r['last_used_at'] as String).toLocal(),
        ),
    ];
  }

  static Future<void> revoke(String id) => db.rpc('revoke_trusted_device', params: {'p_device': id});

  static Future<int> revokeMember(String email) async =>
      ((await db.rpc('revoke_member_devices', params: {'p_email': email})) as num).toInt();
}
