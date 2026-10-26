import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/attendance_repo.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

const householdStaffViewerRoles = {
  Role.president,
  Role.vicePresident,
  Role.secretary,
  Role.jointSecretary,
  Role.treasurer,
  Role.ecMember,
  Role.caretaker,
};

final householdStaffOverviewProvider = FutureProvider.autoDispose<List<FlatHousekeepingWorker>>(
  (ref) => AttendanceRepo.householdStaffOverview(),
);

class HouseholdStaffOverview extends ConsumerWidget {
  const HouseholdStaffOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(householdStaffOverviewProvider);
    return PageBody(
      maxWidth: 900,
      children: [
        Text('Household staff', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Housekeeping staff registered by flat owners and residents (view only).'),
        const SizedBox(height: 12),
        if (workers.isLoading) const LinearProgressIndicator(),
        if (workers.hasError)
          Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${workers.error}'))),
        if (workers.hasValue && workers.value!.isEmpty)
          const EmptyState('No household staff registered yet.', icon: Icons.cleaning_services_outlined),
        if (workers.hasValue)
          for (final worker in workers.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.cleaning_services_outlined)),
                title: Text('${worker.name} · ${worker.flatNumber}'),
                subtitle: Text('${worker.usualIn}–${worker.usualOut} · ${worker.residesInFlat ? 'Resides in flat' : 'Visits only'}'),
              ),
            ),
      ],
    );
  }
}
