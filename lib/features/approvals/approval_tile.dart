import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class ApprovalTile extends StatelessWidget {
  const ApprovalTile({super.key, required this.request});
  final ApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final a = request;
    final done = a.steps.where((s) => s.decision == Decision.approved).length;
    final (statusText, statusColor) = switch (a.overall) {
      Decision.approved => ('Approved', AppColors.green),
      Decision.rejected => ('Rejected', AppColors.red),
      Decision.sentBack => ('Sent back', AppColors.amber),
      Decision.pending => ('Waiting: ${a.currentStep?.role.label ?? '-'}', Colors.blueGrey),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: () => context.go('/approvals/${a.id}'),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(a.code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${a.initiatorName} · $done/${a.steps.length} approved', style: Theme.of(context).textTheme.bodySmall),
            if (a.momRequired) const Pill('MOM required', color: Colors.indigo, icon: Icons.description_outlined),
            if (a.highRisk) const Pill('High risk', color: AppColors.red, icon: Icons.shield_outlined),
            if (a.flagged) const Pill('Flagged', color: AppColors.amber, icon: Icons.flag),
          ],
        ),
      ),
      trailing: Pill(statusText, color: statusColor),
    );
  }
}
