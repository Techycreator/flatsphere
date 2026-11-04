import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, PostgrestException, StorageException;

import 'backend.dart';
import '../models/models.dart';
import 'daily_help_repo.dart';
import 'directory_repo.dart' show friendlyError;
import 'gate_repo.dart';
import 'visitor_repo.dart';

/// True when [e] looks like lost network rather than a server refusal.
bool isOffline(Object e) =>
    e is! PostgrestException &&
    e is! AuthException &&
    e is! StorageException &&
    e is! ArgumentError &&
    e is! StateError;

/// Gate actions saved on the phone while offline, sent in order when the network is back.
class GateOffline {
  static const _legacyQueueKey = 'gate_queue';
  static String _queueKey(String associationId) => 'gate_queue_$associationId';
  static String _cacheKey(String associationId) => 'gate_cache_$associationId';
  static String _helpKey(String associationId) => 'gate_help_cache_$associationId';
  static String guardKey(String associationId) => 'gate_guard_on_duty_$associationId';

  static Future<List<Map<String, dynamic>>> queue(String associationId) async {
    final p = await SharedPreferences.getInstance();
    return [
      for (final s in p.getStringList(_queueKey(associationId)) ?? const <String>[])
        jsonDecode(s) as Map<String, dynamic>,
    ];
  }

  static Future<List<Map<String, dynamic>>> legacyQueue() async {
    final p = await SharedPreferences.getInstance();
    return [
      for (final s in p.getStringList(_legacyQueueKey) ?? const <String>[])
        jsonDecode(s) as Map<String, dynamic>,
    ];
  }

  static Future<int> recoverLegacyQueue(String associationId) =>
      AssociationContext.run(() => _recoverLegacyQueue(associationId, recoverUnassigned: true));

  static Future<int> recoverAssignedLegacyQueue(String associationId) =>
      AssociationContext.run(() => _recoverLegacyQueue(associationId, recoverUnassigned: false));

  static Future<int> _recoverLegacyQueue(String associationId, {required bool recoverUnassigned}) async {
    final p = await SharedPreferences.getInstance();
    final legacy = p.getStringList(_legacyQueueKey) ?? const <String>[];
    if (legacy.isEmpty) return 0;
    final scoped = p.getStringList(_queueKey(associationId)) ?? const <String>[];
    final assignments = <String>[];
    final updatedLegacy = <String>[];
    final deferred = <String>[];
    var changed = false;
    var mismatchedAssigned = false;
    for (var index = 0; index < legacy.length; index++) {
      final action = jsonDecode(legacy[index]) as Map<String, dynamic>;
      final assignedAssociation = action['_legacy_recovery_association'];
      if (assignedAssociation != null && assignedAssociation != associationId) {
        if (recoverUnassigned) {
          mismatchedAssigned = true;
        }
        deferred.add(legacy[index]);
        updatedLegacy.add(legacy[index]);
        continue;
      }
      if (assignedAssociation == null && !recoverUnassigned) {
        deferred.add(legacy[index]);
        updatedLegacy.add(legacy[index]);
        continue;
      }
      final recoveryId =
          action['_legacy_recovery_id'] as String? ??
          sha256.convert(utf8.encode('$index:${legacy[index]}')).toString();
      if (assignedAssociation == null || action['_legacy_recovery_id'] != recoveryId) {
        changed = true;
      }
      final assigned = jsonEncode({
        ...action,
        '_legacy_recovery_association': associationId,
        '_legacy_recovery_id': recoveryId,
      });
      assignments.add(assigned);
      updatedLegacy.add(assigned);
    }
    if (recoverUnassigned && assignments.isEmpty && mismatchedAssigned) {
      throw StateError('These older gate entries were already assigned to another association.');
    }
    if (changed && !await p.setStringList(_legacyQueueKey, updatedLegacy)) {
      throw StateError('Could not save the legacy gate entry assignment.');
    }

    final recoveredIds = {
      for (final s in scoped)
        if ((jsonDecode(s) as Map<String, dynamic>)['_legacy_recovery_id'] case final String id) id,
    };
    final now = DateTime.now().toIso8601String();
    final recovered = <String>[];
    for (final s in assignments) {
      final action = jsonDecode(s) as Map<String, dynamic>;
      final recoveryId = action['_legacy_recovery_id'] as String;
      if (!recoveredIds.add(recoveryId)) continue;
      recovered.add(
        jsonEncode({
          ...action,
          'association_id': associationId,
          'at': action['at'] ?? now,
          '_legacy_recovery_id': recoveryId,
        }),
      );
    }
    if (recovered.isNotEmpty && !await p.setStringList(_queueKey(associationId), [...scoped, ...recovered])) {
      throw StateError('Could not save legacy gate entries.');
    }
    final cleared = deferred.isEmpty
        ? await p.remove(_legacyQueueKey)
        : await p.setStringList(_legacyQueueKey, deferred);
    if (!cleared) {
      throw StateError('Could not clear the recovered legacy gate entries.');
    }
    return recovered.length;
  }

  static Future<void> _save(String associationId, List<Map<String, dynamic>> q) async =>
      (await SharedPreferences.getInstance()).setStringList(_queueKey(associationId), [
        for (final m in q) jsonEncode(m),
      ]);

  static Future<void> add(String associationId, Map<String, dynamic> action) =>
      AssociationContext.run(() async {
        await _save(associationId, [
          ...await queue(associationId),
          {...action, 'association_id': associationId, 'at': DateTime.now().toIso8601String()},
        ]);
      });

