import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/vendors_repo.dart';
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../models/models.dart';
import '../../models/vendor.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final vendorsProvider = FutureProvider.autoDispose<List<AssociationVendor>>((ref) => VendorsRepo.list());

class VendorAmcScreen extends ConsumerWidget {
  const VendorAmcScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final canManage = role == Role.admin || role == Role.president || role == Role.secretary;
    final vendors = ref.watch(vendorsProvider);

    Future<void> editVendor([AssociationVendor? vendor]) async {
      final saved = await _vendorDialog(context, vendor);
      if (saved == null) return;
      try {
        await VendorsRepo.save(
          id: vendor?.id,
          name: saved.name,
          serviceCategory: saved.category,
          contactName: saved.contactName,
          phone: saved.phone,
          email: saved.email,
          address: saved.address,
          securityDeposit: saved.deposit,
          escalationContacts: saved.escalations,
        );
        ref.invalidate(vendorsProvider);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> addContract(AssociationVendor vendor) async {
      final draft = await _contractDialog(context);
      if (draft == null) return;
      try {
        await VendorsRepo.addContract(
          vendorId: vendor.id,
          serviceName: draft.serviceName,
          startDate: draft.startDate,
          endDate: draft.endDate,
          renewalNoticeDays: draft.noticeDays,
          annualCost: draft.annualCost,
        );
        ref.invalidate(vendorsProvider);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> addDocument(AssociationVendor vendor, [VendorAmcContract? contract]) async {
      final draft = await _documentDialog(context);
      if (draft == null) return;
      try {
        await VendorsRepo.uploadDocument(
          vendorId: vendor.id,
          contractId: contract?.id,
          type: draft.type,
          title: draft.title,
          bytes: await draft.file.readAsBytes(),
          extension: draft.file.extension ?? '',
          expiresOn: draft.expiresOn,
        );
        ref.invalidate(vendorsProvider);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> openDocument(VendorDocument document) async {
      try {
        final url = await VendorsRepo.documentUrl(document.id);
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    return PageBody(
      maxWidth: 1100,
      children: [
        Row(
          children: [
            Expanded(child: Text('Vendors & AMCs', style: Theme.of(context).textTheme.headlineSmall)),
            if (canManage)
              FilledButton.icon(onPressed: () => editVendor(), icon: const Icon(Icons.add), label: const Text('Add vendor')),
          ],
        ),
        const SizedBox(height: 8),
        if (vendors.isLoading) const LinearProgressIndicator(),
        if (vendors.hasError) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${vendors.error}'))),
        if (vendors.hasValue && vendors.value!.isEmpty)
          const EmptyState('No vendors or AMCs registered.', icon: Icons.business_outlined),
        if (vendors.hasValue)
          for (final vendor in vendors.value!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: Icon(vendor.active ? Icons.business_outlined : Icons.business_center_outlined),
                title: Text(vendor.name),
                subtitle: Text('${vendor.serviceCategory} · ${vendor.phone.isEmpty ? 'No phone' : vendor.phone}'),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Pill(vendor.active ? 'Active' : 'Inactive', color: vendor.active ? AppColors.green : AppColors.amber),
                    if (canManage)
                      PopupMenuButton<String>(
                        tooltip: 'Vendor actions',
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await editVendor(vendor);
                          } else {
                            try {
                              await VendorsRepo.setActive(vendor.id, !vendor.active);
                              ref.invalidate(vendorsProvider);
                            } catch (error) {
                              if (context.mounted) toast(context, '$error');
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit vendor')),
                          PopupMenuItem(value: 'active', child: Text(vendor.active ? 'Mark inactive' : 'Reactivate')),
                        ],
                      ),
                  ],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        if (vendor.contactName.isNotEmpty) Text('Contact: ${vendor.contactName}'),
                        if (vendor.email.isNotEmpty) Text('Email: ${vendor.email}'),
                        if (vendor.address.isNotEmpty) Text('Address: ${vendor.address}'),
                        Text('Security deposit: ${inr.format(vendor.securityDeposit)}'),
                        if (vendor.escalationContacts.isNotEmpty) Text('Escalation: ${vendor.escalationContacts.join(' · ')}'),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(child: Text('AMC contracts', style: Theme.of(context).textTheme.titleMedium)),
                      if (canManage)
                        IconButton(
                          tooltip: 'Add AMC contract',
                          onPressed: () => addContract(vendor),
                          icon: const Icon(Icons.add),
                        ),
                    ],
                  ),
                  if (vendor.contracts.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No AMC contracts')),
                  for (final contract in vendor.contracts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.handshake_outlined),
                      title: Text(contract.serviceName),
                      subtitle: Text(
                        '${dateFmt.format(contract.startDate)} – ${dateFmt.format(contract.endDate)}'
                        ' · reminder ${contract.renewalNoticeDays} days before'
                        '${contract.annualCost == null ? '' : ' · ${inr.format(contract.annualCost)} / year'}',
                      ),
                      trailing: Wrap(
                        children: [
                          if (canManage)
                            IconButton(
                              tooltip: contract.active ? 'End contract' : 'Reactivate contract',
                              onPressed: () async {
                                try {
                                  await VendorsRepo.setContractActive(contract.id, !contract.active);
                                  ref.invalidate(vendorsProvider);
                                } catch (error) {
                                  if (context.mounted) toast(context, '$error');
                                }
                              },
                              icon: Icon(contract.active ? Icons.pause_circle_outline : Icons.play_circle_outline),
                            ),
                          if (canManage)
                            IconButton(
                              tooltip: 'Attach contract document',
                              onPressed: () => addDocument(vendor, contract),
                              icon: const Icon(Icons.attach_file),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(child: Text('Documents', style: Theme.of(context).textTheme.titleMedium)),
                      if (canManage)
                        IconButton(
                          tooltip: 'Attach insurance document',
                          onPressed: () => addDocument(vendor),
                          icon: const Icon(Icons.upload_file),
                        ),
                    ],
                  ),
                  if (vendor.documents.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No contract or insurance documents')),
                  for (final document in vendor.documents)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(document.type == 'insurance' ? Icons.shield_outlined : Icons.description_outlined),
                      title: Text(document.title),
                      subtitle: Text('${document.type == 'insurance' ? 'Insurance' : 'Contract'}${document.expiresOn == null ? '' : ' · expires ${dateFmt.format(document.expiresOn!)}'}'),
                      trailing: IconButton(
                        tooltip: 'Open document',
                        onPressed: () => openDocument(document),
                        icon: const Icon(Icons.open_in_new),
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

class _VendorDraft {
  const _VendorDraft(this.name, this.category, this.contactName, this.phone, this.email, this.address, this.deposit, this.escalations);
  final String name;
  final String category;
  final String contactName;
  final String phone;
  final String email;
  final String address;
  final num deposit;
  final List<String> escalations;
}

Future<_VendorDraft?> _vendorDialog(BuildContext context, AssociationVendor? vendor) async {
  const categories = ['Lift', 'STP', 'Generator', 'Fire Safety', 'CCTV', 'Other'];
  return showDialog<_VendorDraft>(context: context, builder: (_) => _VendorDialog(vendor: vendor, categories: categories));
}

class _VendorDialog extends StatefulWidget {
  const _VendorDialog({required this.vendor, required this.categories});
  final AssociationVendor? vendor;
  final List<String> categories;

  @override
  State<_VendorDialog> createState() => _VendorDialogState();
}

class _VendorDialogState extends State<_VendorDialog> {
  late final _name = TextEditingController(text: widget.vendor?.name);
  late final _contact = TextEditingController(text: widget.vendor?.contactName);
  late final _phone = TextEditingController(text: widget.vendor?.phone);
  late final _email = TextEditingController(text: widget.vendor?.email);
  late final _address = TextEditingController(text: widget.vendor?.address);
  late final _deposit = TextEditingController(text: widget.vendor?.securityDeposit.toString());
  late final _escalations = TextEditingController(text: widget.vendor?.escalationContacts.join('\n'));
  late String _category = widget.vendor?.serviceCategory ?? widget.categories.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _deposit.dispose();
    _escalations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.vendor == null ? 'Add vendor' : 'Edit vendor'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null) _dialogError(_error!),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Vendor name *')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Service category'),
              items: [for (final item in widget.categories) DropdownMenuItem(value: item, child: Text(item))],
              onChanged: (value) => setState(() => _category = value ?? _category),
            ),
            TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Primary contact')),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address')),
            TextField(controller: _deposit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Security deposit')),
            TextField(controller: _escalations, maxLines: 3, decoration: const InputDecoration(labelText: 'Escalation contacts (one per line)')),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save vendor')),
        ],
      );

  void _save() {
    final amount = num.tryParse(_deposit.text.trim().isEmpty ? '0' : _deposit.text.trim());
    if (_name.text.trim().isEmpty || amount == null || amount < 0) {
      setState(() => _error = 'Enter a vendor name and a valid non-negative deposit');
      return;
    }
    Navigator.pop(context, _VendorDraft(
      _name.text.trim(),
      _category,
      _contact.text.trim(),
      _phone.text.trim(),
      _email.text.trim(),
      _address.text.trim(),
      amount,
      _escalations.text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList(),
    ));
  }
}

class _ContractDraft {
  const _ContractDraft(this.serviceName, this.startDate, this.endDate, this.noticeDays, this.annualCost);
  final String serviceName;
  final DateTime startDate;
  final DateTime endDate;
  final int noticeDays;
  final num? annualCost;
}

Future<_ContractDraft?> _contractDialog(BuildContext context) async {
  return showDialog<_ContractDraft>(context: context, builder: (_) => const _ContractDialog());
}

class _ContractDialog extends StatefulWidget {
  const _ContractDialog();

  @override
  State<_ContractDialog> createState() => _ContractDialogState();
}

class _ContractDialogState extends State<_ContractDialog> {
  final _service = TextEditingController();
  final _cost = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 365));
  int _notice = 90;
  String? _error;

  @override
  void dispose() { _service.dispose(); _cost.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add AMC contract'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) _dialogError(_error!),
          TextField(controller: _service, decoration: const InputDecoration(labelText: 'Service / equipment *')),
          TextButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.event_outlined), label: Text('Starts ${dateFmt.format(_start)}')),
          TextButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event_busy_outlined), label: Text('Ends ${dateFmt.format(_end)}')),
          DropdownButtonFormField<int>(
            initialValue: _notice,
            decoration: const InputDecoration(labelText: 'Renewal reminder lead time'),
            items: const [30, 60, 90, 120, 180].map((days) => DropdownMenuItem(value: days, child: Text('$days days'))).toList(),
            onChanged: (value) => setState(() => _notice = value ?? _notice),
          ),
          TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Annual cost (optional)')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _save, child: const Text('Save contract'))],
      );

  Future<void> _pickDate(bool start) async {
    final current = start ? _start : _end;
    final date = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2000), lastDate: DateTime(2045));
    if (date != null && mounted) setState(() { if (start) { _start = date; } else { _end = date; } });
  }

  void _save() {
    final annualCost = _cost.text.trim().isEmpty ? null : num.tryParse(_cost.text.trim());
    if (_service.text.trim().isEmpty || _end.isBefore(_start) || (_cost.text.trim().isNotEmpty && (annualCost == null || annualCost < 0))) {
      setState(() => _error = 'Enter a service, valid dates, and a non-negative annual cost');
      return;
    }
    Navigator.pop(context, _ContractDraft(_service.text.trim(), _start, _end, _notice, annualCost));
  }
}

