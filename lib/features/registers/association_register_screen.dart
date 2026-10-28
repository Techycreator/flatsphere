import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../backend/register_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'vendor_amc_screen.dart';

final associationRegisterProvider = FutureProvider.autoDispose<List<AssociationRegisterItem>>((ref) => RegisterRepo.list());
final expiringRegisterProvider = FutureProvider.autoDispose<List<AssociationRegisterItem>>((ref) => RegisterRepo.expiringSoon());

const _types = [
  ('asset', 'Asset'),
  ('insurance', 'Insurance'),
  ('compliance', 'Compliance document'),
  ('conflict', 'Conflict of interest'),
  ('other', 'Other (name it in Category)'),
];

class AssociationRegisterScreen extends ConsumerWidget {
  const AssociationRegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final canSubmit = role.isOfficeBearer;
    final items = ref.watch(associationRegisterProvider);
    final expiring = ref.watch(expiringRegisterProvider);

    Future<void> addRecord() async {
      final draft = await _recordDialog(context);
      if (draft == null || !context.mounted) return;
      try {
        final requestRef = ref.read(approvalsProvider.notifier).nextId();
        await RegisterRepo.submit(
          type: draft.type,
          name: draft.name,
          category: draft.category,
          vendor: draft.vendor,
          purchaseDate: draft.purchaseDate,
          warrantyEnd: draft.warrantyEnd,
          amcEnd: draft.amcEnd,
          expiresOn: draft.expiresOn,
          expectedLifeYears: draft.expectedLifeYears,
          replacementCost: draft.replacementCost,
          details: {'notes': draft.details},
          requestRef: requestRef,
        );
        ref.invalidate(associationRegisterProvider);
        ref.invalidate(expiringRegisterProvider);
        await ref.read(approvalsProvider.notifier).refresh();
        if (context.mounted) toast(context, '$requestRef sent for President approval');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'Registers'), Tab(text: 'Expiry dashboard'), Tab(text: 'Vendors & AMCs')],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                PageBody(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Assets & records', style: Theme.of(context).textTheme.headlineSmall)),
                        if (canSubmit)
                          FilledButton.icon(onPressed: addRecord, icon: const Icon(Icons.add), label: const Text('Add record')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('New records become active only after approval and remain associated with this community.'),
                    if (items.isLoading) const LinearProgressIndicator(),
                    if (items.hasError) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${items.error}'))),
                    if (items.hasValue && items.value!.isEmpty)
                      const EmptyState('No register records yet.', icon: Icons.inventory_2_outlined),
                    if (items.hasValue)
                      for (final item in items.value!) _registerTile(item),
                  ],
                ),
                PageBody(
                  children: [
                    Text('Expiry dashboard', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('Approved items with a warranty, AMC, or certificate expiry in the next 90 days.'),
                    if (expiring.isLoading) const LinearProgressIndicator(),
                    if (expiring.hasError)
                      Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${expiring.error}'))),
                    if (expiring.hasValue && expiring.value!.isEmpty)
                      const EmptyState('Nothing expires in the next 90 days.', icon: Icons.event_available_outlined),
                    if (expiring.hasValue)
                      for (final item in expiring.value!) _registerTile(item, expiryOnly: true),
                  ],
                ),
                const VendorAmcScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _registerTile(AssociationRegisterItem item, {bool expiryOnly = false}) {
  final dates = [
    if (item.expiresOn != null) 'Expires ${dateFmt.format(item.expiresOn!)}',
    if (item.amcEnd != null) 'AMC to ${dateFmt.format(item.amcEnd!)}',
    if (item.warrantyEnd != null) 'Warranty to ${dateFmt.format(item.warrantyEnd!)}',
  ];
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(
        item.type == 'insurance' ? Icons.shield_outlined : item.type == 'compliance' ? Icons.verified_outlined : Icons.inventory_2_outlined,
      ),
      title: Text(item.name),
      subtitle: Text([
        item.category,
        if (item.vendor != null) item.vendor!,
        if (item.purchaseDate != null) 'Purchased ${dateFmt.format(item.purchaseDate!)}',
        if (item.expectedLifeYears != null) 'Life ${item.expectedLifeYears}y',
        if (item.replacementCost != null) 'Replacement ${inr.format(item.replacementCost)}',
        ...dates,
        if (item.type == 'conflict') item.details['notes'] as String? ?? '',
        if (!expiryOnly) 'Status: ${item.status}',
      ].where((s) => s.isNotEmpty).join(' · ')),
      trailing: Pill(item.status == 'active' ? 'Active' : 'Pending approval', color: item.status == 'active' ? AppColors.green : AppColors.amber),
    ),
  );
}

