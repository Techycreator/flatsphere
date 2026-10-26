import '../models/models.dart';
import 'backend.dart';

const _decisionDb = {
  Decision.pending: 'pending',
  Decision.approved: 'approved',
  Decision.rejected: 'rejected',
  Decision.sentBack: 'sent_back',
};

class ApprovalsRepo {
  /// App ids are the human-readable refs (APR-...); the server keys rows by uuid.
  static final _uuidByRef = <String, String>{};

  static Future<List<ApprovalRequest>> fetchAll(DemoUser me) async {
    final rows = await db
        .from('approval_requests')
        .select('*, approval_steps(*)')
        .order('created_at', ascending: false);
    return [for (final r in rows) _fromRow(r, me)];
  }

  static Future<String> insert(ApprovalRequest a) async {
    final row = await db
        .from('approval_requests')
        .insert({
          'ref': a.id,
          'code': a.code,
          'title': a.title,
          'details': a.details,
          'initiator_name': a.initiatorName,
          'initiator_role': dbRole(a.initiatorRole),
          'category': a.category,
          'mom_required': a.momRequired,
          'mom_ref': a.momRef,
          'high_risk': a.highRisk,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    _uuidByRef[a.id] = id;
    await db.from('approval_steps').insert([
      for (final (i, s) in a.steps.indexed)
        {
          'request_id': id,
          'seq': i + 1,
          'role': dbRole(s.role),
          'alternate_role': s.alternateRole == null ? null : dbRole(s.alternateRole!),
          'name': s.name,
          'on_behalf_of': s.onBehalfOf,
          'owner_flat': s.role == Role.owner ? a.details['Flat']?.split(' ').first : null,
        },
    ]);
    return id;
  }

  static Future<void> decide(String ref, Decision d, String? comment) =>
      db.rpc('decide_step', params: {'req': _uuidByRef[ref], 'd': _decisionDb[d], 'note': comment});

  static Future<void> toggleFlag(String ref) => db.rpc('toggle_flag', params: {'req': _uuidByRef[ref]});

  static ApprovalRequest _fromRow(Map<String, dynamic> r, DemoUser me) {
    final ref = r['ref'] as String? ?? r['id'] as String;
    _uuidByRef[ref] = r['id'] as String;
    final steps = List<Map<String, dynamic>>.from(r['approval_steps'] as List? ?? const [])
      ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    return ApprovalRequest(
      id: ref,
      code: r['code'] as String,
      title: r['title'] as String,
      initiatorName: r['initiator_name'] as String? ?? '',
      initiatorRole: roleFromDb(r['initiator_role']) ?? Role.ecMember,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      category: r['category'] as String? ?? 'General',
      momRequired: r['mom_required'] as bool? ?? false,
      momRef: r['mom_ref'] as String?,
      highRisk: r['high_risk'] as bool? ?? false,
      flagged: r['flagged'] as bool? ?? false,
      details: {for (final e in (r['details'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
      steps: [for (final s in steps) _stepFromRow(s, me)],
    );
  }

  static ApproverStep _stepFromRow(Map<String, dynamic> s, DemoUser me) {
    final role = roleFromDb(s['role']) ?? Role.president;
    final alt = roleFromDb(s['alternate_role']);
    // Owner-consent steps are bound to a flat; show them as the signed-in owner's when it is theirs.
    final mine = role == Role.owner && me.roles.contains(Role.owner) && s['owner_flat'] == me.flatNumber;
    final by = s['decided_by_name'] as String?;
    return ApproverStep(
      role: role,
      alternateRole: alt,
      name: mine ? me.name : s['name'] as String? ?? '',
      decision: _decisionDb.entries.firstWhere((e) => e.value == s['decision']).key,
      comment: s['comment'] as String?,
      onBehalfOf: s['on_behalf_of'] as String?,
      decidedBy: by == null ? null : '$by (${alt == null ? role.label : '${role.label} / ${alt.label}'})',
    );
  }
}
