import 'backend.dart';

typedef Poll = ({
  String id,
  String question,
  List<String> options,
  DateTime closesAt,
  String by,
  List<int> votes,
  int? myVote,
});

class PollsRepo {
  static Future<List<Poll>> list() async {
    final rows = await db
        .from('polls')
        .select('id, question, options, closes_at, created_by_name')
        .order('created_at', ascending: false)
        .limit(30);
    final results = await db.rpc('poll_results') as List;
    final mine = await db.from('poll_votes').select('poll_id, option_index');
    final my = {for (final r in mine) r['poll_id'] as String: r['option_index'] as int};
    return [
      for (final r in rows)
        () {
          final options = List<String>.from(r['options'] as List);
          final votes = List<int>.filled(options.length, 0);
          for (final x in results.cast<Map>()) {
            final i = x['option_index'] as int;
            if (x['poll_id'] == r['id'] && i < votes.length) votes[i] = (x['votes'] as num).toInt();
          }
          return (
            id: r['id'] as String,
            question: r['question'] as String,
            options: options,
            closesAt: DateTime.parse(r['closes_at'] as String).toLocal(),
            by: r['created_by_name'] as String? ?? '',
            votes: votes,
            myVote: my[r['id']],
          );
        }(),
    ];
  }

  static Future<void> create(String question, List<String> options, DateTime closesAt) => db.from('polls').insert({
    'question': question.trim(),
    'options': [for (final o in options) o.trim()],
    'closes_at': closesAt.toUtc().toIso8601String(),
  });

  static Future<void> vote(String id, int option) =>
      db.rpc('cast_poll_vote', params: {'p_poll': id, 'p_option': option});

  static Future<void> close(String id) =>
      db.from('polls').update({'closes_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
}