class _DocumentDraft {
  const _DocumentDraft(this.type, this.title, this.file, this.expiresOn);
  final String type;
  final String title;
  final PlatformFile file;
  final DateTime? expiresOn;
}

Future<_DocumentDraft?> _documentDialog(BuildContext context) async {
  return showDialog<_DocumentDraft>(context: context, builder: (_) => const _DocumentDialog());
}

class _DocumentDialog extends StatefulWidget {
  const _DocumentDialog();

  @override
  State<_DocumentDialog> createState() => _DocumentDialogState();
}

class _DocumentDialogState extends State<_DocumentDialog> {
  final _title = TextEditingController();
  String _type = 'contract';
  PlatformFile? _file;
  DateTime? _expiry;
  String? _error;

  @override
  void dispose() { _title.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Attach vendor document'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) _dialogError(_error!),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Document type'),
            items: const [DropdownMenuItem(value: 'contract', child: Text('Contract')), DropdownMenuItem(value: 'insurance', child: Text('Insurance'))],
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Document title *')),
          OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.attach_file), label: Text(_file?.name ?? 'Choose photo or PDF *')),
          TextButton.icon(onPressed: _pickExpiry, icon: const Icon(Icons.event_busy_outlined), label: Text(_expiry == null ? 'Expiry date (optional)' : 'Expires ${dateFmt.format(_expiry!)}')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _save, child: const Text('Attach'))],
      );

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    if (files.isEmpty || !mounted) return;
    final size = await files.first.length();
    if (!mounted) return;
    if (size == null || size > maxSourceUploadBytes(files.first.extension ?? '')) {
      setState(() => _error = 'File exceeds the supported source size');
      return;
    }
    setState(() { _file = files.first; _error = null; });
  }

  Future<void> _pickExpiry() async {
    final date = await showDatePicker(context: context, initialDate: _expiry ?? DateTime.now(), firstDate: DateTime(1990), lastDate: DateTime(2045));
    if (date != null && mounted) setState(() => _expiry = date);
  }

  void _save() {
    if (_title.text.trim().isEmpty || _file == null) {
      setState(() => _error = 'Document title and file are required');
      return;
    }
    Navigator.pop(context, _DocumentDraft(_type, _title.text.trim(), _file!, _expiry));
  }
}

Widget _dialogError(String message) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(alignment: Alignment.centerLeft, child: Text(message, style: const TextStyle(color: Colors.red))),
    );
