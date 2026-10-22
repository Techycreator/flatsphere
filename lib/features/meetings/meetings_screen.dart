import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
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
    final meetings = ref.watch(meetingsProvider);
    final now = DateTime.now();
    final visible = meetings.where((meeting) => role.isCommittee || meeting.type == 'General Body').toList();
    final upcoming = visible.where((meeting) => meeting.at.isAfter(now)).toList();
    final past = visible.where((meeting) => !meeting.at.isAfter(now)).toList();
    final canManage = role == Role.admin || role == Role.secretary || role == Role.president;

    return PageBody(
      children: [
        Row(
          children: [
            Expanded(child: Text(l.meetings, style: Theme.of(context).textTheme.headlineSmall)),
            if (canManage)
              FilledButton.icon(
                onPressed: () => _schedule(context, ref),
                icon: const Icon(Icons.event),
                label: Text(l.scheduleMeeting),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l.meetingsUpcoming, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (upcoming.isEmpty) EmptyState(l.noUpcomingMeetings, icon: Icons.event_outlined),
        for (final meeting in upcoming)
          _MeetingCard(meeting: meeting, canManage: canManage, canApproveMinutes: role == Role.president),
        const SizedBox(height: 16),
        Text(l.meetingsPast, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (past.isEmpty) EmptyState(l.noPastMeetings, icon: Icons.history),
        for (final meeting in past)
          _MeetingCard(meeting: meeting, canManage: canManage, canApproveMinutes: role == Role.president),
      ],
    );
  }

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    var type = 'Executive Committee';
    var mode = MeetingMode.hybrid;
    var platform = 'Google Meet';
    var at = DateTime.now().add(const Duration(days: 7));
    final title = TextEditingController(text: 'EC meeting – special');
    final agenda = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.scheduleMeeting),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(labelText: l.meetingType),
                    items: [
                      for (final value in const ['Executive Committee', 'Office bearers', 'Staff meeting', 'General Body'])
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) => setDialogState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: title, decoration: InputDecoration(labelText: '${l.meetingTitle} *')),
                  const SizedBox(height: 12),
                  SegmentedButton<MeetingMode>(
                    segments: const [
                      ButtonSegment(value: MeetingMode.inPerson, label: Text(l.inPerson)),
                      ButtonSegment(value: MeetingMode.online, label: Text(l.online)),
                      ButtonSegment(value: MeetingMode.hybrid, label: Text(l.hybrid)),
                    ],
                    selected: {mode},
                    onSelectionChanged: (values) => setDialogState(() => mode = values.first),
                  ),
                  if (mode != MeetingMode.inPerson) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: platform,
                      decoration: InputDecoration(labelText: l.platform),
                      items: [
                        for (final value in const ['Google Meet', 'Zoom', 'Microsoft Teams'])
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
                      onChanged: (value) => setDialogState(() => platform = value ?? platform),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: at,
                        firstDate: DateUtils.dateOnly(DateTime.now()),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (date == null || !dialogContext.mounted) return;
                      final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.fromDateTime(at));
                      if (time != null && dialogContext.mounted) {
                        setDialogState(() => at = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(dateTimeFmt.format(at)),
                  ),
                  TextField(controller: agenda, maxLines: 3, decoration: InputDecoration(labelText: l.meetingAgenda)),
                  const SizedBox(height: 8),
                  Text(l.meetingSaved, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l.cancel)),
            FilledButton(
              onPressed: title.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, true),
              child: Text(l.submit),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) {
      title.dispose();
      agenda.dispose();
      return;
    }
    try {
      await ref.read(meetingsProvider.notifier).add(
        Meeting(
          id: backendEnabled ? '' : 'M-${DateTime.now().microsecondsSinceEpoch}',
          type: type,
          title: title.text.trim(),
          at: at,
          mode: mode,
          platform: mode == MeetingMode.inPerson ? null : platform,
          venue: mode == MeetingMode.online ? null : 'Association office',
          agenda: agenda.text.split('\n').where((line) => line.trim().isNotEmpty).toList(),
        ),
      );
      if (context.mounted) toast(context, l.meetingSaved);
    } catch (error) {
      if (context.mounted) toast(context, '$error');
    } finally {
      title.dispose();
      agenda.dispose();
    }
  }
}

class _MeetingCard extends ConsumerWidget {
  const _MeetingCard({required this.meeting, required this.canManage, required this.canApproveMinutes});

