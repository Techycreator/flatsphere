import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final role = ref.watch(sessionProvider)!.activeRole;
    final now = DateTime.now();
    final all = ref.watch(meetingsProvider);
    final visible = all.where((m) => role.isCommittee || m.type == 'General Body').toList();
    final upcoming = visible.where((m) => m.at.isAfter(now)).toList();
    final past = visible.where((m) => !m.at.isAfter(now)).toList();
    final canSchedule = role == Role.secretary || role == Role.president;

    return PageBody(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.meetings,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (canSchedule)
              FilledButton.icon(
                onPressed: () => _schedule(context, ref),
                icon: const Icon(Icons.event),
                label: const Text('Schedule meeting'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Upcoming', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final m in upcoming) _MeetingCard(meeting: m, canManage: canSchedule),
        const SizedBox(height: 16),
        Text('Past', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final m in past) _MeetingCard(meeting: m, canManage: canSchedule),
      ],
    );
  }

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    var type = 'Executive Committee';
    var mode = MeetingMode.hybrid;
    var platform = 'Google Meet';
    final title = TextEditingController(text: 'EC meeting – special');
    final agenda = TextEditingController(text: 'Lift AMC renewal\nCCTV upgrade quotes');
    final when = DateTime.now().add(const Duration(days: 7));
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Schedule meeting'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Meeting type'),
                    items: [
                      for (final t in const ['Executive Committee', 'Office bearers', 'Staff meeting', 'General Body'])
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<MeetingMode>(
                    segments: const [
                      ButtonSegment(value: MeetingMode.inPerson, label: Text('In person')),
                      ButtonSegment(value: MeetingMode.online, label: Text('Online')),
                      ButtonSegment(value: MeetingMode.hybrid, label: Text('Hybrid')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => setState(() => mode = s.first),
                  ),
                  if (mode != MeetingMode.inPerson) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: platform,
                      decoration: const InputDecoration(labelText: 'Platform (link auto-generated)'),
                      items: [
                        for (final p in const ['Google Meet', 'Zoom', 'Microsoft Teams'])
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => setState(() => platform = v!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: agenda,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Agenda (one per line)'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Invites go to all $type members by email (calendar invite), WhatsApp and app notification. Date: ${dateTimeFmt.format(DateTime(when.year, when.month, when.day, 19, 30))}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                ref
                    .read(meetingsProvider.notifier)
                    .add(
                      Meeting(
                        id: 'M-${DateTime.now().millisecond}',
                        type: type,
                        title: title.text,
                        at: DateTime(when.year, when.month, when.day, 19, 30),
                        mode: mode,
                        platform: mode == MeetingMode.inPerson ? null : platform,
                        venue: mode == MeetingMode.online ? null : 'Association office',
                        agenda: agenda.text.split('\n').where((x) => x.trim().isNotEmpty).toList(),
                        invited: type == 'General Body' ? 120 : 9,
                      ),
                    );
                Navigator.pop(ctx);
                toast(context, 'Meeting scheduled and invites sent');
              },
              child: const Text('Send invites'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingCard extends ConsumerWidget {
  const _MeetingCard({required this.meeting, required this.canManage});
  final Meeting meeting;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = meeting;
    final upcoming = m.at.isAfter(DateTime.now());
    final modeText = switch (m.mode) {
      MeetingMode.inPerson => 'In person · ${m.venue}',
      MeetingMode.online => 'Online · ${m.platform}',
      MeetingMode.hybrid => 'Hybrid · ${m.venue} + ${m.platform}',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pill(m.type, color: Theme.of(context).colorScheme.primary),
                const Spacer(),
                Text(dateTimeFmt.format(m.at), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(m.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(modeText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final a in m.agenda) Text('• $a'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill('${m.accepted} accepted', color: AppColors.green),
                Pill('${m.tentative} tentative', color: AppColors.amber),
                Pill('${m.declined} declined', color: AppColors.red),
                Pill('${m.invited - m.accepted - m.tentative - m.declined} no reply', color: Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 12),
            if (upcoming)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<Rsvp>(
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(value: Rsvp.accepted, label: Text('Accept')),
                      ButtonSegment(value: Rsvp.tentative, label: Text('Tentative')),
                      ButtonSegment(value: Rsvp.declined, label: Text('Decline')),
                    ],
                    selected: m.myRsvp == Rsvp.pending ? <Rsvp>{} : {m.myRsvp},
                    onSelectionChanged: (s) {
                      if (s.isNotEmpty) ref.read(meetingsProvider.notifier).rsvp(m.id, s.first);
                    },
                  ),
                  if (m.platform != null)
                    TextButton.icon(
                      onPressed: () => toast(context, 'Opens ${m.platform} link'),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Join link'),
                    ),
                  if (canManage)
                    TextButton.icon(
                      onPressed: () => toast(context, 'Reschedule: pick new date; all invitees notified'),
                      icon: const Icon(Icons.update),
                      label: const Text('Reschedule'),
                    ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Pill(
                    m.minutesStatus ?? 'Minutes pending',
                    color: m.minutesStatus != null ? AppColors.green : AppColors.amber,
                    icon: Icons.description_outlined,
                  ),
                  if (canManage && m.minutesStatus == null)
                    FilledButton.tonalIcon(
                      onPressed: () => _aiMinutes(context, m),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Draft minutes with AI'),
                    ),
                  if (m.minutesStatus != null)
                    TextButton(onPressed: () => toast(context, 'Opens locked MOM PDF'), child: const Text('View MOM')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _aiMinutes(BuildContext context, Meeting m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI draft minutes'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Source: Google Meet transcript (uploaded)', style: TextStyle(fontSize: 12)),
                const Divider(),
                Text(m.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('Attendees: 8 of 9 EC members (quorum met)'),
                const SizedBox(height: 8),
                const Text('Decisions', style: TextStyle(fontWeight: FontWeight.w600)),
                for (var i = 0; i < m.agenda.length; i++)
                  Text('D${i + 1}. ${m.agenda[i]} – approved (6 for, 1 against, 1 abstain)'),
                const SizedBox(height: 8),
                const Text('Action items', style: TextStyle(fontWeight: FontWeight.w600)),
                const Text('A1. Treasurer to collect 3 quotes – due in 14 days'),
                const Text('A2. Secretary to circulate notice to owners – due in 7 days'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              toast(context, 'Draft saved. Circulated to attendees for comments, then President approval.');
            },
            child: const Text('Save as draft'),
          ),
        ],
      ),
    );
  }
}
