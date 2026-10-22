import '../models/models.dart';
import 'backend.dart';

class MeetingsRepo {
  static Future<List<Meeting>> load() async {
    final rows = await db.rpc('list_association_meetings') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        Meeting(
          id: row['id'] as String,
          type: row['meeting_type'] as String,
          title: row['title'] as String,
          at: DateTime.parse(row['starts_at'] as String).toLocal(),
          mode: switch (row['meeting_mode']) {
            'online' => MeetingMode.online,
            'hybrid' => MeetingMode.hybrid,
            _ => MeetingMode.inPerson,
          },
          platform: row['platform'] as String?,
          venue: row['venue'] as String?,
          agenda: List<String>.from(row['agenda'] as List? ?? const []),
          invited: (row['invited_count'] as num?)?.toInt() ?? 0,
          accepted: (row['accepted_count'] as num?)?.toInt() ?? 0,
          tentative: (row['tentative_count'] as num?)?.toInt() ?? 0,
          declined: (row['declined_count'] as num?)?.toInt() ?? 0,
          myRsvp: switch (row['my_rsvp']) {
            'accepted' => Rsvp.accepted,
            'tentative' => Rsvp.tentative,
            'declined' => Rsvp.declined,
            _ => Rsvp.pending,
          },
          minutesStatus: row['minutes_status'] as String?,
          minutesText: row['minutes_text'] as String?,
        ),
    ];
  }

  static Future<String> create(Meeting meeting) async => await db.rpc(
    'create_association_meeting',
    params: {
      'p_type': meeting.type,
      'p_title': meeting.title.trim(),
      'p_starts_at': meeting.at.toUtc().toIso8601String(),
      'p_mode': switch (meeting.mode) {
        MeetingMode.inPerson => 'inPerson',
        MeetingMode.online => 'online',
        MeetingMode.hybrid => 'hybrid',
      },
      'p_platform': meeting.platform,
      'p_venue': meeting.venue,
      'p_agenda': meeting.agenda,
    },
  ) as String;

  static Future<void> rsvp(String id, Rsvp rsvp) => db.rpc('set_meeting_rsvp', params: {
    'p_meeting': id,
    'p_status': switch (rsvp) {
      Rsvp.accepted => 'accepted',
      Rsvp.tentative => 'tentative',
      Rsvp.declined => 'declined',
      Rsvp.pending => throw ArgumentError.value(rsvp, 'rsvp', 'Cannot submit a pending RSVP'),
    },
  });

  static Future<void> saveMinutes(String id, String text) =>
      db.rpc('save_meeting_minutes', params: {'p_meeting': id, 'p_text': text});

  static Future<void> submitMinutes(String id) =>
      db.rpc('submit_meeting_minutes', params: {'p_meeting': id});

  static Future<void> approveMinutes(String id) =>
      db.rpc('approve_meeting_minutes', params: {'p_meeting': id});

  static Future<void> reschedule(String id, DateTime at) => db.rpc('reschedule_association_meeting', params: {
    'p_meeting': id,
    'p_starts_at': at.toUtc().toIso8601String(),
  });
}
