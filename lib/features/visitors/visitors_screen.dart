import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/directory_repo.dart';
import '../../backend/visitor_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final visitorRequestsProvider = FutureProvider.autoDispose<List<VisitorRequest>>((ref) => VisitorRepo.load());
final visitorFlatsProvider = FutureProvider.autoDispose<List<(String id, String number)>>((ref) => VisitorRepo.myFlats());
final vehicleSearchProvider = FutureProvider.autoDispose.family<List<VehicleContact>, String>(DirectoryRepo.searchVehicle);

class VisitorsScreen extends ConsumerWidget {
  const VisitorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final canHost = role == Role.owner || role == Role.resident;
    final canVerify = role == Role.security || role == Role.caretaker;
    final canSearchVehicles = role.isOfficeBearer || role == Role.ecMember || canVerify;
    final requests = ref.watch(visitorRequestsProvider);
    final flats = canHost ? ref.watch(visitorFlatsProvider) : null;

    Future<void> addRequest() async {
      if (flats == null || !flats.hasValue) return;
      final draft = await _visitorDialog(context, flats.value!);
      if (draft == null || !context.mounted) return;
      try {
        await VisitorRepo.create(
          flatId: draft.flatId,
          guestName: draft.name,
          guestPhone: draft.phone,
          expectedArrival: draft.arrival,
          vehicleNumber: draft.vehicle,
          note: draft.note,
        );
        ref.invalidate(visitorRequestsProvider);
        if (context.mounted) toast(context, 'Visitor request sent to the entry register');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> verify(VisitorRequest request, VisitorStatus status) async {
      try {
        await VisitorRepo.verify(request.id, status);
        ref.invalidate(visitorRequestsProvider);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    return PageBody(
      maxWidth: 1000,
      children: [
        Row(
          children: [
            Expanded(child: Text('Visitor register', style: Theme.of(context).textTheme.headlineSmall)),
            if (canHost)
              FilledButton.icon(
                onPressed: flats == null || flats.isLoading || flats.valueOrNull?.isEmpty == true ? null : addRequest,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Pre-register visitor'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          canHost
              ? 'Register an expected visit for your flat. Security and the caretaker can verify arrival.'
              : canVerify
              ? 'Check the guest name, host flat, arrival time and vehicle before verifying entry.'
              : 'Visitor requests are visible only within this association and to the relevant entry staff.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (canSearchVehicles) ...[
          const SizedBox(height: 12),
          const _VehicleLookupPanel(),
        ],
        if (flats?.hasError == true)
          Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${flats!.error}'))),
        const SizedBox(height: 12),
        if (requests.isLoading) const LinearProgressIndicator(),
        if (requests.hasError)
          Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${requests.error}'))),
        if (requests.hasValue && requests.value!.isEmpty)
          const EmptyState('No visitor requests found.', icon: Icons.directions_walk_outlined),
        if (requests.hasValue)
          for (final request in requests.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                isThreeLine: true,
                leading: CircleAvatar(
                  backgroundColor: _statusColor(request.status).withValues(alpha: 0.14),
                  child: Icon(_statusIcon(request.status), color: _statusColor(request.status)),
                ),
                title: Text('${request.guestName} · ${request.hostFlat}'),
                subtitle: Text(
                  '${dateTimeFmt.format(request.expectedAt)} · Host: ${request.hostName}'
                  '${request.guestPhone == null ? '' : ' · ${request.guestPhone}'}'
                  '${request.vehicleNumber == null ? '' : '\nVisitor vehicle: ${request.vehicleNumber}'}'
                  '${request.flatCarNumber == null && request.flatBikeNumber == null ? '' : '\nRegistered: ${[request.flatCarNumber, request.flatBikeNumber].whereType<String>().join(' · ')}'}'
                  '${request.parkingSlot == null ? '' : ' · slot ${request.parkingSlot}'}'
                  '${request.note.isEmpty ? '' : '\n${request.note}'}',
                ),
                trailing: canVerify
                    ? switch (request.status) {
                        VisitorStatus.expected => FilledButton.tonal(
                            onPressed: () => verify(request, VisitorStatus.checkedIn),
                            child: const Text('Verify entry'),
                          ),
                        VisitorStatus.checkedIn => FilledButton.tonal(
                            onPressed: () => verify(request, VisitorStatus.checkedOut),
                            child: const Text('Check out'),
                          ),
                        _ => Pill(request.status.label, color: _statusColor(request.status)),
                      }
                    : Pill(request.status.label, color: _statusColor(request.status)),
              ),
            ),
      ],
    );
  }
}

class _VehicleLookupPanel extends ConsumerStatefulWidget {
  const _VehicleLookupPanel();

  @override
  ConsumerState<_VehicleLookupPanel> createState() => _VehicleLookupPanelState();
}

class _VehicleLookupPanelState extends ConsumerState<_VehicleLookupPanel> {
  final _registration = TextEditingController();
  String? _submitted;
  bool _exporting = false;

  @override
  void dispose() {
    _registration.dispose();
    super.dispose();
  }

  void _search() {
    final value = _registration.text.trim().toUpperCase();
    if (value.length < 3) {
      toast(context, AppLocalizations.of(context).enterThreeVehicleChars);
      return;
    }
    setState(() => _submitted = value);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final vehicles = await DirectoryRepo.vehicleRegister();
      String csvCell(String value) => '"${value.replaceAll('"', '""')}"';
      final csv = [
        'vehicle_number,vehicle_type,flat_number,parking_slot',
        for (final vehicle in vehicles)
          [vehicle.registrationNumber, vehicle.vehicleType, vehicle.flatNumber, vehicle.parkingSlot ?? '']
              .map(csvCell)
              .join(','),
      ].join('\r\n');
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Export boom-barrier vehicle list',
        fileName: 'flatsphere-vehicle-register.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
      if (mounted && saved != null) toast(context, 'Exported ${vehicles.length} registered vehicles');
    } catch (error) {
      if (mounted) toast(context, 'Could not export vehicle list: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results = _submitted == null ? null : ref.watch(vehicleSearchProvider(_submitted!));
    return SectionCard(
      title: l.vehicleLookup,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _registration,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    labelText: l.vehicleRegistration,
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: l.searchVehicleNumber,
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined),
              label: Text(l.exportBoomBarrierCsv),
            ),
          ),
          if (results != null) ...[
            const SizedBox(height: 8),
            if (results.isLoading) const LinearProgressIndicator(),
            if (results.hasError) Text(l.vehicleSearchFailed('${results.error}')),
            if (results.hasValue && results.value!.isEmpty)
              Text(l.noRegisteredVehicleMatch),
            if (results.hasValue)
              for (final contact in results.value!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(contact.vehicleType == 'car' ? Icons.directions_car_outlined : Icons.two_wheeler_outlined),
                  title: Text('${contact.registrationNumber} · Flat ${contact.flatNumber}'),
                  subtitle: Text(
                    '${contact.vehicleType == 'car' ? 'Car' : 'Bike'} · ${contact.personName ?? l.noActiveOccupant}'
                    '${contact.phone == null ? ' · ${l.noPhoneOnRecord}' : ' · ${contact.phone}'}',
                  ),
                  trailing: contact.phone == null
                      ? null
                      : IconButton(
                          tooltip: 'Call ${contact.personName ?? 'flat contact'}',
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: contact.phone)),
                          icon: const Icon(Icons.call_outlined),
                        ),
                ),
          ],
        ],
      ),
    );
  }
}

