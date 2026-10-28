import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'backend.dart';
import 'upload_preparation.dart';

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

String mimeFor(String ext) => switch (ext.toLowerCase()) {
  'pdf' => 'application/pdf',
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};

String? _date(DateTime? d) => d?.toIso8601String().substring(0, 10);

/// Flats, members/invites and private ID proofs. Writes go through server-side functions that check the caller.
class DirectoryRepo {
  static const _bucket = 'id-proofs';

  static Future<List<VehicleContact>> searchVehicle(String registrationNumber) async {
    final rows = await db.rpc(
      'search_vehicle_contacts',
      params: {'p_vehicle_number': registrationNumber.trim().toUpperCase()},
    ) as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        VehicleContact(
          registrationNumber: row['registration_number'] as String,
          vehicleType: row['vehicle_type'] as String,
          flatNumber: row['flat_number'] as String,
          personName: row['person_name'] as String?,
          phone: row['phone'] as String?,
        ),
    ];
  }

  static Future<List<VehicleRegisterRow>> vehicleRegister() async {
    final rows = await db.rpc('export_vehicle_register') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        VehicleRegisterRow(
          registrationNumber: row['registration_number'] as String,
          vehicleType: row['vehicle_type'] as String,
          flatNumber: row['flat_number'] as String,
          parkingSlot: row['parking_slot'] as String?,
          occupancy: row['occupancy'] as String? ?? '',
        ),
    ];
  }

  static Future<List<FlatInfo>> flats() async {
    final rows = await db
        .from('flats')
        .select(
          'id, number, block, flat_type, sqft, occupancy, flat_vehicles(vehicle_type, registration_number, parking_slot)',
        )
        .isFilter('retired_at', null)
        .order('number');
    return [
      for (final r in rows)
        FlatInfo(
          id: r['id'] as String,
          number: r['number'] as String,
          block: r['block'] as String? ?? '',
          type: r['flat_type'] as String,
          sqft: r['sqft'] as int?,
          occupancy: _occupancy(r['occupancy']),
          carNumber: (r['flat_vehicles'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .where((v) => v['vehicle_type'] == 'car')
              .map((v) => v['registration_number'] as String?)
              .firstOrNull,
          bikeNumber: (r['flat_vehicles'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .where((v) => v['vehicle_type'] == 'bike')
              .map((v) => v['registration_number'] as String?)
              .firstOrNull,
          parkingSlot: (r['flat_vehicles'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map((v) => v['parking_slot'] as String?)
              .whereType<String>()
              .firstOrNull,
        ),
    ];
  }

  static Future<Set<String>> ownedFlatNumbers() async {
    final association = await db.rpc('my_association') as String;
    final rows = await db.rpc('my_owned_flat_numbers', params: {'assoc': association}) as List;
    return {for (final row in rows) '$row'};
  }

  static Future<Set<String>> myFlatNumbers() async {
    final rows = await db
        .from('memberships')
        .select('flats(number)')
        .eq('user_id', db.auth.currentUser!.id)
        .isFilter('ended_at', null)
        .inFilter('role', ['owner', 'resident']);
    return {
      for (final row in rows)
        if ((row['flats'] as Map?)?['number'] case final String number) number,
    };
  }

  static Future<void> createMembershipChange({
    required String requestId,
    required String flatId,
    required String type,
    required String name,
    required String email,
    required String mobile,
    required String leasePeriod,
    required List<({String name, DateTime dateOfBirth, String? email})> familyMembers,
  }) async {
    await db.rpc(
      'create_membership_change_with_family',
      params: {
        'p_request': requestId,
        'p_flat': flatId,
        'p_type': type,
        'p_name': name.trim(),
        'p_email': email.trim().toLowerCase(),
        'p_mobile': mobile.trim(),
        'p_lease': leasePeriod.trim(),
        'p_family': [
          for (final member in familyMembers)
            {
              'full_name': member.name.trim(),
              'date_of_birth': _date(member.dateOfBirth),
              'email': (member.email?.trim().isEmpty ?? true) ? null : member.email!.trim().toLowerCase(),
            },
        ],
      },
    );
  }

  static Future<void> requestFamilyMemberAddition({
    required String flatId,
    required String name,
    required DateTime dateOfBirth,
  }) => db.rpc(
    'request_family_member_addition',
    params: {'p_flat': flatId, 'p_full_name': name.trim(), 'p_date_of_birth': _date(dateOfBirth)},
  );

  static Future<List<FamilyMemberRecord>> familyMembers() async {
    final rows = await db
        .from('family_members')
        .select('id,full_name,date_of_birth,email,approved_at,flats(number)')
        .isFilter('archived_at', null)
        .order('created_at');
    return [
      for (final row in rows)
        FamilyMemberRecord(
          id: row['id'] as String,
          name: row['full_name'] as String,
          dateOfBirth: DateTime.parse(row['date_of_birth'] as String),
          email: row['email'] as String?,
          approved: row['approved_at'] != null,
          flatNumber: (row['flats'] as Map?)?['number'] as String? ?? '',
        ),
    ];
  }

  static Future<void> updateFamilyMemberEmail(String id, String email) =>
      db.rpc('update_family_member_email', params: {'p_member': id, 'p_email': email.trim().toLowerCase()});

  static Future<void> uploadRequestProof({
    required String requestId,
    required Person person,
    required String flatId,
    required String type,
    required Uint8List bytes,
    required String ext,
  }) async {
    final prepared = await prepareUpload(bytes, ext);
    final association = await db.rpc('my_association') as String;
    final path = '$association/$flatId/$requestId/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from(_bucket)
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
    await db.from('id_documents').insert({
      'request_id': requestId,
      'subject_email': person.email.toLowerCase(),
      'subject_name': person.name,
      'flat_id': flatId,
      'doc_type': type,
      'storage_path': path,
    });
  }

  static Future<void> retireFlat(String id, String reason) =>
      db.rpc('retire_flat', params: {'p_flat': id, 'p_reason': reason.trim()});

  static Future<void> saveFlat(FlatInfo f) async {
    final row = {
      'number': f.number,
      'block': f.block,
      'flat_type': f.type,
      'sqft': f.sqft,
      'occupancy': _occupancyDb(f.occupancy),
    };
    final flatId = f.id == null ? (await db.from('flats').insert(row).select('id').single())['id'] as String : f.id!;
    if (f.id != null) {
      await db.from('flats').update(row).eq('id', flatId);
    }
    await db.rpc(
      'save_flat_vehicles',
      params: {'p_flat': flatId, 'p_car': f.carNumber, 'p_bike': f.bikeNumber, 'p_slot': f.parkingSlot},
    );
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
            birthDate: DateTime.tryParse(r['date_of_birth'] as String? ?? ''),
            designations: List<String>.from(r['designations'] as List? ?? const []),
            monitorCategories: List<String>.from(r['monitor_categories'] as List? ?? const []),
            monitorFrom: DateTime.tryParse(r['monitor_from'] as String? ?? ''),
            monitorUntil: DateTime.tryParse(r['monitor_until'] as String? ?? ''),
            assignedBy: r['assigned_by'] as String?,
            since: DateTime.tryParse(r['since'] as String? ?? '')?.toLocal(),
            supportFlags: [
              for (final flag in List<String>.from(r['support_flags'] as List? ?? const []))
                if (_supportFlagFromDb(flag) case final modelFlag?) modelFlag,
            ],
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
      'p_birth_date': _date(p.birthDate),
      'p_from': _date(p.monitorFrom),
      'p_until': _date(p.monitorUntil),
      'p_support_flags': [for (final flag in p.supportFlags) _supportFlagDb(flag)],
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

  static Future<void> setBirthDate(Person person, DateTime birthDate) => db.rpc(
    'set_member_birth_date',
    params: {'p_kind': person.invited ? 'invited' : 'member', 'p_id': person.id, 'p_birth_date': _date(birthDate)},
  );

  /// Returns 'removed', or 'pending_approval' for committee/staff roles that need President approval.
  static Future<String> remove(Person p, String reason) async =>
      await db.rpc(
        'revoke_member_role',
        params: {'p_kind': p.invited ? 'invited' : 'member', 'p_id': p.id, 'p_reason': reason.trim()},
      ) as String? ??
      'removed';

  static Future<void> sendInviteEmail(String email) =>
      db.functions.invoke('send-invite-email', body: {'email': email.trim().toLowerCase()});

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
    final prepared = await prepareUpload(bytes, ext);
    final assoc = await db.rpc('my_association') as String;
    final path = '$assoc/${flatId ?? 'none'}/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage
        .from(_bucket)
        .uploadBinary(path, prepared.bytes, fileOptions: FileOptions(contentType: prepared.contentType));
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

String _supportFlagDb(MemberSupportFlag flag) => switch (flag) {
  MemberSupportFlag.wheelchairAssisted => 'wheelchair_assisted',
};

MemberSupportFlag? _supportFlagFromDb(String flag) => switch (flag) {
  'wheelchair_assisted' => MemberSupportFlag.wheelchairAssisted,
  _ => null,
};
