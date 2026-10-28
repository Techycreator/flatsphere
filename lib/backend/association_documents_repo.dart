import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'upload_preparation.dart';

const associationDocumentTypes = {
  'sale_deed': 'Sale deeds and property documents',
  'building_plan': 'Approved building plans',
  'completion_certificate': 'Project completion certificates',
  'occupancy_certificate': 'Occupancy certificates',
  'encumbrance_certificate': 'Encumbrance certificates',
  'noc': 'NOCs and approvals',
  'property_insurance': 'Property insurance',
  'corpus_transfer': 'Maintenance corpus transfers',
  'maintenance_agreement': 'Maintenance agreements',
  'other': 'Other association records',
};

class AssociationDocumentsRepo {
  static const _bucket = 'association-documents';

  static Future<List<AssociationRegisterItem>> list() async {
    final rows = await db
        .from('association_documents')
        .select('id,document_type,title,issue_date,expiry_date,version,archived_at,created_at')
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        AssociationRegisterItem(
          id: row['id'] as String,
          type: row['document_type'] as String,
          name: row['title'] as String,
          category: associationDocumentTypes[row['document_type']] as String? ?? 'Other',
          status: row['archived_at'] == null ? 'active' : 'archived',
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          expiresOn: row['expiry_date'] == null ? null : DateTime.parse(row['expiry_date'] as String),
          details: {'version': row['version'], 'issue_date': row['issue_date'], 'archived_at': row['archived_at']},
        ),
    ];
  }

  static Future<String> upload({
    required String type,
    required String title,
    required Uint8List bytes,
    required String extension,
    DateTime? issueDate,
    DateTime? expiryDate,
  }) async {
    final prepared = await prepareUpload(bytes, extension);
    final association = await db.rpc('my_association') as String;
    final path = '$association/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from(_bucket)
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    try {
      final id = await db.rpc(
        'add_association_document',
        params: {
          'p_type': type,
          'p_title': title.trim(),
          'p_storage_path': path,
          'p_issue_date': _date(issueDate),
          'p_expiry_date': _date(expiryDate),
        },
      ) as String;
      return id;
    } catch (_) {
      await db.storage.from(_bucket).remove([path]);
      rethrow;
    }
  }

  static Future<String> viewUrl(String id) async {
    await db.rpc('log_association_document_view', params: {'p_document': id});
    final row = await db.from('association_documents').select('storage_path').eq('id', id).single();
    return db.storage.from(_bucket).createSignedUrl(row['storage_path'] as String, 60);
  }

  static String? _date(DateTime? date) => date?.toIso8601String().substring(0, 10);
}
