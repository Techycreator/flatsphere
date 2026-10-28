import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'upload_preparation.dart';

String _snake(String s) =>
    s == 'newTicket' ? 'new' : s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

T _parse<T extends Enum>(List<T> values, Object? v, T fallback) =>
    values.where((e) => _snake(e.name) == v || e.name == v).firstOrNull ?? fallback;

typedef VoiceFormat = ({String extension, String contentType});
const wavVoiceFormat = (extension: 'wav', contentType: 'audio/wav');
const webmVoiceFormat = (extension: 'webm', contentType: 'audio/webm');
const m4aVoiceFormat = (extension: 'm4a', contentType: 'audio/mp4');

class ComplaintsRepo {
  static const _select =
      '*, vendor:association_vendors(name), complaint_remarks(author_name, body, created_at), complaint_media(kind, storage_path)';

  static Future<List<Complaint>> fetchAll() async {
    final rows = await db.from('complaints').select(_select).order('created_at', ascending: false);
    return rows.map(_fromRow).toList();
  }

  static Future<void> insert(
    Complaint c, {
    List<Uint8List> photos = const [],
    Uint8List? voiceNote,
    VoiceFormat voiceFormat = wavVoiceFormat,
  }) async {
    final preparedPhotos = [for (final photo in photos) await prepareUpload(photo, 'jpg')];
    if (voiceNote != null && voiceNote.length > maxUploadBytes) {
      throw ArgumentError.value(voiceNote.length, 'voiceNote', 'Voice note must be 5 MB or smaller');
    }
    final row = await db.from('complaints').insert(_toRow(c)..['ref'] = c.id).select('id').single();
    final complaintId = row['id'] as String;
    await _addRemarks(complaintId, c.remarks);
    if (preparedPhotos.isNotEmpty || voiceNote != null) {
      try {
        await _uploadMedia(complaintId, preparedPhotos, voiceNote, voiceFormat);
      } catch (error) {
        throw StateError('Request ${c.id} was submitted, but its attachments could not be uploaded: $error');
      }
    }
  }

  static Future<void> _uploadMedia(
    String complaintId,
    List<PreparedUpload> photos,
    Uint8List? voiceNote,
    VoiceFormat voiceFormat,
  ) async {
    final association = await db.rpc('my_association') as String;
    final uploadedPaths = <String>[];
    final media = <Map<String, String>>[];

    Future<void> upload(String kind, Uint8List bytes, String extension, String contentType, int index) async {
      final path = '$association/$complaintId/${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
      await db.storage
          .from('complaint-media')
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType));
      uploadedPaths.add(path);
      media.add({'complaint_id': complaintId, 'kind': kind, 'storage_path': path});
    }

    try {
      for (var i = 0; i < photos.length; i++) {
        final photo = photos[i];
        await upload('photo', photo.bytes, photo.extension, photo.contentType, i);
      }
      if (voiceNote != null) {
        await upload('voice', voiceNote, voiceFormat.extension, voiceFormat.contentType, photos.length);
      }
      await db.from('complaint_media').insert(media);
    } catch (error) {
      if (uploadedPaths.isNotEmpty) {
        try {
          await db.storage.from('complaint-media').remove(uploadedPaths);
        } catch (cleanupError) {
          throw StateError('Attachment upload failed: $error. Temporary file cleanup failed: $cleanupError');
        }
      }
      rethrow;
    }
  }

  static Future<String> mediaUrl(String path) => db.storage.from('complaint-media').createSignedUrl(path, 300);

  static Future<void> update(Complaint before, Complaint after) async {
    final row = await db.from('complaints').update(_toRow(after)).eq('ref', after.id).select('id').single();
    if (after.remarks.length > before.remarks.length) {
      await _addRemarks(row['id'] as String, after.remarks.sublist(before.remarks.length));
    }
  }

  static Future<void> setStatus(String ref, TicketStatus status, String note) =>
      db.rpc('set_complaint_status', params: {'p_ref': ref, 'p_status': _snake(status.name), 'p_note': note});

  static Future<void> closeOrReopen(String ref, {required bool close, String note = ''}) =>
      db.rpc('close_or_reopen_complaint', params: {'p_ref': ref, 'p_close': close, 'p_note': note});

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
    'vendor_id': c.vendorId,
    'raised_by_name': c.raisedBy,
    'assignee_name': c.assignee,
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
      raisedById: r['raised_by'] as String?,
      aiSuggested: r['ai_suggested'] as bool? ?? false,
      assignee: r['assignee_name'] as String?,
      remarks: remarks,
      media: [
        for (final item in (r['complaint_media'] as List? ?? const []))
          ComplaintMedia(kind: item['kind'] as String, storagePath: item['storage_path'] as String),
      ],
      photoCount: r['photo_count'] as int? ?? 0,
      hasVoiceNote: r['has_voice_note'] as bool? ?? false,
      isPrivate: r['is_private'] as bool? ?? false,
      location: r['location'] as String? ?? 'Inside flat',
      kind: _parse(ReportKind.values, r['kind'], ReportKind.complaint),
      acceptedAt: r['accepted_at'] == null ? null : DateTime.parse(r['accepted_at'] as String).toLocal(),
      estimatedCost: r['estimated_cost'] as int?,
      vendorId: r['vendor_id'] as String?,
      vendorName: (r['vendor'] as Map?)?['name'] as String?,
    );
  }
}
