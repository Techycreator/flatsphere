import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;

import '../../widgets/tr_text.dart';

const _terms = <(String, String)>[
  ('MOM · Minutes of Meeting', 'The written record of what was discussed and decided at a meeting.'),
  ('EC · Executive Committee', 'The elected group that runs the association day to day.'),
  ('AMC · Annual Maintenance Contract', 'A yearly service agreement with a vendor, for example for lifts or the generator.'),
  (
    'SLA · Service Level Agreement',
    'The time within which a complaint should be handled. Green is on time, Amber is getting late, Red is overdue.',
  ),
  ('Maker-checker', 'The person who raises a request cannot approve it. A different person must check and approve.'),
  ('AGM · Annual General Meeting', 'The yearly meeting of all owners to approve accounts and the budget.'),
  ('OTP · One-time password', 'The 6-digit code emailed to you to sign in. It works once and expires in 10 minutes.'),
  (
    'Monitor',
    'A member appointed by the committee to oversee an area such as the gym or sewage plant for a set period.',
  ),
  ('Membership desk', 'Committee members who can add owners and residents and start membership changes.'),
  ('Corpus fund', 'A reserve fund kept for major future repairs and replacements.'),
  ('Audit log', 'A record of who did what and when. It cannot be edited.'),
];

Future<void> showGlossary(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Help & terms'),
    content: SizedBox(
      width: 440,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final t in _terms)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(t.$2),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
  ),
);