  /// Returns how many were sent and the messages for ones the server refused. Stops at the first network error.
  static Future<(int, List<String>)> flush(String associationId) =>
      AssociationContext.run(() => _flush(associationId));

  static Future<(int, List<String>)> _flush(String associationId) async {
    if (await db.rpc('my_association') != associationId) return (0, <String>[]);
    final q = await queue(associationId);
    var sent = 0;
    final failed = <String>[];
    while (q.isNotEmpty) {
      final a = q.first;
      if (a['association_id'] != associationId) {
        failed.add('${a['label'] ?? 'Gate action'}: saved for a different association');
        q.removeAt(0);
        await _save(associationId, q);
        continue;
      }
      try {
        switch (a['kind']) {
          case 'walkin':
            var requestId = a['request_id'] as String?;
            if (requestId == null || requestId.isEmpty) {
              requestId = GateRepo.newWalkInRequestId();
              a['request_id'] = requestId;
              await _save(associationId, q);
            }
            final id = await GateRepo.walkIn(
              requestId: requestId,
              flat: a['flat'] as String,
              name: a['name'] as String,
              phone: a['phone'] as String? ?? '',
              type: a['type'] as String? ?? 'guest',
              vehicle: a['vehicle'] as String? ?? '',
              mode: a['mode'] as String? ?? 'ask',
              note: a['note'] as String? ?? '',
              meet: a['meet'] as String? ?? '',
              staffId: a['staff_id'] as String?,
              occurredAt: a['at'] is String ? DateTime.tryParse(a['at'] as String) : null,
            );
            final photo = a['photo'] as String?;
            if (photo != null) {
              try {
                await GateRepo.attachPhoto(id, base64Decode(photo));
              } catch (_) {}
            }
          case 'lobby':
            await GateRepo.lobbyDrop(
              a['id'] as String,
              occurredAt: a['at'] is String ? DateTime.tryParse(a['at'] as String) : null,
            );
          case 'help':
            await DailyHelpRepo.entry(
              a['id'] as String,
              checkIn: a['in'] as bool,
              at: DateTime.parse(a['at'] as String),
            );
          case 'verify':
            await VisitorRepo.verify(
              a['id'] as String,
              a['action'] == 'check_in' ? VisitorStatus.checkedIn : VisitorStatus.checkedOut,
            );
        }
        sent++;
      } catch (e) {
        if (isOffline(e)) break;
        failed.add('${a['label']}: ${friendlyError(e)}');
      }
      q.removeAt(0);
      await _save(associationId, q);
    }
    return (sent, failed);
  }

  static Future<void> cache(String associationId, List<GateVisitor> list) async =>
      (await SharedPreferences.getInstance()).setString(
    _cacheKey(associationId),
    jsonEncode([
      for (final v in list)
        {
          'id': v.id,
          'guest': v.guest,
          'phone': v.phone,
          'flat': v.flat,
          'status': v.status,
          'approval': v.approval,
          'type': v.type,
          'note': v.note,
          'vehicle': v.vehicle,
          'pass': v.passCode,
          'arrival': v.arrival.toIso8601String(),
        },
    ]),
  );

  static Future<List<GateVisitor>> cached(String associationId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_cacheKey(associationId));
    if (raw == null) return const [];
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        (
          id: m['id'] as String,
          guest: m['guest'] as String,
          phone: m['phone'] as String?,
          flat: m['flat'] as String,
          status: m['status'] as String,
          approval: m['approval'] as String,
          type: m['type'] as String,
          note: m['note'] as String? ?? '',
          vehicle: m['vehicle'] as String?,
          passCode: m['pass'] as String?,
          arrival: DateTime.parse(m['arrival'] as String),
          photoPath: null,
          guardName: null,
        ),
    ];
  }

  static String _flatsKey(String associationId) => 'gate_flats_cache_$associationId';

  static String _staffKey(String associationId) => 'gate_staff_cache_$associationId';

  static Future<void> cacheStaff(
    String associationId,
    List<({String id, String name, String role, String mobile})> staff,
  ) async => (await SharedPreferences.getInstance()).setString(
    _staffKey(associationId),
    jsonEncode([for (final s in staff) {'id': s.id, 'name': s.name, 'role': s.role, 'mobile': s.mobile}]),
  );

  static Future<List<({String id, String name, String role, String mobile})>> cachedStaff(String associationId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_staffKey(associationId));
    if (raw == null) return const [];
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        (
          id: m['id'] as String? ?? '',
          name: m['name'] as String,
          role: m['role'] as String,
          mobile: m['mobile'] as String,
        ),
    ];
  }

  static Future<void> cacheFlats(String associationId, List<String> flats) async =>
      (await SharedPreferences.getInstance()).setStringList(_flatsKey(associationId), flats);

  static Future<List<String>> cachedFlats(String associationId) async =>
      (await SharedPreferences.getInstance()).getStringList(_flatsKey(associationId)) ?? const [];

  static Future<void> cacheHelp(String associationId, List<DailyHelp> list) async =>
      (await SharedPreferences.getInstance()).setString(
    _helpKey(associationId),
    jsonEncode([for (final h in list) DailyHelpRepo.toJson(h)]),
  );

  static Future<List<DailyHelp>> cachedHelp(String associationId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_helpKey(associationId));
    if (raw == null) return const [];
    return [for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) DailyHelpRepo.fromJson(m)];
  }
}
