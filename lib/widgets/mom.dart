import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'common.dart';

/// MOM references point at approved meeting minutes ("<meeting title> · <date>").
String momLabel(Meeting m) => '${m.title} · ${dateFmt.format(m.at)}';

bool _approved(Meeting m) => m.minutesStatus == 'approved' || m.minutesStatus == 'Approved by President';

List<String> approvedMomOptions(BuildContext context) => [
  for (final m in ProviderScope.containerOf(context, listen: false).read(meetingsProvider))
    if (_approved(m)) momLabel(m),
];

/// Approved AGM / General Body minutes, required to remove an office bearer.
List<String> approvedAgmOptions(BuildContext context) => [
  for (final m in ProviderScope.containerOf(context, listen: false).read(meetingsProvider))
    if (_approved(m) && m.type == 'General Body') momLabel(m),
];

Future<void> openMom(BuildContext context, String? ref) async {
  final meeting = ProviderScope.containerOf(context, listen: false)
      .read(meetingsProvider)
      .where((m) => ref != null && _approved(m) && (momLabel(m) == ref || ref.contains(m.title)))
      .firstOrNull;
  if (meeting == null || (meeting.minutesText ?? '').trim().isEmpty) {
    return toast(
      context,
      'No approved minutes found for "${ref ?? ''}". Approve the meeting minutes in Meetings first.',
    );
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Minutes · ${momLabel(meeting)}'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(meeting.minutesText!))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}
