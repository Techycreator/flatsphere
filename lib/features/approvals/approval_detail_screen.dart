import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class ApprovalDetailScreen extends ConsumerWidget {
  const ApprovalDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final a = ref.watch(approvalsProvider).where((x) => x.id == id).firstOrNull;
    if (a == null) return const Scaffold(body: EmptyState('Request not found'));
    final s = ref.watch(sessionProvider)!;
    final isInitiator = a.initiatorName.contains(s.user.name);
    final myTurn = a.awaits(s.activeRole, s.user.name);
    final notifier = ref.read(approvalsProvider.notifier);
    final theme = Theme.of(context);

    Future<void> decide(Decision d) async {
      String? comment;
      if (d != Decision.approved) {
        comment = await promptText(
          context,
          title: d == Decision.rejected ? l.reject : l.sendBack,
          hint: 'Comment (required)',
        );
        if (comment == null) return;
      }
      if (d == Decision.approved && a.highRisk) {
        if (!context.mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => _OtpDialog(approveLabel: l.approve),
        );
        if (ok != true) return;
      }
      notifier.decide(a.id, s.activeRole, s.user.name, d, comment);
      if (context.mounted) toast(context, 'Decision recorded. All approvers and the initiator have been notified.');
    }

    return Scaffold(
      appBar: AppBar(title: Text('${a.code} · ${a.id}')),
      body: PageBody(
        maxWidth: 900,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Raised by ${a.initiatorName} (${a.initiatorRole.label}) · ${dateTimeFmt.format(a.createdAt)}'),
                  const SizedBox(height: 12),
                  for (final e in a.details.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 160,
                            child: Text(e.key, style: const TextStyle(color: Colors.black54)),
                          ),
                          Expanded(child: Text(e.value)),
                        ],
                      ),
                    ),
                  if (a.momRequired) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.description_outlined, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Linked MOM: ${a.momRef ?? 'Not linked – cannot be approved'}')),
                          TextButton(
                            onPressed: () => toast(context, 'Opens the approved MOM PDF'),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (a.code == 'W3') ...[
                    const SizedBox(height: 8),
                    const Text(
                      'All EC members are alerted by SMS, email, push and web notification at every step. The change takes effect 48 hours after final approval.',
                      style: TextStyle(color: AppColors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Approval chain',
            child: Column(
              children: [
                for (final st in a.steps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (st.decision) {
                        Decision.approved => Icons.check_circle,
                        Decision.rejected => Icons.cancel,
                        Decision.sentBack => Icons.undo,
                        Decision.pending => Icons.radio_button_unchecked,
                      },
                      color: switch (st.decision) {
                        Decision.approved => AppColors.green,
                        Decision.rejected => AppColors.red,
                        Decision.sentBack => AppColors.amber,
                        Decision.pending => Colors.grey,
                      },
                    ),
                    title: Text(
                      '${st.role == Role.owner ? 'Owner consent' : st.label} – ${st.name}${st.onBehalfOf != null ? ' (in place of ${st.onBehalfOf})' : ''}',
                    ),
                    subtitle: Text(
                      [st.decision.name, if (st.decidedBy != null) 'by ${st.decidedBy}', ?st.comment].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (a.code == 'W21' && a.overall == Decision.approved) ...[
            const Card(
              color: Color(0xFFF0FDF4),
              child: ListTile(
                leading: Icon(Icons.verified_user, color: AppColors.green),
                title: Text('Applied to records'),
                subtitle: Text(
                  'Resident updated. Outgoing tenant and family logins disabled and archived. Caretaker informed.',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isInitiator && a.overall == Decision.pending)
            const Card(child: EmptyState('You raised this request, so you cannot approve it.', icon: Icons.block)),
          if (myTurn)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => decide(Decision.approved),
                  icon: const Icon(Icons.check),
                  label: Text(l.approve),
                ),
                OutlinedButton.icon(
                  onPressed: () => decide(Decision.sentBack),
                  icon: const Icon(Icons.undo),
                  label: Text(l.sendBack),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () => decide(Decision.rejected),
                  icon: const Icon(Icons.close),
                  label: Text(l.reject),
                ),
              ],
            ),
          if (s.activeRole == Role.president) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                notifier.flag(a.id);
                toast(context, a.flagged ? 'Flag removed' : 'Flagged – added to next EC meeting agenda');
              },
              icon: Icon(a.flagged ? Icons.flag : Icons.outlined_flag),
              label: Text(a.flagged ? 'Remove flag' : 'Flag for discussion'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OtpDialog extends StatefulWidget {
  const _OtpDialog({required this.approveLabel});
  final String approveLabel;

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _ctrl = TextEditingController();

  bool get _valid => RegExp(r'^\d{6}$').hasMatch(_ctrl.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm with OTP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('High-risk approval. An OTP was sent to your registered mobile.'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'OTP (demo: any 6 digits)',
              errorText: _ctrl.text.isNotEmpty && !_valid ? 'Enter all 6 digits' : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_valid) Navigator.pop(context, true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? () => Navigator.pop(context, true) : null, child: Text(widget.approveLabel)),
      ],
    );
  }
}
