import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../backend/backend.dart';
import '../../widgets/common.dart';

const _archiveTypes = [
  ('membership', 'Membership'),
  ('invite', 'Invite'),
  ('profile', 'Profile'),
  ('flat', 'Flat'),
  ('staff', 'Association staff'),
  ('staff_private_details', 'Staff employment details'),
  ('household_housekeeping', 'Household housekeeping'),
  ('vehicle', 'Vehicle'),
  ('staff_attendance', 'Staff attendance'),
  ('visitor_request', 'Visitor request'),
  ('id_document', 'ID document'),
];

class _ArchiveEntry {
  const _ArchiveEntry({
    required this.id,
    required this.type,
    required this.action,
    required this.archivedAt,
    required this.snapshot,
    this.person,
    this.flat,
  });

  final String id;
  final String type;
  final String action;
  final DateTime archivedAt;
  final Map<String, dynamic> snapshot;
  final String? person;
  final String? flat;
}

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _flat = TextEditingController();
  final _person = TextEditingController();
  int? _year;
  String? _type;
  bool _loading = false;
  String? _error;
  List<_ArchiveEntry> _entries = [];

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await db.rpc(
        'search_association_archive',
        params: {
          'p_year': _year,
          'p_flat': _flat.text.trim().isEmpty ? null : _flat.text.trim(),
          'p_person': _person.text.trim().isEmpty ? null : _person.text.trim(),
          'p_entity': _type,
          'p_limit': 250,
        },
      ) as List;
      final entries = [
        for (final raw in rows.cast<Map<String, dynamic>>())
          _ArchiveEntry(
            id: raw['id'] as String,
            type: raw['entity_type'] as String,
            action: raw['change_action'] as String,
            archivedAt: DateTime.parse(raw['archived_at'] as String).toLocal(),
            snapshot: Map<String, dynamic>.from(raw['snapshot'] as Map? ?? const {}),
            person: raw['person_name'] as String?,
            flat: raw['flat_number'] as String?,
          ),
      ];
      if (mounted) setState(() => _entries = entries);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _flat.dispose();
    _person.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider)!.activeRole;
    if (role != Role.admin && role != Role.president && role != Role.secretary) {
      return const PageBody(children: [EmptyState('Only the President or Secretary can browse archives.', icon: Icons.lock_outline)]);
    }
    final currentYear = DateTime.now().year;
    return PageBody(
      maxWidth: 1100,
      children: [
        Text('Archive', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Archive retrieval may take several minutes for large searches.'),
            subtitle: Text('Narrow results by year, flat, person, or record type. Results are limited to 250 records per search.'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 145,
              child: DropdownButtonFormField<int?>(
                initialValue: _year,
                decoration: const InputDecoration(labelText: 'Archived year'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                  for (var year = currentYear; year >= currentYear - 20; year--)
                    DropdownMenuItem<int?>(value: year, child: Text('$year')),
                ],
                onChanged: (value) => setState(() => _year = value),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(controller: _flat, decoration: const InputDecoration(labelText: 'Flat number')),
            ),
            SizedBox(
              width: 220,
              child: TextField(controller: _person, decoration: const InputDecoration(labelText: 'Person / staff name')),
            ),
            SizedBox(
              width: 270,
              child: DropdownButtonFormField<String?>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Record type'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All record types', overflow: TextOverflow.ellipsis),
                  ),
                  for (final (value, label) in _archiveTypes)
                    DropdownMenuItem(value: value, child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _type = value),
              ),
            ),
            FilledButton.icon(
              onPressed: _loading ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('Search archive'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(_error!))),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _entries.isEmpty && _error == null)
          const EmptyState('No archived records match these filters.', icon: Icons.inventory_2_outlined),
        for (final entry in _entries)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text('${entry.person ?? _label(entry.type)}${entry.flat == null ? '' : ' · ${entry.flat}'}'),
              subtitle: Text('${entry.action} · ${_label(entry.type)} · ${dateTimeFmt.format(entry.archivedAt)}'),
              children: [
                for (final item in entry.snapshot.entries.where((e) => !_sensitiveKey(e.key)))
                  ListTile(
                    dense: true,
                    title: Text(item.key),
                    subtitle: Text(_format(item.value)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

bool _sensitiveKey(String key) => const {'storage_path', 'id_proof_path', 'email', 'mobile', 'token', 'password'}.contains(key.toLowerCase());

String _label(String type) => _archiveTypes.where((entry) => entry.$1 == type).firstOrNull?.$2 ?? type;

String _format(Object? value) {
  if (value == null) return '—';
  if (value is Map || value is List) return value.toString();
  return '$value';
}
