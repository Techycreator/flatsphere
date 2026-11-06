import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend.dart';
import '../../backend/finance_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/tr_text.dart';

final _setupStatusProvider = FutureProvider.autoDispose<({bool owners, bool schedule})>((ref) async {
  final s = ref.watch(sessionProvider);
  final associationId = s?.user.associationId;
  if (!backendEnabled || associationId == null) return (owners: true, schedule: true);
  final owners = await db
      .from('memberships')
      .select('id')
      .eq('association_id', associationId)
      .eq('role', 'owner')
      .isFilter('ended_at', null)
      .limit(1);
  final schedule = await FinanceRepo.duesSchedule();
  return (owners: owners.isNotEmpty, schedule: schedule?['enabled'] == true);
});

/// First-time setup steps for a new association; hidden once every step is done.
class SetupChecklistCard extends ConsumerWidget {
  const SetupChecklistCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)?.activeRole;
    if (!backendEnabled ||
        !const {Role.admin, Role.president, Role.secretary, Role.treasurer}.contains(role)) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(_setupStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final dues = ref.watch(duesProvider);
    final steps = [
      (dues.flats.isNotEmpty, 'Add flats (number, type, sq. ft.)', 'Flats & people', '/directory'),
      (status.owners, 'Add owners and residents to each flat', 'Flats & people → invite by email', '/directory'),
      (dues.opening != null, 'Set the opening bank balance', 'Finance → Dues → Set opening balance', '/finance'),
      (
        dues.lines.isNotEmpty,
        'Raise the first dues by category',
        'Finance → Dues → More → Raise dues (Maintenance, Corpus fund, Lift AMC…)',
        '/finance',
      ),
      (status.schedule, 'Turn on automatic monthly maintenance bills', 'Finance → Dues → More → Automatic monthly bills', '/finance'),
    ];
    final done = steps.where((x) => x.$1).length;
    if (done == steps.length) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        title: 'Getting started ($done of ${steps.length} done)',
        padding: false,
        child: Column(
          children: [
            for (final (ok, title, where, route) in steps)
              ListTile(
                dense: true,
                leading: Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: ok ? Colors.green : null,
                ),
                title: Text(title),
                subtitle: Text(where),
                onTap: ok ? null : () => context.go(route),
              ),
            const ListTile(
              dense: true,
              leading: Icon(Icons.info_outline),
              title: Text('Every month: record bank interest under Finance → Income (source: Bank interest)'),
            ),
          ],
        ),
      ),
    );
  }
}
