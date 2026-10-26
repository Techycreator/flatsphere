import '../models/models.dart';
import 'backend.dart';

class MembershipTransitionRepo {
  static Future<({String status, int outstandingDue})> paymentGate(String approvalRef) async {
    final request = await db.from('approval_requests').select('id').eq('ref', approvalRef).single();
    final row = await db
        .from('membership_changes')
        .select('status,outstanding_due')
        .eq('request_id', request['id'])
        .single();
    return (status: row['status'] as String, outstandingDue: (row['outstanding_due'] as num?)?.toInt() ?? 0);
  }

  static Future<List<MembershipTransitionItem>> checklist(String approvalRef) async {
    final request = await db.from('approval_requests').select('id').eq('ref', approvalRef).single();
    final rows = await db
        .from('membership_transition_items')
        .select('id,phase,label,required,completed,completed_by,completed_at,note')
        .eq('request_id', request['id'])
        .order('phase')
        .order('created_at');
    return [
      for (final row in rows)
        MembershipTransitionItem(
          id: row['id'] as String,
          phase: row['phase'] as String,
          label: row['label'] as String,
          required: row['required'] as bool? ?? false,
          completed: row['completed'] as bool? ?? false,
          completedBy: row['completed_by'] as String?,
          completedAt: row['completed_at'] == null ? null : DateTime.parse(row['completed_at'] as String).toLocal(),
          note: row['note'] as String? ?? '',
        ),
    ];
  }

  static Future<void> update(String itemId, bool completed, String note) async {
    await db.rpc(
      'update_membership_transition_item',
      params: {'p_item': itemId, 'p_completed': completed, 'p_note': note},
    );
  }
}
