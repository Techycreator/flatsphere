import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../backend/meetings_repo.dart';
import '../../backend/directory_repo.dart' show friendlyError;
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
    final link = TextEditingController();
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
                      for (final value in const [
                        'Executive Committee',
                        'Office bearers',
                        'Staff meeting',
                        'General Body',
                      ])
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) => setDialogState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: InputDecoration(labelText: '${l.meetingTitle} *'),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<MeetingMode>(
                    segments: [
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
                      final time = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(at),
                      );
                      if (time != null && dialogContext.mounted) {
                        setDialogState(() => at = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(dateTimeFmt.format(at)),
                  ),
                  if (mode != MeetingMode.inPerson)
                    TextField(
                      controller: link,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Meeting link (optional now)',
                        hintText: 'https://meet.google.com/abc-defg-hij',
                        helperText: 'Create the meeting in Google Meet / Zoom and paste its link here.',
                        helperMaxLines: 2,
                      ),
                    ),
                  TextField(
                    controller: agenda,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l.meetingAgenda),
                  ),
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
      await ref
          .read(meetingsProvider.notifier)
          .add(
            Meeting(
              id: backendEnabled ? '' : 'M-${DateTime.now().microsecondsSinceEpoch}',
              type: type,
              title: title.text.trim(),
              at: at,
              mode: mode,
              platform: mode == MeetingMode.inPerson ? null : platform,
              venue: mode == MeetingMode.online ? null : 'Association office',
              link: mode == MeetingMode.inPerson ? null : link.text.trim(),
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                Pill(meeting.type, color: Theme.of(context).colorScheme.primary),
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
                Pill(
                  '${meeting.invited - meeting.accepted - meeting.tentative - meeting.declined} ${l.noReply}',
                  color: Colors.blueGrey,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OnlineRow(meeting: meeting, canManage: canManage),
            if (upcoming)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<Rsvp>(
                    emptySelectionAllowed: true,
                    segments: [
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
            decoration: const InputDecoration(
              labelText: 'Minutes',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
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
      await ref
          .read(meetingsProvider.notifier)
          .reschedule(meeting.id, DateTime(date.year, date.month, date.day, time.hour, time.minute));
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

/// Join button (online/hybrid, from 15 minutes before the start until 3 hours after), link editing and attendance.
class _OnlineRow extends ConsumerWidget {
  const _OnlineRow({required this.meeting, required this.canManage});

  final Meeting meeting;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final online = meeting.mode != MeetingMode.inPerson;
    final opens = meeting.at.subtract(const Duration(minutes: 15));
    final closes = meeting.at.add(const Duration(hours: 3));
    final joinable = online && meeting.link != null && now.isAfter(opens) && now.isBefore(closes);
    final children = <Widget>[
      if (joinable)
        FilledButton.icon(
          onPressed: () => _join(context),
          icon: const Icon(Icons.video_call_outlined),
          label: const Text('Join meeting'),
        )
      else if (online && now.isBefore(opens))
        Text(
          meeting.link == null
              ? 'Meeting link not added yet'
              : 'Join button appears at ${dateTimeFmt.format(opens)} (15 min before start)',
          style: const TextStyle(fontSize: 12),
        ),
      if (online && canManage && now.isBefore(closes))
        TextButton.icon(
          onPressed: () => _editLink(context, ref),
          icon: const Icon(Icons.link),
          label: Text(meeting.link == null ? 'Add meeting link' : 'Change link'),
        ),
      if (canManage && now.isAfter(opens))
        TextButton.icon(
          onPressed: () => _attendance(context),
          icon: const Icon(Icons.how_to_reg_outlined),
          label: const Text('Attendance'),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children),
    );
  }

  Future<void> _join(BuildContext context) async {
    // Open first (browsers block pop-ups opened after an await), then record attendance.
    await launchUrl(Uri.parse(meeting.link!), webOnlyWindowName: '_blank');
    if (!backendEnabled) return;
    try {
      await MeetingsRepo.join(meeting.id);
    } catch (error) {
      if (context.mounted) toast(context, friendlyError(error));
    }
  }

  Future<void> _editLink(BuildContext context, WidgetRef ref) async {
    final link = await promptText(context, title: 'Meeting link', hint: 'https://meet.google.com/abc-defg-hij');
    if (link == null) return;
    try {
      await ref.read(meetingsProvider.notifier).setLink(meeting.id, link);
      if (context.mounted) toast(context, 'Meeting link saved');
    } catch (error) {
      if (context.mounted) toast(context, friendlyError(error));
    }
  }

  Future<void> _attendance(BuildContext context) async {
    if (!backendEnabled) return toast(context, 'Attendance is saved in the cloud version');
    var people = MeetingsRepo.attendance(meeting.id);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Attendance · ${meeting.title}'),
          content: SizedBox(
            width: 460,
            child: FutureBuilder(
              future: people,
              builder: (_, snap) {
                if (snap.hasError) return Text(friendlyError(snap.error!));
                if (!snap.hasData) return const LinearProgressIndicator();
                final list = snap.data!;
                final present = list.where((p) => p.present == true).length;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$present of ${list.length} present. Online joiners are marked automatically.'),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in list)
                            CheckboxListTile(
                              value: p.present ?? false,
                              title: Text(p.name),
                              subtitle: Text(
                                [
                                  if (p.rsvp != null) 'RSVP: ${p.rsvp}',
                                  if (p.how == 'joined_online') 'joined online',
                                ].join(' · '),
                              ),
                              onChanged: (v) async {
                                try {
                                  await MeetingsRepo.markAttendance(meeting.id, p.userId, v ?? false);
                                  setState(() => people = MeetingsRepo.attendance(meeting.id));
                                } catch (error) {
                                  if (ctx.mounted) toast(ctx, friendlyError(error));
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
    );
  }
}
