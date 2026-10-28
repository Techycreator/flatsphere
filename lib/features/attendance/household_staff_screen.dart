import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/attendance_repo.dart';
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'household_staff_overview.dart';

final householdFlatsProvider = FutureProvider<List<(String id, String number)>>((ref) => AttendanceRepo.myResidentialFlats());
final householdWorkersProvider = FutureProvider<List<FlatHousekeepingWorker>>((ref) => AttendanceRepo.flatHousekeeping());

class HouseholdStaffScreen extends ConsumerWidget {
  const HouseholdStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    if (householdStaffViewerRoles.contains(role)) return const HouseholdStaffOverview();
    if (role != Role.owner && role != Role.resident) {
      return const PageBody(children: [EmptyState('Household staff is available to flat owners and residents.', icon: Icons.lock_outline)]);
    }
    final flats = ref.watch(householdFlatsProvider);
    final workers = ref.watch(householdWorkersProvider);
    return PageBody(
      maxWidth: 900,
      children: [
        Row(
          children: [
            Expanded(child: Text('Household staff', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: flats.hasValue && flats.value!.isNotEmpty ? () => _addWorker(context, ref, flats.value!) : null,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add housekeeping staff'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Record the worker, their usual visit hours, and whether they reside in your flat.'),
        const SizedBox(height: 12),
        if (flats.isLoading || workers.isLoading) const LinearProgressIndicator(),
        if (flats.hasError)
          Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${flats.error}'))),
        if (workers.hasError)
          Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${workers.error}'))),
        if (flats.hasValue && flats.value!.isEmpty)
          const EmptyState('No active owner/resident flat is linked to this account.', icon: Icons.home_outlined),
        if (workers.hasValue && workers.value!.isEmpty)
          const EmptyState('No household housekeeping staff added yet.', icon: Icons.cleaning_services_outlined),
        if (workers.hasValue)
          for (final worker in workers.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.cleaning_services_outlined)),
                title: Text('${worker.name} · ${worker.flatNumber}'),
                subtitle: Text(
                  '${worker.usualIn}–${worker.usualOut} · ${worker.residesInFlat ? 'Resides in flat' : 'Visits only'}',
                ),
                trailing: IconButton(
                  tooltip: 'View ID proof',
                  icon: const Icon(Icons.badge_outlined),
                  onPressed: () async {
                    try {
                      final url = await AttendanceRepo.housekeepingProofUrl(worker.idProofPath);
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    } catch (error) {
                      if (context.mounted) toast(context, '$error');
                    }
                  },
                ),
              ),
            ),
      ],
    );
  }
}

class _HousekeepingDraft {
  const _HousekeepingDraft({
    required this.flatId,
    required this.name,
    required this.usualIn,
    required this.usualOut,
    required this.residesInFlat,
    required this.proof,
  });

  final String flatId;
  final String name;
  final TimeOfDay usualIn;
  final TimeOfDay usualOut;
  final bool residesInFlat;
  final PlatformFile proof;
}

Future<void> _addWorker(BuildContext context, WidgetRef ref, List<(String id, String number)> flats) async {
  final draft = await _housekeepingDialog(context, flats);
  if (draft == null || !context.mounted) return;
  try {
    final bytes = await draft.proof.readAsBytes();
    await AttendanceRepo.addFlatHousekeeping(
      flatId: draft.flatId,
      name: draft.name,
      usualIn: _time(draft.usualIn),
      usualOut: _time(draft.usualOut),
      residesInFlat: draft.residesInFlat,
      proofBytes: bytes,
      proofExtension: draft.proof.extension ?? '',
    );
    ref.invalidate(householdWorkersProvider);
    if (context.mounted) toast(context, 'Housekeeping staff added');
  } catch (error) {
    if (context.mounted) toast(context, '$error');
  }
}

Future<_HousekeepingDraft?> _housekeepingDialog(
  BuildContext context,
  List<(String id, String number)> flats,
) async {
  final name = TextEditingController();
  var flatId = flats.first.$1;
  var usualIn = const TimeOfDay(hour: 9, minute: 0);
  var usualOut = const TimeOfDay(hour: 17, minute: 0);
  var resides = false;
  PlatformFile? proof;
  String? error;
  String displayTime(TimeOfDay value) => value.format(context);
  Future<TimeOfDay?> pickTime(TimeOfDay initial) => showTimePicker(context: context, initialTime: initial);
  final draft = await showDialog<_HousekeepingDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Add household housekeeping staff'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: flatId,
                  decoration: const InputDecoration(labelText: 'Flat'),
                  items: [for (final flat in flats) DropdownMenuItem(value: flat.$1, child: Text(flat.$2))],
                  onChanged: (value) => setState(() => flatId = value ?? flatId),
                ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name *')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final value = await pickTime(usualIn);
                          if (value != null && dialogContext.mounted) setState(() => usualIn = value);
                        },
                        icon: const Icon(Icons.login),
                        label: Text('In ${displayTime(usualIn)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final value = await pickTime(usualOut);
                          if (value != null && dialogContext.mounted) setState(() => usualOut = value);
                        },
                        icon: const Icon(Icons.logout),
                        label: Text('Out ${displayTime(usualOut)}'),
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: resides,
                  onChanged: (value) => setState(() => resides = value ?? false),
                  title: const Text('Resides in this flat'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final files = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
                    );
                    if (files.isEmpty || !dialogContext.mounted) return;
                    final size = await files.first.length();
                    if (!dialogContext.mounted) return;
                    if (size == null || size > maxSourceUploadBytes(files.first.extension ?? '')) {
                      return setState(() => error = 'File exceeds the supported source size');
                    }
                    setState(() => proof = files.first);
                  },
                  icon: Icon(proof == null ? Icons.upload_file_outlined : Icons.verified_outlined),
                  label: Text(proof?.name ?? 'Attach ID proof * (photos auto-compressed)'),
                ),
                if (error != null) Align(alignment: Alignment.centerLeft, child: Text(error!)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return setState(() => error = 'Name is required');
              if (proof == null) return setState(() => error = 'ID proof is required');
              Navigator.pop(
                dialogContext,
                _HousekeepingDraft(
                  flatId: flatId,
                  name: name.text.trim(),
                  usualIn: usualIn,
                  usualOut: usualOut,
                  residesInFlat: resides,
                  proof: proof!,
                ),
              );
            },
            child: const Text('Add worker'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  return draft;
}

String _time(TimeOfDay value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00';