import 'package:flutter/material.dart' hide Text;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/membership_transition_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final membershipTransitionChecklistProvider = FutureProvider.autoDispose.family<List<MembershipTransitionItem>, String>(
  (ref, requestRef) => MembershipTransitionRepo.checklist(requestRef),
);
final membershipPaymentGateProvider = FutureProvider.autoDispose.family<({String status, int outstandingDue}), String>(
  (ref, requestRef) => MembershipTransitionRepo.paymentGate(requestRef),
);

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
    final paymentGate = backendEnabled && (a.code == 'W20' || a.code == 'W21')
      ? ref.watch(membershipPaymentGateProvider(a.id))
      : null;
    if (paymentGate != null) {
      ref.listen(membershipPaymentGateProvider(a.id), (previous, next) {
        final previousStatus = previous?.value?.status;
        final nextStatus = next.value?.status;
        if (previousStatus != null && nextStatus != null && previousStatus != nextStatus) {
          ref.read(approvalsProvider.notifier).refresh();
        }
      });
      ref.listen(duesProvider, (previous, next) {
        if (previous != null &&
            (previous.lines.length != next.lines.length || previous.payments.length != next.payments.length)) {
          ref.invalidate(membershipPaymentGateProvider(a.id));
        }
      });
    }
    final paymentBlocked = paymentGate?.value?.status == 'pending_payment_due';
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
      try {
        await notifier.decide(a.id, s.activeRole, s.user.name, d, comment);
      } catch (e) {
        final msg = e.toString();
        if (context.mounted) {
          toast(
            context,
            msg.contains('maker-checker')
                ? 'Maker-checker: you raised this request or already decided an earlier step.'
                : msg.contains('not your step')
                ? 'This step is not assigned to you.'
                : 'Could not record the decision. Please try again.',
          );
        }
        return;
      }
      if (context.mounted) toast(context, 'Decision recorded. All approvers and the initiator have been notified.');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${a.code} · ${a.id}'),
        actions: [
          if (paymentGate != null)
            IconButton(
              tooltip: 'Refresh payment and approvals',
              onPressed: () {
                ref.invalidate(membershipPaymentGateProvider(a.id));
                ref.read(approvalsProvider.notifier).refresh();
              },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
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
          if (a.code == 'W20' || a.code == 'W21') ...[
            const SizedBox(height: 16),
            if (paymentGate != null)
              SectionCard(
                title: 'Payment and activation',
                child: paymentGate.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('$error'),
                  data: (gate) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      gate.status == 'pending_payment_due' ? Icons.payments_outlined :
                      gate.status == 'applied' ? Icons.verified_outlined : Icons.pending_actions_outlined,
                      color: gate.status == 'pending_payment_due' ? AppColors.red :
                          gate.status == 'applied' ? AppColors.green : AppColors.amber,
                    ),
                    title: Text(switch (gate.status) {
                      'pending_first_approval' => 'Waiting for first President approval',
                      'pending_payment_due' => 'Pending payment · ${inr.format(gate.outstandingDue)}',
                      'pending_final_approval' => 'Dues cleared · awaiting Secretary and President',
                      'applied' => 'Payment clear · membership activated',
                      _ => 'Membership transition pending',
                    }),
                    subtitle: Text(switch (gate.status) {
                      'pending_first_approval' => 'The outgoing record remains active until first approval.',
                      'pending_payment_due' => 'The outgoing record is archived. The incoming person is not active for gate clearance.',
                      'pending_final_approval' => 'Dues are currently zero; they are checked again before final activation.',
                      'applied' => 'The incoming owner or tenant is now in active association records.',
                      _ => '',
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            _MembershipTransitionChecklist(
              request: a,
              canEdit: (isInitiator || s.activeRole == Role.owner || s.user.canInitiateMembership(s.activeRole)) &&
                  a.overall == Decision.pending,
            ),
          ],
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
            if (a.code == 'W21' &&
              (backendEnabled ? paymentGate?.value?.status == 'applied' : a.overall == Decision.approved)) ...[
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
          if (myTurn && !paymentBlocked)
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

class _MembershipTransitionChecklist extends ConsumerWidget {
  const _MembershipTransitionChecklist({required this.request, required this.canEdit});

  final ApprovalRequest request;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(membershipTransitionChecklistProvider(request.id));
    return SectionCard(
      title: 'Move-in / move-out checklist',
      child: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text('$error'),
        data: (entries) => Column(
          children: [
            for (final phase in const ['move_out', 'move_in']) ...[
              if (entries.any((entry) => entry.phase == phase))
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(phase == 'move_out' ? 'Move-out' : 'Move-in', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              for (final entry in entries.where((entry) => entry.phase == phase))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: entry.completed,
                  onChanged: canEdit
                      ? (value) async {
                          var note = entry.note;
                          if (value == true) {
                            note = await promptText(context, title: entry.label, hint: 'Optional note or reference', required: false) ?? '';
                            if (!context.mounted) return;
                          }
                          try {
                            await MembershipTransitionRepo.update(entry.id, value ?? false, note);
                            ref.invalidate(membershipTransitionChecklistProvider(request.id));
                          } catch (error) {
                            if (context.mounted) toast(context, '$error');
                          }
                        }
                      : null,
                  title: Text(entry.label),
                  subtitle: Text([
                    if (entry.required) 'Required before final approval',
                    if (entry.completedAt != null) dateTimeFmt.format(entry.completedAt!),
                    if (entry.note.isNotEmpty) entry.note,
                  ].join(' · ')),
                  secondary: entry.required ? const Icon(Icons.priority_high, color: AppColors.amber) : null,
                ),
            ],
          ],
        ),
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
