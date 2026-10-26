import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/directory_repo.dart' show friendlyError;
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider)!;
    final role = session.activeRole;
    final st = ref.watch(checklistProvider);
    final notifier = ref.read(checklistProvider.notifier);
    final editable = role == Role.caretaker && !st.submitted;
    final reviewer = role.canReviewChecklist;
    final myCats = session.user.monitorCategories;
    final items = role == Role.monitor && myCats.isNotEmpty
        ? st.items.where((i) => myCats.contains(i.category)).toList()
        : st.items;
    final byCat = <String, List<ChecklistItem>>{};
    for (final i in items) {
      byCat.putIfAbsent(i.category, () => []).add(i);
    }
    final theme = Theme.of(context);

    return PageBody(
      maxWidth: 900,
      children: [
        Text(
          '${l.checklist} · ${l.today}',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(dateFmt.format(DateTime.now())),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${st.doneCount} of ${st.items.length} done', style: theme.textTheme.titleMedium),
                    ),
                    if (st.approved)
                      const Pill('Approved', color: AppColors.green, icon: Icons.verified)
                    else if (st.submitted)
                      const Pill('Submitted – awaiting approval', color: AppColors.amber, icon: Icons.hourglass_top)
                    else
                      const Pill('In progress', color: Colors.blueGrey),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: st.progress, minHeight: 10, borderRadius: BorderRadius.circular(6)),
                if (role == Role.monitor && myCats.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Showing your categories: ${myCats.join(', ')}', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        if (const {Role.president, Role.secretary, Role.jointSecretary}.contains(role))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _manageItems(context),
              icon: const Icon(Icons.edit_note),
              label: const Text('Manage checklist items'),
            ),
          ),
        const SizedBox(height: 12),
        for (final e in byCat.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              e.key.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.8),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final item in e.value) ...[
                  _ChecklistRow(item: item, editable: editable, reviewer: reviewer && st.submitted && !st.approved),
                  if (item != e.value.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (role == Role.caretaker && !st.submitted)
          FilledButton.icon(
            onPressed: () {
              notifier.submit();
              final pending = st.items.length - st.doneCount;
              toast(
                context,
                pending == 0
                    ? 'Submitted for approval'
                    : 'Submitted. $pending item(s) recorded as NOT done and flagged to monitor.',
              );
            },
            icon: const Icon(Icons.send),
            label: Padding(padding: const EdgeInsets.all(12), child: Text('${l.submit} (end of day)')),
          ),
        if (reviewer && st.submitted && !st.approved)
          FilledButton.icon(
            onPressed: () {
              notifier.approveAll();
              toast(context, 'Checklist approved');
            },
            icon: const Icon(Icons.verified),
            label: Padding(padding: const EdgeInsets.all(12), child: Text('${l.approve} all')),
          ),
        if (reviewer && !st.submitted)
          const EmptyState(
            'The caretaker has not submitted today\'s checklist yet. You can watch progress live above.',
            icon: Icons.hourglass_empty,
          ),
        const SizedBox(height: 8),
        Text(
          'You can switch YES back to NO until the checklist is submitted. Every change is logged.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ChecklistRow extends ConsumerWidget {
  const _ChecklistRow({required this.item, required this.editable, required this.reviewer});
  final ChecklistItem item;
  final bool editable;
  final bool reviewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(checklistProvider.notifier);
    final narrow = MediaQuery.sizeOf(context).width < 520;

    final toggle = SegmentedButton<bool>(
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (!s.contains(WidgetState.selected)) return null;
          return item.done ? AppColors.green.withValues(alpha: 0.18) : AppColors.red.withValues(alpha: 0.12);
        }),
      ),
      segments: [
        ButtonSegment(value: true, label: Text(l.yes), icon: const Icon(Icons.check)),
        ButtonSegment(value: false, label: Text(l.no), icon: const Icon(Icons.close)),
      ],
      selected: {item.done},
      onSelectionChanged: editable ? (s) => notifier.toggle(item.id, s.first) : null,
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(item.timeWindow, style: Theme.of(context).textTheme.bodySmall),
            if (item.proofRequired) const Pill('Photo proof', color: Colors.indigo, icon: Icons.photo_camera_outlined),
            if (item.note.isNotEmpty) Pill(item.note, color: Colors.teal, icon: Icons.notes),
            if (item.hasVoiceNote) const Pill('Voice note', color: Colors.teal, icon: Icons.mic),
            if (item.rejectedReason != null)
              Pill('Rejected: ${item.rejectedReason}', color: AppColors.red, icon: Icons.error_outline),
          ],
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (editable)
          IconButton(tooltip: l.notes, icon: const Icon(Icons.edit_note), onPressed: () => _noteSheet(context, ref)),
        if (reviewer)
          IconButton(
            tooltip: l.reject,
            icon: const Icon(Icons.thumb_down_alt_outlined),
            onPressed: () async {
              final reason = await promptText(context, title: 'Reject "${item.title}"', hint: 'Reason for caretaker');
              if (reason != null) notifier.reject(item.id, reason);
            },
          ),
        toggle,
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }

  void _noteSheet(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: item.note);
    var voice = item.hasVoiceNote;
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(labelText: '${l.notes} (optional)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => voice = !voice),
                icon: Icon(voice ? Icons.check_circle : Icons.mic_none),
                label: Text(voice ? 'Voice note recorded (tap to remove)' : l.recordVoice),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  ref.read(checklistProvider.notifier).setNote(item.id, ctrl.text.trim(), voice);
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add or remove the caretaker's daily items (removed items keep their past photo proofs).
Future<void> _manageItems(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => Consumer(
    builder: (ctx, ref, _) {
      final items = ref.watch(checklistProvider).items;
      return AlertDialog(
        title: const Text('Caretaker checklist items'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final i in items)
                ListTile(
                  dense: true,
                  title: Text(i.title),
                  subtitle: Text(
                    [
                      i.category,
                      if (i.timeWindow.isNotEmpty) i.timeWindow,
                      if (i.proofRequired) 'photo proof',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await ref.read(checklistProvider.notifier).removeItem(i.id);
                      } catch (error) {
                        if (ctx.mounted) toast(ctx, friendlyError(error));
                      }
                    },
                  ),
                ),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No items yet.')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () => _addItem(ctx, ref, items),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ],
      );
    },
  ),
);

Future<void> _addItem(BuildContext context, WidgetRef ref, List<ChecklistItem> items) async {
  final title = TextEditingController();
  final window = TextEditingController();
  final categories = {'Caretaker functions', ...items.map((i) => i.category), ...monitorAreas}.toList();
  var category = categories.first;
  var proof = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Add checklist item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Task *', hintText: 'e.g. Fire extinguisher pressure check'),
            ),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category (monitors see their categories)'),
              items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => category = v ?? category),
            ),
            TextField(
              controller: window,
              decoration: const InputDecoration(labelText: 'When', hintText: 'e.g. Before 9:00 AM'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: proof,
              onChanged: (v) => setState(() => proof = v ?? false),
              title: const Text('Photo proof required'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty), child: const Text('Add')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await ref
        .read(checklistProvider.notifier)
        .addItem(
          ChecklistItem(
            id: 'c${DateTime.now().microsecondsSinceEpoch}',
            title: title.text.trim(),
            category: category,
            timeWindow: window.text.trim(),
            proofRequired: proof,
          ),
        );
  } catch (error) {
    if (context.mounted) toast(context, friendlyError(error));
  }
}