  final Meeting meeting;
  final bool canManage;
  final bool canApproveMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final meeting = this.meeting;
    final upcoming = meeting.at.isAfter(DateTime.now());
    final modeText = switch (meeting.mode) {
      MeetingMode.inPerson => '${l.inPerson} · ${meeting.venue}',
      MeetingMode.online => '${l.online} · ${meeting.platform}',
      MeetingMode.hybrid => '${l.hybrid} · ${meeting.venue} + ${meeting.platform}',
    };
    final approvedMinutes = meeting.minutesStatus == 'approved' || meeting.minutesStatus == 'Approved by President';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pill(meeting.type, color: Theme.of(context).colorScheme.primary),
                const Spacer(),
                Text(dateTimeFmt.format(meeting.at), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(meeting.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(modeText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final item in meeting.agenda) Text('• $item'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill('${meeting.accepted} ${l.accepted}', color: AppColors.green),
                Pill('${meeting.tentative} ${l.tentativeCount}', color: AppColors.amber),
                Pill('${meeting.declined} ${l.declined}', color: AppColors.red),
                Pill('${meeting.invited - meeting.accepted - meeting.tentative - meeting.declined} ${l.noReply}', color: Colors.blueGrey),
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
                      ButtonSegment(value: Rsvp.accepted, label: Text(l.accept)),
                      ButtonSegment(value: Rsvp.tentative, label: Text(l.tentative)),
                      ButtonSegment(value: Rsvp.declined, label: Text(l.decline)),
                    ],
                    selected: meeting.myRsvp == Rsvp.pending ? <Rsvp>{} : {meeting.myRsvp},
                    onSelectionChanged: (values) async {
                      if (values.isEmpty) return;
                      try {
                        await ref.read(meetingsProvider.notifier).rsvp(meeting.id, values.first);
                      } catch (error) {
                        if (context.mounted) toast(context, '$error');
                      }
                    },
                  ),
                  if (meeting.platform != null)
                    Text(l.meetingLinkNotConfigured, style: const TextStyle(fontSize: 12)),
                  if (canManage)
                    TextButton.icon(
                      onPressed: () => _reschedule(context, ref, meeting),
                      icon: const Icon(Icons.update),
                      label: Text(l.meetingReschedule),
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
                    switch (meeting.minutesStatus) {
                      'draft' => l.minutesDraft,
                      'pending_approval' => l.minutesPendingApproval,
                      'approved' || 'Approved by President' => l.minutesApproved,
                      _ => l.minutesPending,
                    },
                    color: approvedMinutes ? AppColors.green : AppColors.amber,
                    icon: Icons.description_outlined,
                  ),
                  if (canManage && (meeting.minutesStatus == null || meeting.minutesStatus == 'draft'))
                    FilledButton.tonalIcon(
                      onPressed: () => _editMinutes(context, ref, meeting),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(meeting.minutesStatus == 'draft' ? l.editMinutes : l.writeMinutes),
                    ),
                  if (canManage && meeting.minutesStatus == 'draft')
                    TextButton.icon(
                      onPressed: () => _submitMinutes(context, ref, meeting),
                      icon: const Icon(Icons.send_outlined),
                      label: Text(l.submitForApproval),
                    ),
                  if (canApproveMinutes && meeting.minutesStatus == 'pending_approval')
                    FilledButton.tonalIcon(
                      onPressed: () => _approveMinutes(context, ref, meeting),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(l.approveMinutes),
                    ),
                  if (approvedMinutes)
                    TextButton(onPressed: () => _viewMinutes(context, meeting), child: Text(l.viewMinutes)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMinutes(BuildContext context, WidgetRef ref, Meeting meeting) async {
    final l = AppLocalizations.of(context);
    final minutes = TextEditingController(text: meeting.minutesText ?? _minutesTemplate(meeting));
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.minutesTitle),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: minutes,
            maxLines: 14,
            maxLength: 30000,
            decoration: const InputDecoration(labelText: 'Minutes', alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l.saveDraft)),
        ],
      ),
    );
    if (saved == true) {
      try {
        await ref.read(meetingsProvider.notifier).saveMinutes(meeting.id, minutes.text);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }
    minutes.dispose();
  }

  Future<void> _submitMinutes(BuildContext context, WidgetRef ref, Meeting meeting) async {
    try {
      await ref.read(meetingsProvider.notifier).submitMinutes(meeting.id);
    } catch (error) {
      if (context.mounted) toast(context, '$error');
    }
  }

  Future<void> _approveMinutes(BuildContext context, WidgetRef ref, Meeting meeting) async {
    try {
      await ref.read(meetingsProvider.notifier).approveMinutes(meeting.id);
    } catch (error) {
      if (context.mounted) toast(context, '$error');
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref, Meeting meeting) async {
    final l = AppLocalizations.of(context);
    final date = await showDatePicker(
      context: context,
      initialDate: meeting.at,
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(meeting.at));
    if (time == null || !context.mounted) return;
    try {
      await ref.read(meetingsProvider.notifier).reschedule(meeting.id, DateTime(date.year, date.month, date.day, time.hour, time.minute));
      if (context.mounted) toast(context, l.meetingSaved);
    } catch (error) {
      if (context.mounted) toast(context, '$error');
    }
  }

  void _viewMinutes(BuildContext context, Meeting meeting) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.minutesApproved),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(meeting.minutesText ?? ''))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(l.no))],
      ),
    );
  }

  String _minutesTemplate(Meeting meeting) => [
    meeting.title,
    'Date: ${dateTimeFmt.format(meeting.at)}',
    '',
    'Attendees:',
    '',
    'Agenda and discussion:',
    for (final item in meeting.agenda) '- $item',
    '',
    'Decisions:',
    '',
    'Action items:',
  ].join('\n');
}
