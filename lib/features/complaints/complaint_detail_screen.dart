import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../models/sla.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class ComplaintDetailScreen extends ConsumerWidget {
  const ComplaintDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(complaintsProvider).where((x) => x.id == id).firstOrNull;
    if (c == null) return const Scaffold(body: EmptyState('Complaint not found'));
    final session = ref.watch(sessionProvider)!;
    final role = session.activeRole;
    final sla = slaFor(c, ref.watch(clockProvider));
    final canManage = role.isOfficeBearer || role == Role.caretaker || role == Role.monitor;
    final isRaiser = c.raisedBy == session.user.name || c.flatNumber == session.user.flatNumber;
    final notifier = ref.read(complaintsProvider.notifier);
    final theme = Theme.of(context);

    void addRemark(String text, {TicketStatus? status, Criticality? crit}) {
      notifier.update(id, (x) => x.copyWith(
            status: status,
            criticality: crit,
            aiSuggested: crit != null ? false : null,
            remarks: [...x.remarks, TicketRemark(by: '${session.user.name} (${role.label})', at: DateTime.now(), text: text)],
          ));
    }

    Future<void> changeStatus(TicketStatus s) async {
      final needsReason = sla.color != SlaColor.green || s == TicketStatus.onHold;
      final text = await promptText(
        context,
        title: 'Move to "${s.label}"',
        hint: needsReason ? 'Remark required: what was done / why not progressed' : 'Optional remark',
        required: needsReason,
      );
      if (text == null) return;
      addRemark(text.isEmpty ? 'Status changed to ${s.label}' : '[${s.label}] $text', status: s);
    }

    return Scaffold(
      appBar: AppBar(title: Text(c.id)),
      body: PageBody(maxWidth: 900, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (c.status.isOpen) SlaPill(sla),
                CriticalityPill(c.criticality, ai: c.aiSuggested),
                Pill(c.status.label, color: Colors.blueGrey),
                Pill(c.type == TicketType.maintenance ? 'Maintenance' : 'Complaint', color: theme.colorScheme.primary),
                if (c.isPrivate) const Pill('Private', color: Colors.purple, icon: Icons.lock_outline),
              ]),
              const SizedBox(height: 12),
              Text(c.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(c.description.isEmpty ? 'No details added' : c.description),
              const SizedBox(height: 12),
              _kv('Flat / location', '${c.flatNumber} · ${c.location}'),
              _kv('Category', c.category),
              _kv('Raised by', '${c.raisedBy} · ${dateTimeFmt.format(c.createdAt)}'),
              _kv('Assigned to', c.assignee ?? 'Not assigned'),
              if (c.aiSuggested) _kv('AI note', 'Criticality suggested by AI from the description. Staff can override.'),
              if (c.photoCount > 0 || c.hasVoiceNote) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < c.photoCount; i++)
                    Container(
                      width: 96, height: 72,
                      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.image_outlined),
                    ),
                  if (c.hasVoiceNote)
                    Chip(avatar: const Icon(Icons.play_arrow), label: const Text('Voice note · 0:24 · transcribed')),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (canManage && c.status.isOpen)
          SectionCard(
            title: 'Actions',
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.assignee == null)
                FilledButton.tonalIcon(
                  onPressed: () => notifier.update(id, (x) => x.copyWith(assignee: 'Suresh Kumar', status: TicketStatus.assigned)),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Assign to caretaker'),
                ),
              for (final s in [TicketStatus.inProgress, TicketStatus.onHold, TicketStatus.resolved])
                if (s != c.status) OutlinedButton(onPressed: () => changeStatus(s), child: Text(s.label)),
              PopupMenuButton<Criticality>(
                onSelected: (cr) async {
                  final reason = await promptText(context, title: 'Change criticality to ${cr.label}', hint: 'Reason (required)');
                  if (reason != null) addRemark('Criticality changed to ${cr.label}: $reason', crit: cr);
                },
                itemBuilder: (_) => [for (final cr in Criticality.values) PopupMenuItem(value: cr, child: Text(cr.label))],
                child: const Chip(avatar: Icon(Icons.tune, size: 18), label: Text('Change criticality')),
              ),
              TextButton.icon(
                onPressed: () async {
                  final t = await promptText(context, title: 'Add remark', hint: 'Progress update');
                  if (t != null) addRemark(t);
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Add remark'),
              ),
            ]),
          ),
        if (isRaiser && c.status == TicketStatus.resolved)
          SectionCard(
            title: 'Was this resolved to your satisfaction?',
            child: Wrap(spacing: 8, children: [
              FilledButton.icon(
                onPressed: () => addRemark('Closed by resident – rated 5/5', status: TicketStatus.closed),
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('Yes, close it'),
              ),
              OutlinedButton.icon(
                onPressed: () => addRemark('Reopened by resident', status: TicketStatus.inProgress),
                icon: const Icon(Icons.replay),
                label: const Text('No, reopen'),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Timeline',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _event(context, 'Created by ${c.raisedBy}', c.createdAt),
            for (final r in c.remarks) _event(context, '${r.by}: ${r.text}', r.at),
            if (c.status.isOpen && sla.color != SlaColor.green && c.remarks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠ No progress remark yet. A remark is mandatory for Amber/Red tickets.',
                    style: TextStyle(color: AppColors.sla(sla.color))),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(v)),
        ]),
      );

  Widget _event(BuildContext context, String text, DateTime at) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.circle, size: 10),
        title: Text(text),
        subtitle: Text(dateTimeFmt.format(at)),
      );
}
