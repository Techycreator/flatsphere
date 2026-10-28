import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, PostgrestException, StorageException;

import '../models/models.dart';
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
  static const _queueKey = 'gate_queue', _cacheKey = 'gate_cache', guardKey = 'gate_guard_on_duty';

  static Future<List<Map<String, dynamic>>> queue() async {
    final p = await SharedPreferences.getInstance();
    return [for (final s in p.getStringList(_queueKey) ?? const <String>[]) jsonDecode(s) as Map<String, dynamic>];
  }

  static Future<void> _save(List<Map<String, dynamic>> q) async =>
      (await SharedPreferences.getInstance()).setStringList(_queueKey, [for (final m in q) jsonEncode(m)]);

  static Future<void> add(Map<String, dynamic> action) async => _save([
    ...await queue(),
    {...action, 'at': DateTime.now().toIso8601String()},
  ]);

  /// Returns how many were sent and the messages for ones the server refused. Stops at the first network error.
  static Future<(int, List<String>)> flush() async {
    final q = await queue();
    var sent = 0;
    final failed = <String>[];
    while (q.isNotEmpty) {
      final a = q.first;
      try {
        switch (a['kind']) {
          case 'walkin':
            final id = await GateRepo.walkIn(
              flat: a['flat'] as String,
              name: a['name'] as String,
              phone: a['phone'] as String? ?? '',
              type: a['type'] as String? ?? 'guest',
              vehicle: a['vehicle'] as String? ?? '',
            );
            final photo = a['photo'] as String?;
            if (photo != null) {
              try {
                await GateRepo.attachPhoto(id, base64Decode(photo));
              } catch (_) {}
            }
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
      await _save(q);
    }
    return (sent, failed);
  }

  static Future<void> cache(List<GateVisitor> list) async => (await SharedPreferences.getInstance()).setString(
    _cacheKey,
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
          'vehicle': v.vehicle,
          'pass': v.passCode,
          'arrival': v.arrival.toIso8601String(),
        },
    ]),
  );

  static Future<List<GateVisitor>> cached() async {
    final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
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
          vehicle: m['vehicle'] as String?,
          passCode: m['pass'] as String?,
          arrival: DateTime.parse(m['arrival'] as String),
          photoPath: null,
          guardName: null,
        ),
    ];
  }
}
