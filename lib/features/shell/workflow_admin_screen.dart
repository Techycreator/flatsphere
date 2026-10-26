import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend.dart' show backendEnabled;
import '../../backend/workflow_admin_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/tr_text.dart';

String _flowText(WorkflowInfo w) {
  final parts = [
    for (final s in w.flow)
      if (s.type == 'approval' || s.type == 'cooling_period') s.label.replaceAll(RegExp(r' approval$'), ''),
  ];
  return parts.isEmpty ? '-' : parts.join(' \u2192 ');
}

class WorkflowAdminScreen extends ConsumerStatefulWidget {
  const WorkflowAdminScreen({super.key});

  @override
  ConsumerState<WorkflowAdminScreen> createState() => _WorkflowAdminScreenState();
}

class _WorkflowAdminScreenState extends ConsumerState<WorkflowAdminScreen> {
  WorkflowOverview? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (backendEnabled) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await WorkflowAdminRepo.overview();
      if (mounted) setState(() => _data = data);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign(ProcessInfo p, WorkflowInfo target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move ${p.name} to ${target.code}?'),
        content: Text(
          'New "${p.name}" requests will follow: ${_flowText(target)}. Requests already in progress are not changed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change workflow')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WorkflowAdminRepo.assign(p.code, target.code);
      await _load();
      if (mounted) toast(context, '${p.name} now uses ${target.code}.');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider)?.activeRole;
    if (role != Role.admin) {
      return const PageBody(children: [EmptyState('Only the Admin can manage approval workflows.', icon: Icons.lock_outline)]);
    }
    if (!backendEnabled) {
      return const PageBody(children: [EmptyState('Approval workflows are available when connected to the cloud.', icon: Icons.cloud_off_outlined)]);
    }
    final theme = Theme.of(context);
    final data = _data;
    final wide = MediaQuery.sizeOf(context).width >= 760;

    List<ProcessInfo> usedBy(WorkflowInfo w) => [for (final p in data!.processes) if (p.workflowCode == w.code) p];

    return PageBody(
      maxWidth: 1100,
      children: [
        Row(
          children: [
            Expanded(child: Text('Approval workflows', style: theme.textTheme.headlineSmall)),
            IconButton(onPressed: _loading ? null : _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Each workflow lists who approves and in what order. Move a process to a different workflow to change who approves its new requests.',
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) EmptyState(_error!, icon: Icons.error_outline),
        if (data != null) ...[
          SectionCard(
            title: 'Workflows',
            padding: false,
            child: wide
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Code')),
                        DataColumn(label: Text('Workflow')),
                        DataColumn(label: Text('Approval flow')),
                        DataColumn(label: Text('Processes using it')),
                      ],
                      rows: [
                        for (final w in data.workflows)
                          DataRow(
                            cells: [
                              DataCell(Text(w.code, style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text(w.name)),
                              DataCell(Text(_flowText(w))),
                              DataCell(Text(usedBy(w).isEmpty ? '-' : usedBy(w).map((p) => p.name).join(', '))),
                            ],
                          ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (final w in data.workflows)
                        ListTile(
                          title: Text('${w.code} \u00b7 ${w.name}'),
                          subtitle: Text(
                            'Flow: ${_flowText(w)}\nUsed by: ${usedBy(w).isEmpty ? '-' : usedBy(w).map((p) => p.name).join(', ')}',
                          ),
                          isThreeLine: true,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Process assignment',
            padding: false,
            child: Column(
              children: [
                for (final p in data.processes)
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.reassignable ? 'Currently uses ${p.workflowCode}' : 'Built-in rules, cannot be reassigned'),
                    trailing: p.reassignable
                        ? DropdownButton<String>(
                            value: data.workflows.any((w) => w.code == p.workflowCode) ? p.workflowCode : null,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final w in data.workflows)
                                if (w.hasApprovalStep) DropdownMenuItem(value: w.code, child: Text('${w.code} \u00b7 ${w.name}')),
                            ],
                            onChanged: (code) {
                              if (code == null || code == p.workflowCode) return;
                              _assign(p, data.workflows.firstWhere((w) => w.code == code));
                            },
                          )
                        : const Icon(Icons.lock_outline),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cooling-period and publish steps of a workflow are not copied; only its approval steps apply to the moved process.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }
}
