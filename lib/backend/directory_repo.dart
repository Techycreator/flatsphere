import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';

Occupancy _occupancy(Object? s) => switch (s) {
  'rented' => Occupancy.rented,
  'vacant' => Occupancy.vacant,
  _ => Occupancy.ownerOccupied,
};

String _occupancyDb(Occupancy o) => switch (o) {
  Occupancy.rented => 'rented',
  Occupancy.vacant => 'vacant',
  Occupancy.ownerOccupied => 'owner_occupied',
};

String _mime(String ext) => switch (ext.toLowerCase()) {
  'pdf' => 'application/pdf',
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

String? _date(DateTime? d) => d?.toIso8601String().substring(0, 10);

/// Flats, members/invites and private ID proofs. Writes go through server-side functions that check the caller.
class DirectoryRepo {
  static const _bucket = 'id-proofs';

  static Future<List<FlatInfo>> flats() async {
    final rows = await db.from('flats').select('id, number, block, flat_type, sqft, occupancy').order('number');
    return [
      for (final r in rows)
        FlatInfo(
          id: r['id'] as String,
          number: r['number'] as String,
          block: r['block'] as String? ?? '',
          type: r['flat_type'] as String,
          sqft: r['sqft'] as int?,
          occupancy: _occupancy(r['occupancy']),
        ),
    ];
  }

  static Future<void> saveFlat(FlatInfo f) async {
    final row = {
      'number': f.number,
      'block': f.block,
      'flat_type': f.type,
      'sqft': f.sqft,
      'occupancy': _occupancyDb(f.occupancy),
    };
    if (f.id == null) {
      await db.from('flats').insert(row);
    } else {
      await db.from('flats').update(row).eq('id', f.id!);
    }
  }

  static Future<List<Person>> people() async {
    final rows = await db.rpc('directory') as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        if (roleFromDb(r['role']) case final role?)
          Person(
            id: r['id'] as String,
            invited: r['kind'] == 'invited',
            name: r['full_name'] as String,
            email: r['email'] as String? ?? '',
            mobile: r['mobile'] as String?,
            role: role,
            flatNumber: r['flat_number'] as String?,
            designations: List<String>.from(r['designations'] as List? ?? const []),
            monitorCategories: List<String>.from(r['monitor_categories'] as List? ?? const []),
            monitorFrom: DateTime.tryParse(r['monitor_from'] as String? ?? ''),
            monitorUntil: DateTime.tryParse(r['monitor_until'] as String? ?? ''),
            assignedBy: r['assigned_by'] as String?,
            since: DateTime.tryParse(r['since'] as String? ?? '')?.toLocal(),
          ),
    ];
  }

  /// Returns 'member' (role added to an existing account) or 'invited'.
  static Future<String> add(Person p) async => await db.rpc(
    'add_member',
    params: {
      'p_full_name': p.name,
      'p_email': p.email,
      'p_mobile': p.mobile ?? '',
      'p_role': dbRole(p.role),
      'p_flat': p.flatNumber,
      'p_designations': p.designations,
      'p_monitor_categories': p.monitorCategories,
      'p_from': _date(p.monitorFrom),
      'p_until': _date(p.monitorUntil),
    },
  ) as String;

  static Future<void> setDetails(
    Person p,
    List<String> designations,
    List<String> areas, {
    DateTime? from,
    DateTime? until,
  }) => db.rpc(
    'set_member_details',
    params: {
      'p_kind': p.invited ? 'invited' : 'member',
      'p_id': p.id,
      'p_designations': designations,
      'p_monitor_categories': areas,
      'p_from': _date(from),
      'p_until': _date(until),
    },
  );

  static Future<void> remove(Person p) =>
      db.rpc('remove_member', params: {'p_kind': p.invited ? 'invited' : 'member', 'p_id': p.id});

  static Future<List<IdDocument>> docs(String email) async {
    final rows = await db
        .from('id_documents')
        .select('id, doc_type, number_last4, storage_path, created_at, archived_at')
        .eq('subject_email', email.toLowerCase())
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        IdDocument(
          id: r['id'] as String,
          type: r['doc_type'] as String,
          last4: r['number_last4'] as String?,
          path: r['storage_path'] as String,
          uploadedAt: DateTime.parse(r['created_at'] as String).toLocal(),
          archived: r['archived_at'] != null,
        ),
    ];
  }

  static Future<void> uploadDoc({
    required Person person,
    required String? flatId,
    required String type,
    required String last4,
    required Uint8List bytes,
    required String ext,
  }) async {
    final assoc = await db.rpc('my_association') as String;
    final path = '$assoc/${flatId ?? 'none'}/${DateTime.now().microsecondsSinceEpoch}.${ext.toLowerCase()}';
    await db.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: _mime(ext)));
    await db.from('id_documents').insert({
      'subject_email': person.email.toLowerCase(),
      'subject_name': person.name,
      'flat_id': flatId,
      'doc_type': type,
      'number_last4': last4.isEmpty ? null : last4,
      'storage_path': path,
    });
  }

  /// Logs the view, then returns a link valid for 60 seconds.
  static Future<String> viewUrl(IdDocument d) async {
    await db.rpc('log_id_view', params: {'doc': d.id});
    return db.storage.from(_bucket).createSignedUrl(d.path!, 60);
  }
}

/// Server errors look like 'not_allowed: reason'; show just the reason.
String friendlyError(Object e) {
  final msg = e is PostgrestException ? e.message : (e is StorageException ? e.message : '$e');
  final i = msg.indexOf(': ');
  return i > 0 && !msg.substring(0, i).contains(' ') ? msg.substring(i + 2) : msg;
}
