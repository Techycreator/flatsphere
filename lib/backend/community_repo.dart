import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'upload_preparation.dart';

class CommunityRepo {
  static Future<List<EmergencyContact>> emergencyContacts() async {
    final rows = await db
        .from('emergency_contacts')
        .select('id,label,contact_name,phone,category,notes')
        .eq('active', true)
        .order('category');
    return [
      for (final row in rows)
        EmergencyContact(
          id: row['id'] as String,
          label: row['label'] as String,
          name: row['contact_name'] as String,
          phone: row['phone'] as String,
          category: row['category'] as String? ?? 'Emergency',
          notes: row['notes'] as String? ?? '',
        ),
    ];
  }

  static Future<void> addEmergencyContact({
    required String label,
    required String name,
    required String phone,
    required String category,
    required String notes,
  }) async {
    await db.from('emergency_contacts').insert({
      'label': label.trim(),
      'contact_name': name.trim(),
      'phone': phone.trim(),
      'category': category.trim(),
      'notes': notes.trim(),
    });
  }

  static Future<List<CommunityEvent>> events() async {
    final rows = await db
        .from('community_events')
        .select(
          'id,title,event_type,starts_at,ends_at,location,budget,description,status,fund_request_id,fund_requests(title),community_event_photos(storage_path)',
        )
        .order('starts_at');
    return [
      for (final row in rows)
        CommunityEvent(
          id: row['id'] as String,
          title: row['title'] as String,
          type: row['event_type'] as String,
          startsAt: DateTime.parse(row['starts_at'] as String).toLocal(),
          endsAt: DateTime.parse(row['ends_at'] as String).toLocal(),
          location: row['location'] as String? ?? '',
          budget: (row['budget'] as num?)?.toInt(),
          description: row['description'] as String? ?? '',
          status: row['status'] as String? ?? 'scheduled',
          photoPaths: [
            for (final photo in (row['community_event_photos'] as List? ?? const []))
              if (photo['storage_path'] is String) photo['storage_path'] as String,
          ],
          fundRequestId: row['fund_request_id'] as String?,
          fundRequestTitle: ((row['fund_requests'] as Map?)?['title'] as String?),
        ),
    ];
  }

  static Future<void> addEvent({
    required String title,
    required String type,
    required DateTime startsAt,
    required DateTime endsAt,
    required String location,
    required int? budget,
    required String description,
    Uint8List? photo,
    String? photoExtension,
    String? fundRequestId,
  }) async {
    final row = await db
        .from('community_events')
        .insert({
          'title': title.trim(),
          'event_type': type,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt.toUtc().toIso8601String(),
          'location': location.trim(),
          'budget': budget,
          'description': description.trim(),
          'fund_request_id': fundRequestId,
        })
        .select('id')
        .single();
    if (photo == null) return;
    final prepared = await prepareUpload(photo, photoExtension ?? 'jpg');
    final association = await db.rpc('my_association') as String;
    final path = '$association/${row['id']}/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from('community-event-photos')
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    try {
      await db.from('community_event_photos').insert({'event_id': row['id'], 'storage_path': path});
    } catch (_) {
      await db.storage.from('community-event-photos').remove([path]);
      rethrow;
    }
  }

  static Future<String> eventPhotoUrl(String path) =>
      db.storage.from('community-event-photos').createSignedUrl(path, 60);

  static Future<List<MeetingAction>> actions() async {
    final rows = await db
        .from('meeting_actions')
        .select('id,mom_ref,title,owner_name,due_date,status,event_id')
        .order('due_date');
    return [
      for (final row in rows)
        MeetingAction(
          id: row['id'] as String,
          momRef: row['mom_ref'] as String,
          title: row['title'] as String,
          owner: row['owner_name'] as String,
          dueDate: row['due_date'] == null ? null : DateTime.parse(row['due_date'] as String),
          status: row['status'] as String,
          eventId: row['event_id'] as String?,
        ),
    ];
  }

  static Future<void> addAction({required String momRef, required String title, required DateTime? dueDate}) async {
    await db.rpc(
      'add_meeting_action',
      params: {
        'p_mom_ref': momRef.trim(),
        'p_title': title.trim(),
        'p_due_date': dueDate?.toIso8601String().substring(0, 10),
      },
    );
  }

  static Future<void> updateAction(String id, String status) async =>
      db.rpc('update_meeting_action_status', params: {'p_action': id, 'p_status': status});

  static Future<List<MarketplacePost>> marketplace() async {
    try {
      await db.rpc('archive_marketplace_posts');
    } catch (_) {
      // Archive function may not be deployed yet; listing must still work.
    }
    final rows = await db
        .from('marketplace_posts')
        .select('id,post_type,title,description,contact,price,created_by,created_by_name,expires_at')
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        MarketplacePost(
          id: row['id'] as String,
          createdBy: row['created_by'] as String?,
          type: row['post_type'] as String,
          title: row['title'] as String,
          description: row['description'] as String,
          contact: row['contact'] as String,
          price: (row['price'] as num?)?.toInt(),
          author: row['created_by_name'] as String? ?? '',
          expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
        ),
    ];
  }

  static Future<void> removeMarketplacePost(String id) => db.rpc('remove_marketplace_post', params: {'p_id': id});

  static Future<void> addMarketplacePost({
    required String type,
    required String title,
    required String description,
    required String contact,
    required int? price,
  }) async {
    await db.from('marketplace_posts').insert({
      'post_type': type,
      'title': title.trim(),
      'description': description.trim(),
      'contact': contact.trim(),
      'price': price,
    });
  }
}
