import '../models/models.dart';
import 'backend.dart';

String _snake(String s) =>
    s == 'newTicket' ? 'new' : s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

T _parse<T extends Enum>(List<T> values, Object? v, T fallback) =>
    values.where((e) => _snake(e.name) == v || e.name == v).firstOrNull ?? fallback;

class ComplaintsRepo {
  static const _select = '*, complaint_remarks(author_name, body, created_at)';

  static Future<List<Complaint>> fetchAll() async {
    final rows = await db.from('complaints').select(_select).order('created_at', ascending: false);
    return rows.map(_fromRow).toList();
  }

  static Future<void> insert(Complaint c) async {
    final row = await db.from('complaints').insert(_toRow(c)..['ref'] = c.id).select('id').single();
    await _addRemarks(row['id'] as String, c.remarks);
  }

  static Future<void> update(Complaint before, Complaint after) async {
    final row = await db.from('complaints').update(_toRow(after)).eq('ref', after.id).select('id').single();
    if (after.remarks.length > before.remarks.length) {
      await _addRemarks(row['id'] as String, after.remarks.sublist(before.remarks.length));
    }
  }

  static Future<void> setStatus(String ref, TicketStatus status, String note) =>
      db.rpc('set_complaint_status', params: {'p_ref': ref, 'p_status': _snake(status.name), 'p_note': note});

  static Future<void> _addRemarks(String complaintId, List<TicketRemark> remarks) async {
    if (remarks.isEmpty) return;
    await db.from('complaint_remarks').insert([
      for (final r in remarks) {'complaint_id': complaintId, 'author_name': r.by, 'body': r.text},
    ]);
  }

  static Map<String, dynamic> _toRow(Complaint c) => {
    'flat_number': c.flatNumber,
    'ticket_type': c.type.name,
    'kind': _snake(c.kind.name),
    'category': c.category,
    'title': c.title,
    'description': c.description,
    'location': c.location,
    'criticality': _snake(c.criticality.name),
    'ai_suggested': c.aiSuggested,
    'status': _snake(c.status.name),
    'is_private': c.isPrivate,
    'estimated_cost': c.estimatedCost,
    'raised_by_name': c.raisedBy,
    'assignee_name': c.assignee,
    'photo_count': c.photoCount,
    'has_voice_note': c.hasVoiceNote,
    'accepted_at': c.acceptedAt?.toUtc().toIso8601String(),
  };

  static Complaint _fromRow(Map<String, dynamic> r) {
    final remarks = [
      for (final m in (r['complaint_remarks'] as List? ?? const []))
        TicketRemark(
          by: m['author_name'] as String? ?? '',
          at: DateTime.parse(m['created_at'] as String).toLocal(),
          text: m['body'] as String,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return Complaint(
      id: r['ref'] as String,
      flatNumber: r['flat_number'] as String? ?? '-',
      type: _parse(TicketType.values, r['ticket_type'], TicketType.values.first),
      category: r['category'] as String,
      title: r['title'] as String,
      description: r['description'] as String? ?? '',
      criticality: _parse(Criticality.values, r['criticality'], Criticality.medium),
      status: _parse(TicketStatus.values, r['status'], TicketStatus.newTicket),
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      raisedBy: r['raised_by_name'] as String? ?? '',
      aiSuggested: r['ai_suggested'] as bool? ?? false,
      assignee: r['assignee_name'] as String?,
      remarks: remarks,
      photoCount: r['photo_count'] as int? ?? 0,
      hasVoiceNote: r['has_voice_note'] as bool? ?? false,
      isPrivate: r['is_private'] as bool? ?? false,
      location: r['location'] as String? ?? 'Inside flat',
      kind: _parse(ReportKind.values, r['kind'], ReportKind.complaint),
      acceptedAt: r['accepted_at'] == null ? null : DateTime.parse(r['accepted_at'] as String).toLocal(),
      estimatedCost: r['estimated_cost'] as int?,
    );
  }
}
