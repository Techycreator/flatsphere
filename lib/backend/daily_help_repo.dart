import 'backend.dart';

typedef DailyHelp = ({
  String id,
  String name,
  String kind,
  String? phone,
  List<String> flatIds,
  String flats,
  List<int> days,
  String? start,
  String? end,
  bool notify,
  String code,
  bool inside,
});

typedef DailyHelpVisit = ({DateTime inAt, DateTime? outAt, String? guard});

const dailyHelpKinds = ['maid', 'cook', 'driver', 'cleaner', 'newspaper', 'milk', 'other'];

class DailyHelpRepo {
  static String? _hm(Object? t) => t == null ? null : (t as String).substring(0, 5);

  /// Active passes visible to the current user (RLS: gate staff/committee see all, flats see their own).
  static Future<List<DailyHelp>> load({required String associationId}) =>
      AssociationContext.run(() async {
        if (await db.rpc('my_association') != associationId) {
          throw StateError('The active association changed. Reload daily help to continue.');
        }
        final rows = await db
            .from('daily_help')
            .select()
            .eq('association_id', associationId)
            .eq('active', true)
            .order('name');
        final since = DateTime.now().subtract(const Duration(hours: 20)).toUtc().toIso8601String();
        final open = await db
            .from('daily_help_log')
            .select('help_id')
            .eq('association_id', associationId)
            .isFilter('checked_out_at', null)
            .gte('checked_in_at', since);
        final inside = {for (final r in open) r['help_id'] as String};
        final ids = {for (final r in rows) ...(r['flat_ids'] as List).cast<String>()};
        final numbers = <String, String>{
          if (ids.isNotEmpty)
            for (final f in await db
                .from('flats')
                .select('id, number')
                .eq('association_id', associationId)
                .inFilter('id', ids.toList()))
              f['id'] as String: f['number'] as String,
        };
        return [
          for (final r in rows)
            (
              id: r['id'] as String,
              name: r['name'] as String,
              kind: r['kind'] as String,
              phone: r['phone'] as String?,
              flatIds: (r['flat_ids'] as List).cast<String>(),
              flats: (r['flat_ids'] as List).isEmpty
                  ? 'All flats'
                  : [for (final id in (r['flat_ids'] as List).cast<String>()) numbers[id] ?? '?'].join(', '),
              days: (r['days'] as List).cast<int>(),
              start: _hm(r['start_time']),
              end: _hm(r['end_time']),
              notify: r['notify'] as bool,
              code: r['pass_code'] as String,
              inside: inside.contains(r['id']),
            ),
        ];
      });

  static Future<List<DailyHelpVisit>> visits(String id) async {
    final rows = await db
        .from('daily_help_log')
        .select('checked_in_at, checked_out_at, guard_name')
        .eq('help_id', id)
        .order('checked_in_at', ascending: false)
        .limit(120);
    return [
      for (final r in rows)
        (
          inAt: DateTime.parse(r['checked_in_at'] as String).toLocal(),
          outAt: r['checked_out_at'] == null ? null : DateTime.parse(r['checked_out_at'] as String).toLocal(),
          guard: r['guard_name'] as String?,
        ),
    ];
  }

  static Future<void> save({
    String? id,
    String? flatId,
    required String name,
    required String kind,
    String phone = '',
    required List<int> days,
    String? start,
    String? end,
    bool notify = true,
  }) => db.rpc(
    'save_daily_help',
    params: {
      'p_id': id,
      'p_flat': flatId,
      'p_name': name,
      'p_kind': kind,
      'p_phone': phone,
      'p_days': days,
      'p_start': start,
      'p_end': end,
      'p_notify': notify,
    },
  );

  /// With [flatId]: removes the pass from that flat. Without: blocks it for the whole association (committee).
  static Future<void> remove(String id, {String? flatId}) =>
      db.rpc('remove_daily_help', params: {'p_id': id, 'p_flat': flatId});

  static Future<String> entry(String id, {required bool checkIn, DateTime? at}) async => await db.rpc(
    'gate_daily_help',
    params: {'p_id': id, 'p_in': checkIn, 'p_at': (at ?? DateTime.now()).toUtc().toIso8601String()},
  ) as String;

  static Map<String, dynamic> toJson(DailyHelp h) => {
    'id': h.id,
    'name': h.name,
    'kind': h.kind,
    'phone': h.phone,
    'flatIds': h.flatIds,
    'flats': h.flats,
    'days': h.days,
    'start': h.start,
    'end': h.end,
    'notify': h.notify,
    'code': h.code,
    'inside': h.inside,
  };

  static DailyHelp fromJson(Map<String, dynamic> m) => (
    id: m['id'] as String,
    name: m['name'] as String,
    kind: m['kind'] as String,
    phone: m['phone'] as String?,
    flatIds: (m['flatIds'] as List).cast<String>(),
    flats: m['flats'] as String,
    days: (m['days'] as List).cast<int>(),
    start: m['start'] as String?,
    end: m['end'] as String?,
    notify: m['notify'] as bool,
    code: m['code'] as String,
    inside: m['inside'] as bool,
  );

  /// Same rule the server applies, used when the gate phone is offline.
  static bool allowedNow(DailyHelp h, DateTime t) {
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return h.days.contains(t.weekday) &&
        (h.start == null || hm.compareTo(h.start!) >= 0) &&
        (h.end == null || hm.compareTo(h.end!) <= 0);
  }
}
