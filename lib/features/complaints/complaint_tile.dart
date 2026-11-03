import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;

import '../../widgets/tr_text.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
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
      leading: Container(
        width: 6,
        height: 44,
        decoration: BoxDecoration(color: _barColor(c, sla), borderRadius: BorderRadius.circular(3)),
      ),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${c.id} · ${c.flatNumber} · ${c.category}', style: Theme.of(context).textTheme.bodySmall),
            if (c.kind.isEnhancement)
              Pill(c.kind.label, color: Colors.teal, icon: Icons.lightbulb_outline)
            else
              CriticalityPill(c.criticality, ai: c.aiSuggested),
            Pill(c.status.label, color: c.inReview ? Colors.purple : AppColors.complaintStatus(c.status)),
          ],
        ),
      ),
      trailing: _trailing(c, sla),
    );
  }

  Widget _trailing(Complaint c, SlaInfo sla) {
    if (c.slaApplies) return SlaPill(sla);
    if (c.inReview) return const Pill('Review', color: Colors.purple, icon: Icons.rate_review_outlined);
    if (c.status.isOpen) return const Icon(Icons.lightbulb_outline, color: Colors.teal);
    return switch (c.status) {
      TicketStatus.rejected => const Icon(Icons.cancel_outlined, color: Colors.grey),
      TicketStatus.planned => const Icon(Icons.event_note_outlined, color: Colors.teal),
      TicketStatus.closed => const Icon(Icons.cancel_outlined, color: Colors.blueGrey),
      TicketStatus.resolved => const Icon(Icons.check_circle, color: AppColors.green),
      _ => const Icon(Icons.circle_outlined, color: Colors.blue),
    };
  }

  Color _barColor(Complaint c, SlaInfo sla) {
    if (c.slaApplies) return _slaColor(sla);
    if (c.inReview) return Colors.purple.shade200;
    if (c.kind.isEnhancement && c.status.isOpen) return Colors.teal.shade200;
    return AppColors.complaintStatus(c.status).withValues(alpha: 0.35);
  }

  Color _slaColor(SlaInfo s) => AppColors.sla(s.color);
}

/// Complaints the active role is allowed to see.
List<Complaint> visibleComplaints(WidgetRef ref) {
  final s = ref.watch(sessionProvider)!;
  final all = ref.watch(complaintsProvider);
  return switch (s.activeRole) {
    Role.owner || Role.resident =>
      all.where((c) => c.raisedById != null ? c.raisedById == s.user.id : c.raisedBy == s.user.name).toList(),
    _ => all,
  };
}
