import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notices = ref.watch(noticesProvider);
    return PageBody(maxWidth: 900, children: [
      Text(l.notices, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      for (final n in notices)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(n.important ? Icons.priority_high : Icons.campaign_outlined, color: n.important ? AppColors.red : null),
            title: Text(n.title),
            subtitle: Text('${n.body}\n${dateFmt.format(n.date)}'),
            isThreeLine: true,
            trailing: TextButton(onPressed: () => toast(context, 'Acknowledged'), child: const Text('Acknowledge')),
          ),
        ),
      const SizedBox(height: 8),
      const SectionCard(
        title: 'Emergency contacts',
        child: Column(children: [
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.local_police_outlined), title: Text('Police'), trailing: Text('112')),
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.local_fire_department_outlined), title: Text('Fire'), trailing: Text('101')),
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.local_hospital_outlined), title: Text('Ambulance'), trailing: Text('108')),
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.support_agent), title: Text('Caretaker – Suresh Kumar'), trailing: Text('98470 77777')),
        ]),
      ),
    ]);
  }
}
