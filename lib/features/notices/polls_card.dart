import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend.dart' show backendEnabled;
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/polls_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final pollsProvider = FutureProvider.autoDispose<List<Poll>>(
  (ref) => backendEnabled ? PollsRepo.list() : Future.value(const []),
);

class PollsCard extends ConsumerWidget {
  const PollsCard({super.key});

  static const _creators = {
    Role.admin,
    Role.president,
    Role.vicePresident,
    Role.secretary,
    Role.jointSecretary,
    Role.ecMember,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendEnabled) return const SizedBox.shrink();
    final role = ref.watch(sessionProvider)?.activeRole;
    final polls = ref.watch(pollsProvider).value ?? const [];
    Future<void> run(Future<void> Function() f, String done) async {
      try {
        await f();
        ref.invalidate(pollsProvider);
        if (context.mounted) toast(context, done);
      } catch (e) {
        if (context.mounted) toast(context, friendlyError(e));
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Polls', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_creators.contains(role))
                  TextButton.icon(
                    onPressed: () => _create(context, run),
                    icon: const Icon(Icons.add),
                    label: const Text('New poll'),
                  ),
              ],
            ),
            if (polls.isEmpty) const Text('No polls yet.'),
            for (final p in polls) ...[
              const Divider(),
              Text(p.question, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${p.closesAt.isBefore(DateTime.now()) ? 'Closed' : 'Closes ${dateTimeFmt.format(p.closesAt)}'} · by ${p.by} · '
                '${p.votes.fold(0, (a, b) => a + b)} vote(s) · anonymous',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (var i = 0; i < p.options.length; i++)
                () {
                  final total = p.votes.fold(0, (a, b) => a + b);
                  final open = p.closesAt.isAfter(DateTime.now()) && p.myVote == null;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.myVote == i ? Icons.check_circle : Icons.radio_button_unchecked),
                    title: Text(p.options[i]),
                    subtitle: LinearProgressIndicator(value: total == 0 ? 0 : p.votes[i] / total),
                    trailing: Text('${p.votes[i]}'),
                    onTap: open ? () => run(() => PollsRepo.vote(p.id, i), 'Vote recorded') : null,
                  );
                }(),
              if (p.closesAt.isAfter(DateTime.now()) &&
                  const {Role.admin, Role.president, Role.secretary}.contains(role))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => run(() => PollsRepo.close(p.id), 'Poll closed'),
                    child: const Text('Close poll'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, Future<void> Function(Future<void> Function(), String) run) async {
    final q = TextEditingController();
    final opts = [TextEditingController(), TextEditingController()];
    var days = 7;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New poll'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: q,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Question *'),
                  ),
                  for (var i = 0; i < opts.length; i++)
                    TextField(
                      controller: opts[i],
                      decoration: InputDecoration(labelText: 'Option ${i + 1}${i < 2 ? ' *' : ''}'),
                    ),
                  if (opts.length < 8)
                    TextButton(
                      onPressed: () => set(() => opts.add(TextEditingController())),
                      child: const Text('Add option'),
                    ),
                  DropdownButtonFormField<int>(
                    initialValue: days,
                    decoration: const InputDecoration(labelText: 'Open for'),
                    items: [
                      for (final d in const [1, 3, 7, 14, 30]) DropdownMenuItem(value: d, child: Text('$d day(s)')),
                    ],
                    onChanged: (v) => days = v ?? 7,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
          ],
        ),
      ),
    );
    final options = [
      for (final o in opts)
        if (o.text.trim().isNotEmpty) o.text.trim(),
    ];
    if (ok != true) return;
    if (q.text.trim().length < 3 || options.length < 2) {
      if (context.mounted) toast(context, 'Enter a question and at least 2 options');
      return;
    }
    await run(
      () => PollsRepo.create(q.text, options, DateTime.now().add(Duration(days: days))),
      'Poll published. Members are notified.',
    );
  }
}
