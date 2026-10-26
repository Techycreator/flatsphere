import 'backend.dart';

class ComplianceRepo {
  static Future<bool> privacyAccepted() async => await db.rpc('my_privacy_accepted') as bool? ?? false;

  static Future<void> acceptPrivacy() => db.rpc('accept_privacy_notice');

  static Future<List<({DateTime at, String actor, String action, String entity, String? entityId})>> auditLog() async {
    final rows = await db.rpc('list_audit_log', params: {'p_limit': 300}) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (
          at: DateTime.parse(r['at'] as String).toLocal(),
          actor: r['actor_name'] as String? ?? 'System',
          action: r['action'] as String,
          entity: r['entity'] as String,
          entityId: r['entity_id'] as String?,
        ),
    ];
  }

  static Future<Map<String, dynamic>> exportData() async =>
      Map<String, dynamic>.from(await db.rpc('export_association_data') as Map);
}
