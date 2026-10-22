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
    final reviewer = role == Role.secretary || role == Role.jointSecretary;
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
                if (c.slaApplies) SlaPill(sla),
                if (!c.kind.isEnhancement) CriticalityPill(c.criticality, ai: c.aiSuggested),
                Pill(c.status.label, color: c.inReview ? Colors.purple : Colors.blueGrey),
                c.kind.isEnhancement
                    ? Pill(c.kind.label, color: Colors.teal, icon: Icons.lightbulb_outline)
                    : Pill(c.type == TicketType.maintenance ? 'Maintenance' : 'Complaint', color: theme.colorScheme.primary),
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
              if (c.estimatedCost != null) _kv('Estimated cost', inr.format(c.estimatedCost)),
              if (c.acceptedAt != null && c.flatNumber == 'Common') _kv('Accepted', dateTimeFmt.format(c.acceptedAt!)),
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
        if (c.inReview && !reviewer)
          Card(
            color: Colors.purple.withValues(alpha: 0.05),
            child: ListTile(
              leading: const Icon(Icons.rate_review_outlined, color: Colors.purple),
              title: const Text('Waiting for Secretary review'),
              subtitle: Text(DateTime.now().difference(c.createdAt).inHours >= 24
                  ? 'Waiting more than 24 hours – reminder sent to the Secretary.'
                  : 'The Secretary will check, edit if needed, and accept it as a complaint or enhancement.'),
            ),
          ),
        if (c.inReview && reviewer)
          SectionCard(
            title: 'Secretary review',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Raised by ${c.raisedBy} as "${c.kind.label}". Check and edit the details before it is formally pursued.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => _editDetails(context, ref, c), icon: const Icon(Icons.edit_outlined), label: const Text('Edit details')),
                PopupMenuButton<Criticality>(
                  tooltip: 'Accept as complaint',
                  onSelected: (cr) => notifier.update(id, (x) => x.copyWith(
                        kind: ReportKind.complaint,
                        criticality: cr,
                        status: TicketStatus.newTicket,
                        acceptedAt: DateTime.now(),
                        remarks: [...x.remarks, TicketRemark(by: '${session.user.name} (${role.label})', at: DateTime.now(), text: 'Accepted as complaint (${cr.label}). SLA clock started.')],
                      )),
                  itemBuilder: (_) => [for (final cr in Criticality.values) PopupMenuItem(value: cr, child: Text('Accept as complaint – ${cr.label}'))],
                  child: const Chip(avatar: Icon(Icons.check, size: 18), label: Text('Accept as complaint')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => notifier.update(id, (x) => x.copyWith(
                        kind: ReportKind.enhancementImmediate,
                        status: TicketStatus.newTicket,
                        acceptedAt: DateTime.now(),
                        remarks: [...x.remarks, TicketRemark(by: '${session.user.name} (${role.label})', at: DateTime.now(), text: 'Accepted as immediate enhancement.')],
                      )),
                  icon: const Icon(Icons.bolt),
                  label: const Text('Enhancement – now'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => notifier.update(id, (x) => x.copyWith(
                        kind: ReportKind.enhancementFuture,
                        status: TicketStatus.planned,
                        acceptedAt: DateTime.now(),
                        remarks: [...x.remarks, TicketRemark(by: '${session.user.name} (${role.label})', at: DateTime.now(), text: 'Moved to future enhancements (for budget / AGM).')],
                      )),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Enhancement – later'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () async {
                    final reason = await promptText(context, title: 'Reject or merge', hint: 'Reason, e.g. duplicate of CMP-2026-0142');
                    if (reason != null) addRemark('Rejected: $reason', status: TicketStatus.rejected);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Reject / merge'),
                ),
              ]),
            ]),
          ),
        if (c.status == TicketStatus.planned && reviewer)
          SectionCard(
            title: 'Future enhancement',
            child: Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () => addRemark('Moved to immediate enhancements.', status: TicketStatus.newTicket),
                icon: const Icon(Icons.bolt),
                label: const Text('Pursue now'),
              ),
              TextButton.icon(onPressed: () => toast(context, 'Added to the next General Body agenda'), icon: const Icon(Icons.groups_outlined), label: const Text('Add to AGM agenda')),
            ]),
          ),
        if (canManage && c.status.isOpen && !c.inReview)
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
            if (c.slaApplies && sla.color != SlaColor.green && c.remarks.isEmpty)
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

  Future<void> _editDetails(BuildContext context, WidgetRef ref, Complaint c) async {
    final title = TextEditingController(text: c.title);
    final desc = TextEditingController(text: c.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit details'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Details / Secretary inputs')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final s = ref.read(sessionProvider)!;
    ref.read(complaintsProvider.notifier).update(c.id, (x) => x.copyWith(
          title: title.text.trim(),
          description: desc.text.trim(),
          remarks: [...x.remarks, TicketRemark(by: '${s.user.name} (${s.activeRole.label})', at: DateTime.now(), text: 'Edited details during review.')],
        ));
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
