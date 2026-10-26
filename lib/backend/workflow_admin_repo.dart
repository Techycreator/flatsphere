import 'backend.dart';

class WorkflowStepInfo {
  const WorkflowStepInfo({required this.step, required this.label, required this.role, required this.type});
  final int step;
  final String label;
  final String? role;
  final String type;
}

class WorkflowInfo {
  const WorkflowInfo({required this.code, required this.name, required this.description, required this.flow});
  final String code;
  final String name;
  final String description;
  final List<WorkflowStepInfo> flow;

  bool get hasApprovalStep => flow.any((s) => s.type == 'approval' && s.role != null);
}

class ProcessInfo {
  const ProcessInfo({required this.code, required this.name, required this.reassignable, required this.workflowCode});
  final String code;
  final String name;
  final bool reassignable;
  final String workflowCode;
}

class WorkflowOverview {
  const WorkflowOverview({required this.workflows, required this.processes});
  final List<WorkflowInfo> workflows;
  final List<ProcessInfo> processes;
}

class WorkflowAdminRepo {
  static Future<WorkflowOverview> overview() async {
    final data = Map<String, dynamic>.from(await db.rpc('workflow_admin_overview') as Map);
    return WorkflowOverview(
      workflows: [
        for (final w in data['workflows'] as List)
          WorkflowInfo(
            code: w['code'] as String,
            name: w['name'] as String,
            description: w['description'] as String? ?? '',
            flow: [
              for (final s in w['flow'] as List)
                WorkflowStepInfo(
                  step: (s['step'] as num).toInt(),
                  label: s['label'] as String,
                  role: s['role'] as String?,
                  type: s['type'] as String,
                ),
            ],
          ),
      ],
      processes: [
        for (final p in data['processes'] as List)
          ProcessInfo(
            code: p['code'] as String,
            name: p['name'] as String,
            reassignable: p['reassignable'] as bool,
            workflowCode: p['workflow'] as String,
          ),
      ],
    );
  }

  static Future<void> assign(String process, String workflow) =>
      db.rpc('assign_process_workflow', params: {'p_process': process, 'p_workflow': workflow});
}