class _RegisterDraft {
  const _RegisterDraft({
    required this.type,
    required this.name,
    required this.category,
    required this.vendor,
    required this.purchaseDate,
    required this.warrantyEnd,
    required this.amcEnd,
    required this.expiresOn,
    required this.expectedLifeYears,
    required this.replacementCost,
    required this.details,
  });
  final String type;
  final String name;
  final String category;
  final String vendor;
  final DateTime? purchaseDate;
  final DateTime? warrantyEnd;
  final DateTime? amcEnd;
  final DateTime? expiresOn;
  final int? expectedLifeYears;
  final int? replacementCost;
  final String details;
}

Future<_RegisterDraft?> _recordDialog(BuildContext context) async {
  final name = TextEditingController();
  final category = TextEditingController();
  final vendor = TextEditingController();
  final life = TextEditingController();
  final replacementCost = TextEditingController();
  final details = TextEditingController();
  var type = 'asset';
  DateTime? purchaseDate;
  DateTime? warrantyEnd;
  DateTime? amcEnd;
  DateTime? expiresOn;
  String? error;
  Future<DateTime?> pickDate(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(2010),
    lastDate: DateTime(2045),
  );
  final draft = await showDialog<_RegisterDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Submit register record'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Record type'),
                  items: [for (final option in _types) DropdownMenuItem(value: option.$1, child: Text(option.$2))],
                  onChanged: (value) => setState(() => type = value ?? type),
                ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
                const SizedBox(height: 12),
                TextField(
                  controller: category,
                  decoration: InputDecoration(labelText: type == 'other' ? 'Record kind * (e.g. Licence, Lease)' : 'Category / certificate type'),
                ),
                const SizedBox(height: 12),
                TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Vendor / insurer (optional)')),
                if (type == 'asset') ...[
                  TextField(
                    controller: life,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Expected life in years'),
                  ),
                  TextField(
                    controller: replacementCost,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Replacement cost'),
                  ),
                  _dateButton(context, 'Purchase date', purchaseDate, (d) => setState(() => purchaseDate = d), pickDate),
                  _dateButton(context, 'Warranty end', warrantyEnd, (d) => setState(() => warrantyEnd = d), pickDate),
                  _dateButton(context, 'AMC end', amcEnd, (d) => setState(() => amcEnd = d), pickDate),
                ],
                if (type == 'insurance' || type == 'compliance' || type == 'other')
                  _dateButton(
                    context,
                    type == 'other' ? 'Expiry date (optional)' : 'Expiry date *',
                    expiresOn,
                    (d) => setState(() => expiresOn = d),
                    pickDate,
                  ),
                const SizedBox(height: 8),
                TextField(controller: details, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes / conflict details')),
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
              if (type == 'other' && category.text.trim().isEmpty) return setState(() => error = 'Enter the record kind');
              if ((type == 'insurance' || type == 'compliance') && expiresOn == null) {
                return setState(() => error = 'Expiry date is required');
              }
              Navigator.pop(
                dialogContext,
                _RegisterDraft(
                  type: type,
                  name: name.text.trim(),
                  category: category.text.trim(),
                  vendor: vendor.text.trim(),
                  purchaseDate: purchaseDate,
                  warrantyEnd: warrantyEnd,
                  amcEnd: amcEnd,
                  expiresOn: expiresOn,
                  expectedLifeYears: int.tryParse(life.text),
                  replacementCost: int.tryParse(replacementCost.text),
                  details: details.text.trim(),
                ),
              );
            },
            child: const Text('Send for approval'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  category.dispose();
  vendor.dispose();
  life.dispose();
  replacementCost.dispose();
  details.dispose();
  return draft;
}

Widget _dateButton(
  BuildContext context,
  String label,
  DateTime? current,
  void Function(DateTime?) set,
  Future<DateTime?> Function(DateTime?) pick,
) => Align(
  alignment: Alignment.centerLeft,
  child: TextButton.icon(
    onPressed: () async => set(await pick(current)),
    icon: const Icon(Icons.event_outlined),
    label: Text(current == null ? label : '$label · ${dateFmt.format(current)}'),
  ),
);
