import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/association_documents_repo.dart';
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final associationDocumentsProvider = FutureProvider.autoDispose<List<AssociationRegisterItem>>((ref) => AssociationDocumentsRepo.list());

class AssociationDocumentsScreen extends ConsumerWidget {
  const AssociationDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final canUpload = role == Role.president || role == Role.secretary;
    final documents = ref.watch(associationDocumentsProvider);

    Future<void> upload() async {
      final draft = await _documentDialog(context);
      if (draft == null || !context.mounted) return;
      try {
        final bytes = await draft.file.readAsBytes();
        await AssociationDocumentsRepo.upload(
          type: draft.type,
          title: draft.title,
          bytes: bytes,
          extension: draft.file.extension ?? '',
          issueDate: draft.issueDate,
          expiryDate: draft.expiryDate,
        );
        ref.invalidate(associationDocumentsProvider);
        if (context.mounted) toast(context, 'Document uploaded and previous version archived');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> open(AssociationRegisterItem document) async {
      try {
        final url = await AssociationDocumentsRepo.viewUrl(document.id);
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    return PageBody(
      maxWidth: 1000,
      children: [
        Row(
          children: [
            Expanded(child: Text('Association documents', style: Theme.of(context).textTheme.headlineSmall)),
            if (canUpload) FilledButton.icon(onPressed: upload, icon: const Icon(Icons.upload_file), label: const Text('Upload')),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Current approved association records are visible to members. Previous versions remain in the restricted archive.'),
        if (documents.isLoading) const LinearProgressIndicator(),
        if (documents.hasError) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${documents.error}'))),
        if (documents.hasValue && documents.value!.isEmpty)
          const EmptyState('No association documents have been published.', icon: Icons.folder_open_outlined),
        if (documents.hasValue)
          for (final document in documents.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(document.status == 'archived' ? Icons.archive_outlined : Icons.description_outlined),
                title: Text(document.name),
                subtitle: Text(
                  '${document.category} · v${document.details['version'] ?? 1}'
                  '${document.expiresOn == null ? '' : ' · expires ${dateFmt.format(document.expiresOn!)}'}'
                  '${document.status == 'archived' ? ' · archived' : ''}',
                ),
                trailing: IconButton(tooltip: 'Open document', onPressed: () => open(document), icon: const Icon(Icons.open_in_new)),
              ),
            ),
      ],
    );
  }
}

class _DocumentDraft {
  const _DocumentDraft({required this.type, required this.title, required this.file, this.issueDate, this.expiryDate});
  final String type;
  final String title;
  final PlatformFile file;
  final DateTime? issueDate;
  final DateTime? expiryDate;
}

Future<_DocumentDraft?> _documentDialog(BuildContext context) async {
  final title = TextEditingController();
  var type = associationDocumentTypes.keys.first;
  PlatformFile? file;
  DateTime? issueDate;
  DateTime? expiryDate;
  String? error;
  Future<DateTime?> pickDate(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(1990),
    lastDate: DateTime(2045),
  );
  final draft = await showDialog<_DocumentDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Upload association document'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Document type'),
                  items: [for (final entry in associationDocumentTypes.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
                  onChanged: (value) => setState(() => type = value ?? type),
                ),
                const SizedBox(height: 12),
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Document title *')),
                OutlinedButton.icon(
                  onPressed: () async {
                    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg','jpeg','png','webp','pdf']);
                    if (files.isEmpty || !dialogContext.mounted) return;
                    final size = await files.first.length();
                    if (!dialogContext.mounted) return;
                    if (size == null || size > maxSourceUploadBytes(files.first.extension ?? '')) {
                      return setState(() => error = 'File exceeds the supported source size');
                    }
                    setState(() => file = files.first);
                  },
                  icon: Icon(file == null ? Icons.attach_file : Icons.verified_outlined),
                  label: Text(file?.name ?? 'Choose photo or PDF *'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final date = await pickDate(issueDate);
                    if (date != null && dialogContext.mounted) setState(() => issueDate = date);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(issueDate == null ? 'Issue date (optional)' : 'Issued ${dateFmt.format(issueDate!)}'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final date = await pickDate(expiryDate);
                    if (date != null && dialogContext.mounted) setState(() => expiryDate = date);
                  },
                  icon: const Icon(Icons.event_busy_outlined),
                  label: Text(expiryDate == null ? 'Expiry date (optional)' : 'Expires ${dateFmt.format(expiryDate!)}'),
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
              if (title.text.trim().isEmpty || file == null) return setState(() => error = 'Document title and file are required');
              Navigator.pop(dialogContext, _DocumentDraft(type: type, title: title.text.trim(), file: file!, issueDate: issueDate, expiryDate: expiryDate));
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  return draft;
}
