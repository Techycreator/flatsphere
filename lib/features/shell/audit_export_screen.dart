import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../backend/backend.dart' show backendEnabled;
import '../../backend/compliance_repo.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final auditLogProvider = FutureProvider.autoDispose((ref) => ComplianceRepo.auditLog());

/// Audit trail (President / Secretary / Admin) and full data export (President / Admin).
class AuditExportScreen extends ConsumerWidget {
  const AuditExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)?.activeRole;
    if (!backendEnabled || !const {Role.admin, Role.president, Role.secretary}.contains(role)) {
      return const PageBody(
        children: [EmptyState('Available to the President, Secretary or Admin in the cloud version.')],
      );
    }
    final log = ref.watch(auditLogProvider);
    return PageBody(
      maxWidth: 900,
      children: [
        Row(
          children: [
            Expanded(child: Text('Audit log', style: Theme.of(context).textTheme.headlineSmall)),
            if (role == Role.admin || role == Role.president)
              FilledButton.icon(
                onPressed: () => _export(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export all data'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Latest 300 actions: who did what and when. Entries cannot be edited or deleted.'),
        const SizedBox(height: 12),
        if (log.isLoading) const LinearProgressIndicator(),
        if (log.hasError) Text(friendlyError(log.error!)),
        if (log.hasValue)
          Card(
            child: Column(
              children: [
                for (final e in log.value!)
                  ListTile(
                    dense: true,
                    title: Text('${e.actor} · ${e.action} · ${e.entity}'),
                    subtitle: Text([dateTimeFmt.format(e.at), ?e.entityId].join(' · ')),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    try {
      final data = await ComplianceRepo.exportData();
      await FilePicker.saveFile(
        dialogTitle: 'Export association data',
        fileName: 'flatsphere-export-${DateFormat('yyyyMMdd').format(DateTime.now())}.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(data))),
      );
    } catch (error) {
      if (context.mounted) toast(context, friendlyError(error));
    }
  }
}
