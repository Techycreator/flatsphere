import '../models/models.dart';
import 'backend.dart';

class NotificationsRepo {
  static Future<List<AppNotification>> load() async {
    final rows = await db.rpc('list_app_notifications') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        AppNotification(
          id: row['id'] as String,
          title: row['title'] as String,
          body: row['body'] as String? ?? '',
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          actionPath: row['action_path'] as String?,
          readAt: row['read_at'] == null ? null : DateTime.parse(row['read_at'] as String).toLocal(),
        ),
    ];
  }

  static Future<void> markRead(String id) => db.rpc('mark_app_notification_read', params: {'p_notification': id});
}

class PushRepo {
  static const vapidPublicKey =
      'BDAptvvF7YsEC5sIBENkNXyAlu9odKkemBT0UW-Nb8YCsbwcnX07n1Y5WVAzArFFG2R8YGOnfhh1fD702b8krT8';

  static Future<void> save(({String endpoint, String p256dh, String auth}) s) =>
      db.rpc('save_push_subscription', params: {'p_endpoint': s.endpoint, 'p_p256dh': s.p256dh, 'p_auth': s.auth});
}
