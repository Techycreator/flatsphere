import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/sla.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'complaint_tile.dart';

class ComplaintsScreen extends ConsumerStatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  ConsumerState<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends ConsumerState<ComplaintsScreen> {
  SlaColor? _sla;
  bool _openOnly = true;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = ref.watch(clockProvider);
    final role = ref.watch(sessionProvider)!.activeRole;
    var list = visibleComplaints(ref);
    final open = list.where((c) => c.status.isOpen).toList();
    int count(SlaColor col) => open.where((c) => slaFor(c, now).color == col).length;

    if (_openOnly) list = list.where((c) => c.status.isOpen).toList();
    if (_sla != null) list = list.where((c) => c.status.isOpen && slaFor(c, now).color == _sla).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) => '${c.title} ${c.id} ${c.flatNumber} ${c.category}'.toLowerCase().contains(q)).toList();
    }
    list.sort((a, b) => slaFor(b, now).color.index.compareTo(slaFor(a, now).color.index));

    return PageBody(children: [
      Row(children: [
        Expanded(child: Text(l.complaints, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        if (role != Role.auditor)
          FilledButton.icon(onPressed: () => context.go('/complaints/new'), icon: const Icon(Icons.add), label: Text(l.raiseComplaint)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(label: Text('All open (${open.length})'), selected: _sla == null, onSelected: (_) => setState(() => _sla = null)),
        for (final (col, name, color) in const [
          (SlaColor.green, 'Green', Color(0xFF16A34A)),
          (SlaColor.amber, 'Amber', Color(0xFFF59E0B)),
          (SlaColor.red, 'Red', Color(0xFFDC2626)),
        ])
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: color, radius: 6),
            label: Text('$name (${count(col)})'),
            selected: _sla == col,
            onSelected: (_) => setState(() => _sla = _sla == col ? null : col),
          ),
        FilterChip(label: const Text('Open only'), selected: _openOnly, onSelected: (v) => setState(() => _openOnly = v)),
      ]),
      const SizedBox(height: 12),
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by title, ticket, flat or category', isDense: true),
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 12),
      Card(
        child: list.isEmpty
            ? const EmptyState('No complaints match these filters')
            : Column(children: [
                for (final c in list) ...[ComplaintTile(complaint: c), if (c != list.last) const Divider(height: 1)],
              ]),
      ),
      const SizedBox(height: 8),
      Text('SLA (Medium): Green day 0 · Amber days 1–5 · Red after 5 days. Critical issues are measured in hours.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
