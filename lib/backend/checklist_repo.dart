import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'upload_preparation.dart';

const _checklistBucket = 'checklist-proofs';
const _notesBucket = 'checklist-notes';

class ChecklistRepo {
  static Future<Map<String, List<String>>> proofs(DateTime date) async {
    final rows = await db
        .from('checklist_proofs')
        .select('item_id, storage_path')
        .eq('checklist_date', _date(date))
        .order('created_at');
    final result = <String, List<String>>{};
    for (final row in rows) {
      result.putIfAbsent(row['item_id'] as String, () => []).add(row['storage_path'] as String);
    }
    return result;
  }

  static Future<String> uploadPhoto({required String itemId, required DateTime date, required Uint8List source}) async {
    final prepared = await prepareUpload(source, 'jpg');
    final association = await db.rpc('my_association') as String;
    final day = _date(date);
    final path = '$association/$day/$itemId/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from(_checklistBucket)
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    try {
      await db.from('checklist_proofs').insert({'checklist_date': day, 'item_id': itemId, 'storage_path': path});
    } catch (_) {
      await db.storage.from(_checklistBucket).remove([path]);
      rethrow;
    }
    return path;
  }

  static Future<String> viewUrl(String path) => db.storage.from(_checklistBucket).createSignedUrl(path, 60);

  static Future<Map<String, ({String note, String? voicePath})>> notes(DateTime date) async {
    final rows = await db
        .from('checklist_notes')
        .select('item_id, note, voice_path')
        .eq('checklist_date', _date(date));
    return {
      for (final r in rows) r['item_id'] as String: (note: r['note'] as String? ?? '', voicePath: r['voice_path'] as String?),
    };
  }

  /// Saves the day's note; [voice] replaces the stored recording, [removeVoice] clears it.
  static Future<String?> saveNote({
    required String itemId,
    required DateTime date,
    required String note,
    Uint8List? voice,
    String voiceExtension = 'wav',
    String voiceContentType = 'audio/wav',
    bool removeVoice = false,
  }) async {
    final day = _date(date);
    String? voicePath;
    if (voice != null) {
      final association = await db.rpc('my_association') as String;
      voicePath = '$association/$day/$itemId/${DateTime.now().microsecondsSinceEpoch}.$voiceExtension';
      await db.storage
          .from(_notesBucket)
          .uploadBinary(voicePath, voice, fileOptions: FileOptions(contentType: voiceContentType));
    }
    try {
      await db.from('checklist_notes').upsert({
        'checklist_date': day,
        'item_id': itemId,
        'note': note,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (voicePath != null) 'voice_path': voicePath,
        if (removeVoice && voicePath == null) 'voice_path': null,
      }, onConflict: 'association_id,checklist_date,item_id');
    } catch (_) {
      if (voicePath != null) await db.storage.from(_notesBucket).remove([voicePath]);
      rethrow;
    }
    return voicePath;
  }

  static Future<String> voiceUrl(String path) => db.storage.from(_notesBucket).createSignedUrl(path, 120);

  static Future<List<ChecklistItem>> items() async {
    final rows = await db
        .from('checklist_items')
        .select('id, title, category, time_window, proof_required')
        .eq('active', true)
        .order('sort_order')
        .order('created_at');
    return [
      for (final r in rows)
        ChecklistItem(
          id: r['id'] as String,
          title: r['title'] as String,
          category: r['category'] as String,
          timeWindow: r['time_window'] as String? ?? '',
          proofRequired: r['proof_required'] as bool? ?? false,
        ),
    ];
  }

  static Future<void> addItem(ChecklistItem item, int sortOrder) => db.from('checklist_items').insert({
    'title': item.title,
    'category': item.category,
    'time_window': item.timeWindow,
    'proof_required': item.proofRequired,
    'sort_order': sortOrder,
  });

  /// Deactivates the item; past photo proofs stay linked to it.
  static Future<void> removeItem(String id) => db.from('checklist_items').update({'active': false}).eq('id', id);
}

String _date(DateTime date) => date.toIso8601String().substring(0, 10);
