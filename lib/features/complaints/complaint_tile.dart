import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../models/sla.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class ComplaintTile extends ConsumerWidget {
  const ComplaintTile({super.key, required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = complaint;
    final sla = slaFor(c, ref.watch(clockProvider));
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: () => context.go('/complaints/${c.id}'),
      leading: Container(width: 6, height: 44, decoration: BoxDecoration(color: c.status.isOpen ? _slaColor(sla) : Colors.grey.shade300, borderRadius: BorderRadius.circular(3))),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${c.id} · ${c.flatNumber} · ${c.category}', style: Theme.of(context).textTheme.bodySmall),
          CriticalityPill(c.criticality, ai: c.aiSuggested),
          Pill(c.status.label, color: Colors.blueGrey),
        ]),
      ),
      trailing: c.status.isOpen ? SlaPill(sla) : const Icon(Icons.check_circle, color: Colors.green),
    );
  }

  Color _slaColor(SlaInfo s) => switch (s.color) {
        SlaColor.green => const Color(0xFF16A34A),
        SlaColor.amber => const Color(0xFFF59E0B),
        SlaColor.red => const Color(0xFFDC2626),
      };
}

/// Complaints the active role is allowed to see.
List<Complaint> visibleComplaints(WidgetRef ref) {
  final s = ref.watch(sessionProvider)!;
  final all = ref.watch(complaintsProvider);
  return switch (s.activeRole) {
    Role.owner || Role.resident => all.where((c) => c.flatNumber == s.user.flatNumber || c.raisedBy == s.user.name).toList(),
    _ => all,
  };
}