class _VisitorDraft {
  const _VisitorDraft({required this.flatId, required this.name, required this.arrival, required this.phone, required this.vehicle, required this.note});
  final String flatId;
  final String name;
  final DateTime arrival;
  final String phone;
  final String vehicle;
  final String note;
}

Future<_VisitorDraft?> _visitorDialog(BuildContext context, List<(String id, String number)> flats) async {
  if (flats.isEmpty) return null;
  final name = TextEditingController();
  final phone = TextEditingController();
  final vehicle = TextEditingController();
  final note = TextEditingController();
  var flatId = flats.first.id;
  var arrival = DateTime.now().add(const Duration(hours: 1));
  String? error;
  final draft = await showDialog<_VisitorDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Pre-register visitor'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: flatId,
                  decoration: const InputDecoration(labelText: 'Flat'),
                  items: [for (final flat in flats) DropdownMenuItem(value: flat.id, child: Text(flat.number))],
                  onChanged: (value) => setState(() => flatId = value ?? flatId),
                ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Visitor name *')),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vehicle,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Car / bike number (optional)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: dialogContext,
                      initialDate: arrival,
                      firstDate: DateUtils.dateOnly(DateTime.now()),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !dialogContext.mounted) return;
                    final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.fromDateTime(arrival));
                    if (time != null && dialogContext.mounted) {
                      setState(() => arrival = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Arrival ${dateTimeFmt.format(arrival)}'),
                ),
                const SizedBox(height: 8),
                TextField(controller: note, maxLength: 240, decoration: const InputDecoration(labelText: 'Note for entry staff')),
                if (error != null) Align(alignment: Alignment.centerLeft, child: Text(error!)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return setState(() => error = 'Visitor name is required');
              Navigator.pop(
                dialogContext,
                _VisitorDraft(
                  flatId: flatId,
                  name: name.text.trim(),
                  arrival: arrival,
                  phone: phone.text.trim(),
                  vehicle: vehicle.text.trim().toUpperCase(),
                  note: note.text.trim(),
                ),
              );
            },
            child: const Text('Save visitor'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  phone.dispose();
  vehicle.dispose();
  note.dispose();
  return draft;
}

Color _statusColor(VisitorStatus status) => switch (status) {
  VisitorStatus.expected => AppColors.amber,
  VisitorStatus.checkedIn => AppColors.green,
  VisitorStatus.checkedOut => Colors.blueGrey,
  VisitorStatus.cancelled => AppColors.red,
};

IconData _statusIcon(VisitorStatus status) => switch (status) {
  VisitorStatus.expected => Icons.schedule,
  VisitorStatus.checkedIn => Icons.login,
  VisitorStatus.checkedOut => Icons.logout,
  VisitorStatus.cancelled => Icons.cancel_outlined,
};
