import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../backend/backend.dart' show backendEnabled;
import '../../backend/bulk_import.dart';
import '../../backend/compliance_repo.dart';
import '../../backend/directory_repo.dart';
import '../../backend/export_bundle.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/directory_state.dart';
import '../../widgets/common.dart';

/// One-time bulk load from another system (CSV) and full data export when leaving Flatsphere.
class DataToolsScreen extends ConsumerStatefulWidget {
  const DataToolsScreen({super.key});

  @override
  ConsumerState<DataToolsScreen> createState() => _DataToolsScreenState();
}

class _DataToolsScreenState extends ConsumerState<DataToolsScreen> {
  List<ImportRow<FlatInfo>>? _flats;
  List<ImportRow<Person>>? _members;
  String? _flatsError;
  String? _membersError;
  String _progress = '';
  bool _busy = false;
  final _report = <String>[];

  Future<void> _saveText(String name, String csv) async {
    await FilePicker.saveFile(
      dialogTitle: 'Save $name',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
    );
  }

  Future<String?> _pickCsv() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['csv']);
    if (files.isEmpty) return null;
    final file = files.first;
    if ((await file.length() ?? 0) > 2 * 1024 * 1024) {
      if (mounted) toast(context, 'CSV must be 2 MB or smaller');
      return null;
    }
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  Future<void> _loadFlats() async {
    final text = await _pickCsv();
    if (text == null) return;
    try {
      setState(() {
        _flats = parseFlatsCsv(text);
        _flatsError = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _flats = null;
        _flatsError = e.message;
      });
    }
  }

  Future<void> _loadMembers() async {
    final text = await _pickCsv();
    if (text == null) return;
    try {
      setState(() {
        _members = parseMembersCsv(text);
        _membersError = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _members = null;
        _membersError = e.message;
      });
    }
  }

  Future<void> _importFlats() async {
    final rows = [for (final r in _flats!) if (r.value != null) r];
    setState(() {
      _busy = true;
      _report.clear();
    });
    final notifier = ref.read(directoryProvider.notifier);
    await notifier.refresh();
    final existing = {for (final f in ref.read(directoryProvider).flats) f.number.toLowerCase(): f.id};
    var done = 0;
    for (final r in rows) {
      final f = r.value!;
      setState(() => _progress = 'Flats ${done + 1} of ${rows.length}');
      try {
        final id = existing[f.number.toLowerCase()];
        await DirectoryRepo.saveFlat(
          FlatInfo(
            id: id,
            number: f.number,
            block: f.block,
            type: f.type,
            sqft: f.sqft,
            occupancy: f.occupancy,
            carNumber: f.carNumber,
            bikeNumber: f.bikeNumber,
            parkingSlot: f.parkingSlot,
          ),
        );
        done++;
      } catch (e) {
        _report.add('Line ${r.line} (${f.number}): ${friendlyError(e)}');
      }
    }
    await notifier.refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = '';
      _report.insert(0, 'Flats saved: $done of ${rows.length}');
    });
  }

  Future<void> _importMembers() async {
    final rows = [for (final r in _members!) if (r.value != null) r];
    setState(() {
      _busy = true;
      _report.clear();
    });
    var done = 0;
    for (final r in rows) {
      setState(() => _progress = 'People ${done + 1} of ${rows.length}');
      try {
        await DirectoryRepo.add(r.value!);
        done++;
      } catch (e) {
        _report.add('Line ${r.line} (${r.value!.email}): ${friendlyError(e)}');
      }
    }
    await ref.read(directoryProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = '';
      _report.insert(0, 'People added or invited: $done of ${rows.length}');
    });
  }

  Future<void> _exportZip() async {
    setState(() => _busy = true);
    try {
      final data = await ComplianceRepo.exportData();
      await FilePicker.saveFile(
        dialogTitle: 'Export association data',
        fileName: 'flatsphere-export-${DateFormat('yyyyMMdd').format(DateTime.now())}.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: buildExportZip(data),
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview<T>(List<ImportRow<T>>? rows, String? error, VoidCallback onImport, String label) {
    if (error != null) return Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error));
    if (rows == null) return const SizedBox.shrink();
    final bad = rows.where((r) => r.error != null).toList();
    final good = rows.length - bad.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$good valid row(s), ${bad.length} with problems'),
        for (final r in bad.take(20)) Text('Line ${r.line}: ${r.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (bad.length > 20) Text('…and ${bad.length - 20} more'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy || good == 0 ? null : onImport,
          icon: const Icon(Icons.upload_outlined),
          label: Text(label),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider)?.activeRole;
    if (!backendEnabled || !const {Role.admin, Role.president, Role.secretary}.contains(role)) {
      return const PageBody(children: [EmptyState('Available to the Admin, President or Secretary in the cloud version.')]);
    }
    final canExport = role == Role.admin || role == Role.president;
    return PageBody(
      maxWidth: 820,
      children: [
        Text('Data import & export', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        SectionCard(
          title: '1. Load flats (do this first)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CSV columns: number (required), block, type, sqft, occupancy (owner_occupied, rented or vacant), car_number, bike_number, parking_slot. '
                'Existing flats with the same number are updated.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _saveText('flatsphere-flats-template.csv', toCsv(flatsTemplateHeader, flatsTemplateSample)),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download template'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _loadFlats,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _preview(_flats, _flatsError, _importFlats, 'Import flats'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '2. Load owners, residents and office bearers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CSV columns: full_name, email, role (owner, resident, president, secretary, treasurer, vice_president, joint_secretary, '
                'joint_treasurer, ec_member, monitor, caretaker, security, auditor), mobile, flat_number (required for owner and resident). '
                'People who already have an account get the role at once; others receive an invite and join when they sign in with that email. '
                'At most 400 new invites per day.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _saveText('flatsphere-people-template.csv', toCsv(membersTemplateHeader, membersTemplateSample)),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download template'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _loadMembers,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _preview(_members, _membersError, _importMembers, 'Import people'),
            ],
          ),
        ),
        if (_busy || _report.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Result',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_progress.isNotEmpty) Text(_progress),
                for (final line in _report) Text(line),
              ],
            ),
          ),
        ],
        if (canExport) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Export everything (leaving Flatsphere or backup)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A ZIP with one CSV per table, the full data as JSON and a README. Uploaded files and ID proofs are not included; '
                  'download those from their screens first.',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _exportZip,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Export all data (ZIP)'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
