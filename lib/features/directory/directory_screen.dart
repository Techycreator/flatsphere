import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/directory_state.dart';
import '../../widgets/common.dart';
import '../../validation/input_validation.dart';

enum _Tab { flats, people, monitors }

const _assignerRoles = {Role.admin, Role.president, Role.secretary, Role.jointSecretary};

String _occLabel(Occupancy o) => switch (o) {
  Occupancy.ownerOccupied => 'Owner-occupied',
  Occupancy.rented => 'Rented',
  Occupancy.vacant => 'Vacant',
};

Color _occColor(Occupancy o) => switch (o) {
  Occupancy.ownerOccupied => AppColors.green,
  Occupancy.rented => AppColors.seed,
  Occupancy.vacant => AppColors.amber,
};

bool _isCurrentMonitor(Person p, DateTime today) =>
    !p.invited &&
    (p.monitorFrom == null || !p.monitorFrom!.isAfter(today)) &&
    (p.monitorUntil == null || !p.monitorUntil!.isBefore(today));

(String, Color) _monitorStatus(Person p, DateTime today) {
  final from = p.monitorFrom, until = p.monitorUntil;
  if (p.invited) return ('Invite pending', Colors.blueGrey);
  if (from != null && from.isAfter(today)) return ('Starts ${dateFmt.format(from)}', Colors.blueGrey);
  if (until == null) return ('No end date', AppColors.amber);
  if (until.isBefore(today)) return ('Ended', AppColors.red);
  final days = until.difference(today).inDays;
  if (days <= 30) return ('Ends in $days days', AppColors.amber);
  return ('Active', AppColors.green);
}

String _period(Person p) {
  final from = p.monitorFrom, until = p.monitorUntil;
  final range =
      '${from == null ? 'No start date' : dateFmt.format(from)} – ${until == null ? 'no end date' : dateFmt.format(until)}';
  if (from == null || until == null) return range;
  final days = until.difference(from).inDays + 1;
  return '$range (${days >= 60 ? '${(days / 30.44).round()} months' : '$days days'})';
}

/// Flats, people (owners, residents, committee), monitor assignments and ID proofs.
/// The server re-checks every change; these checks only decide what to show.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  _Tab tab = _Tab.flats;
  String query = '';
  String filter = 'All';

  static const _filters = ['All', 'Committee', 'Owners', 'Residents', 'Invited'];

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      _toast(done);
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionProvider)!;
    final canAssign = _assignerRoles.contains(s.activeRole);
    final canManage = canAssign || (s.activeRole.isCommittee && s.user.designations.contains(DemoUser.membershipDesk));
    final st = ref.watch(directoryProvider);
    final theme = Theme.of(context);
    if (!canManage) {
      return const PageBody(
        children: [
          EmptyState(
            'Only the President, Secretary, Joint Secretary or the Membership desk can manage flats and people.',
            icon: Icons.lock_outline,
          ),
        ],
      );
    }
    return PageBody(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l.directory, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(directoryProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_Tab>(
            segments: const [
              ButtonSegment(value: _Tab.flats, label: Text('Flats'), icon: Icon(Icons.apartment_outlined)),
              ButtonSegment(value: _Tab.people, label: Text('People'), icon: Icon(Icons.people_outline)),
              ButtonSegment(value: _Tab.monitors, label: Text('Monitors'), icon: Icon(Icons.visibility_outlined)),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
        const SizedBox(height: 16),
        if (st.error != null)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.error_outline), title: Text(st.error!)),
          ),
        if (st.loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ...switch (tab) {
            _Tab.flats => _flats(st),
            _Tab.people => _people(context, st, canAssign),
            _Tab.monitors => _monitors(st, canAssign),
          },
      ],
    );
  }

  // ---------------------------------------------------------------- Flats

  String? _names(String label, List<Person> list) =>
      list.isEmpty ? null : '$label: ${list.map((p) => p.invited ? '${p.name} (invited)' : p.name).join(', ')}';

  List<Widget> _flats(DirectoryState st) => [
    Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: () => _editFlat(null),
        icon: const Icon(Icons.add),
        label: const Text('Add flat'),
      ),
    ),
    const SizedBox(height: 8),
    if (st.flats.isEmpty)
      const EmptyState('No flats yet. Add your first flat.', icon: Icons.apartment_outlined)
    else
      SectionCard(
        title: '${st.flats.length} flats',
        padding: false,
        child: Column(
          children: [
            for (final f in st.flats)
              ListTile(
                leading: CircleAvatar(child: Text(f.block.isEmpty ? '#' : f.block.substring(0, 1))),
                title: Text(f.number),
                subtitle: Text(
                  [
                    [
                      if (f.block.isNotEmpty) 'Block ${f.block}',
                      f.type,
                      if (f.sqft != null) '${f.sqft} sq ft',
                    ].join(' · '),
                    _names('Owner', st.at(f.number, Role.owner)) ?? 'Owner: not added',
                    _names('Resident', st.at(f.number, Role.resident)),
                    if (f.carNumber != null) 'Car: ${f.carNumber}${f.parkingSlot == null ? '' : ' · slot ${f.parkingSlot}'}',
                    if (f.bikeNumber != null) 'Bike: ${f.bikeNumber}${f.parkingSlot == null ? '' : ' · slot ${f.parkingSlot}'}',
                  ].whereType<String>().join('\n'),
                ),
                isThreeLine: true,
                trailing: Pill(_occLabel(f.occupancy), color: _occColor(f.occupancy)),
                onTap: () => _editFlat(f),
              ),
          ],
        ),
      ),
  ];

  Future<void> _editFlat(FlatInfo? f) async {
    final number = TextEditingController(text: f?.number);
    final block = TextEditingController(text: f?.block);
    final type = TextEditingController(text: f?.type ?? '2BHK');
    final sqft = TextEditingController(text: f?.sqft?.toString());
    final carNumber = TextEditingController(text: f?.carNumber);
    final bikeNumber = TextEditingController(text: f?.bikeNumber);
    final parkingSlot = TextEditingController(text: f?.parkingSlot);
    var occ = f?.occupancy ?? Occupancy.ownerOccupied;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(f == null ? 'Add flat' : 'Edit ${f.number}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: number,
                    decoration: const InputDecoration(labelText: 'Flat number *', hintText: 'e.g. A-101'),
                  ),
                  TextField(
                    controller: block,
                    decoration: const InputDecoration(labelText: 'Block / tower'),
                  ),
                  TextField(
                    controller: type,
                    decoration: const InputDecoration(labelText: 'Type', hintText: '1BHK, 2BHK, 3BHK…'),
                  ),
                  TextField(
                    controller: sqft,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Area (sq ft)'),
                  ),
                  TextField(
                    controller: carNumber,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Car registration number (optional)'),
                  ),
                  TextField(
                    controller: bikeNumber,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Bike registration number (optional)'),
                  ),
                  TextField(
                    controller: parkingSlot,
                    decoration: const InputDecoration(labelText: 'Parking slot (optional)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Occupancy>(
                    initialValue: occ,
                    decoration: const InputDecoration(labelText: 'Occupancy'),
                    items: [for (final o in Occupancy.values) DropdownMenuItem(value: o, child: Text(_occLabel(o)))],
                    onChanged: (v) => set(() => occ = v ?? occ),
                  ),
                  if (err != null) _ErrorText(err!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (number.text.trim().isEmpty) return set(() => err = 'Flat number is required');
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref
          .read(directoryProvider.notifier)
          .saveFlat(
            FlatInfo(
              id: f?.id,
              number: number.text.trim(),
              block: block.text.trim(),
              type: type.text.trim().isEmpty ? '2BHK' : type.text.trim(),
              sqft: int.tryParse(sqft.text),
              occupancy: occ,
              carNumber: carNumber.text.trim().isEmpty ? null : carNumber.text.trim().toUpperCase(),
              bikeNumber: bikeNumber.text.trim().isEmpty ? null : bikeNumber.text.trim().toUpperCase(),
              parkingSlot: parkingSlot.text.trim().isEmpty ? null : parkingSlot.text.trim(),
            ),
          ),
      'Flat ${number.text.trim()} saved',
    );
  }

  // ---------------------------------------------------------------- People

  List<Widget> _people(BuildContext context, DirectoryState st, bool canAssign) {
    final l = AppLocalizations.of(context);
    final q = query.trim().toLowerCase();
    final list = st.people.where((p) {
      final inFilter = switch (filter) {
        'Committee' => p.role.isCommittee || p.role == Role.caretaker || p.role == Role.auditor,
        'Owners' => p.role == Role.owner,
        'Residents' => p.role == Role.resident,
        'Invited' => p.invited,
        _ => true,
      };
      return inFilter &&
          (q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.email.toLowerCase().contains(q) ||
              (p.flatNumber ?? '').toLowerCase().contains(q));
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, email or flat',
                isDense: true,
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          for (final f in _filters)
            ChoiceChip(label: Text(f), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
          FilledButton.icon(
            onPressed: () => _addPerson(st, canAssign),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add person'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const EmptyState('No one matches.', icon: Icons.people_outline)
      else
        SectionCard(
          title: '${list.length} entries · a person with two roles appears twice',
          padding: false,
          child: Column(
            children: [
              for (final p in list)
                ListTile(
                  leading: CircleAvatar(child: Text(p.name.isEmpty ? '?' : p.name[0])),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.role.label}${p.flatNumber != null ? ' · ${p.flatNumber}' : ''}'
                    '${p.monitorCategories.isNotEmpty ? ' · ${p.monitorCategories.join(', ')}' : ''}'
                    '${p.designations.isNotEmpty ? ' · ${p.designations.join(', ')}' : ''}'
                    '${p.supportFlags.isNotEmpty ? ' · ${p.supportFlags.map((flag) => flag.label).join(', ')}' : ''}\n${p.email}'
                    '${p.mobile == null ? '' : ' · ${p.mobile}'}'
                    '${p.role == Role.owner || p.role == Role.resident ? ' · ${_localizedAgeCategory(p.ageCategory, l)}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: p.invited ? const Pill('Invited', color: AppColors.amber) : null,
                  onTap: () => _openPerson(p, canAssign),
                ),
            ],
          ),
        ),
    ];
  }

  Future<void> _addPerson(DirectoryState st, bool canAssign) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final mobile = TextEditingController();
    DateTime? birthDate;
    final roles = canAssign ? Role.values : const [Role.owner, Role.resident];
    var role = Role.owner;
    String? flat = st.flats.firstOrNull?.number;
    var areas = <String>[];
    DateTime? from = DateUtils.dateOnly(DateTime.now());
    DateTime? until;
    var desk = false;
    var supportFlags = <MemberSupportFlag>{};
    String? err;
    bool needsFlat() => role == Role.owner || role == Role.resident;
    String? validate() {
      if (name.text.trim().isEmpty) return 'Name is required';
      if (!InputValidation.isEmail(email.text)) return 'Enter a valid email';
      if (needsFlat() && !InputValidation.isPhone(mobile.text)) {
        return 'Enter a valid phone number for the owner or resident';
      }
      if (needsFlat() && flat == null) return 'Choose a flat';
      if (role == Role.monitor && areas.isEmpty) return 'Choose at least one monitor area';
      if (role == Role.monitor && until == null) return 'Choose an end date for the monitor assignment';
      if (from != null && until != null && until!.isBefore(from!)) return 'End date must be after the start date';
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add person'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Full name *'),
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email * (login codes are sent here)'),
                  ),
                  TextField(
                    controller: mobile,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+() -]'))],
                    decoration: InputDecoration(labelText: needsFlat() ? 'Mobile *' : 'Mobile'),
                  ),
                  if (needsFlat())
                    TextButton.icon(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: ctx,
                          initialDate: birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 30)),
                          firstDate: DateTime(1900),
                          lastDate: DateUtils.dateOnly(DateTime.now()),
                        );
                        if (selected != null) set(() => birthDate = selected);
                      },
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(birthDate == null ? 'Date of birth (optional)' : 'Date of birth · ${dateFmt.format(birthDate!)}'),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Role>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      for (final r in roles)
                        DropdownMenuItem(
                          value: r,
                          child: Text(r == Role.resident ? 'Resident (tenant / family)' : r.label),
                        ),
                    ],
                    onChanged: (v) => set(() {
                      role = v ?? role;
                      if (role != Role.owner && role != Role.resident) supportFlags.clear();
                    }),
                  ),
                  if (needsFlat())
                    DropdownButtonFormField<String>(
                      initialValue: flat,
                      decoration: const InputDecoration(labelText: 'Flat *'),
                      items: [for (final f in st.flats) DropdownMenuItem(value: f.number, child: Text(f.number))],
                      onChanged: (v) => set(() => flat = v),
                    ),
                  if (role == Role.owner || role == Role.resident) ...[
                    const SizedBox(height: 8),
                    const Align(alignment: Alignment.centerLeft, child: Text('Member support details (optional)')),
                    for (final flag in MemberSupportFlag.values)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: supportFlags.contains(flag),
                        onChanged: (value) => set(() {
                          if (value == true) {
                            supportFlags.add(flag);
                          } else {
                            supportFlags.remove(flag);
                          }
                        }),
                        title: Text(flag.label),
                      ),
                  ],
                  if (role == Role.ecMember || role == Role.monitor)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: desk,
                      onChanged: (v) => set(() => desk = v ?? false),
                      title: const Text(DemoUser.membershipDesk),
                      subtitle: const Text('Can add owners and residents and start membership changes'),
                    ),
                  if (role == Role.monitor)
                    _AreaPicker(
                      areas: areas,
                      from: from,
                      until: until,
                      onChanged: (a, f, u) => set(() {
                        areas = a;
                        from = f;
                        until = u;
                      }),
                    ),
                  if (!canAssign)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Committee and staff roles can only be assigned by the President or Secretary.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (err != null) _ErrorText(err!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final e = validate();
                if (e != null) return set(() => err = e);
                Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final isMonitor = role == Role.monitor;
    final p = Person(
      id: '',
      name: name.text.trim(),
      email: email.text.trim(),
      mobile: mobile.text.trim(),
      role: role,
      flatNumber: needsFlat() ? flat : null,
      birthDate: needsFlat() ? birthDate : null,
      designations: desk ? const [DemoUser.membershipDesk] : const [],
      monitorCategories: isMonitor ? areas : const [],
      monitorFrom: isMonitor ? from : null,
      monitorUntil: isMonitor ? until : null,
      supportFlags: supportFlags.toList(),
    );
    try {
      final r = await ref.read(directoryProvider.notifier).addPerson(p);
      _toast(
        r == 'invited'
            ? 'Invited ${p.name}. They can now log in with a code sent to ${p.email}.'
            : '${p.role.label} role added to ${p.name}\'s existing account.',
      );
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  Future<void> _openPerson(Person p, bool canAssign) => showDialog<void>(
    context: context,
    builder: (ctx) => _PersonDialog(
      person: p,
      canAssign: canAssign,
      onEdit: () {
        Navigator.pop(ctx);
        _editDetails(p);
      },
      onRemove: () {
        Navigator.pop(ctx);
        _remove(p);
      },
    ),
  );

  Future<void> _editDetails(Person p) async {
    var areas = [...p.monitorCategories];
    var birthDate = p.birthDate;
    var from = p.monitorFrom ?? (p.role == Role.monitor ? DateUtils.dateOnly(DateTime.now()) : null);
    var until = p.monitorUntil;
    var desk = p.designations.contains(DemoUser.membershipDesk);
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${p.name} · ${p.role.label}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: desk,
                    onChanged: (v) => set(() => desk = v ?? false),
                    title: const Text(DemoUser.membershipDesk),
                    subtitle: const Text('Can add owners and residents and start membership changes'),
                  ),
                  if (p.role == Role.owner || p.role == Role.resident)
                    TextButton.icon(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: ctx,
                          initialDate: birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 30)),
                          firstDate: DateTime(1900),
                          lastDate: DateUtils.dateOnly(DateTime.now()),
                        );
                        if (selected != null) set(() => birthDate = selected);
                      },
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(birthDate == null ? 'Set date of birth (optional)' : 'DOB · ${dateFmt.format(birthDate!)} · ${_ageLabel(birthDate!, AppLocalizations.of(context))}'),
                    ),
                  if (p.role == Role.monitor)
                    _AreaPicker(
                      areas: areas,
                      from: from,
                      until: until,
                      onChanged: (a, f, u) => set(() {
                        areas = a;
                        from = f;
                        until = u;
                      }),
                    ),
                  if (err != null) _ErrorText(err!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (p.role == Role.monitor && areas.isNotEmpty && until == null) {
                  return set(() => err = 'Choose an end date for the monitor assignment');
                }
                if (from != null && until != null && until!.isBefore(from!)) {
                  return set(() => err = 'End date must be after the start date');
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final designations = [
      ...p.designations.where((d) => d != DemoUser.membershipDesk),
      if (desk) DemoUser.membershipDesk,
    ];
    final isMonitor = p.role == Role.monitor;
    await _run(
      () async {
        final notifier = ref.read(directoryProvider.notifier);
        await notifier.setDetails(
            p,
            designations,
            isMonitor ? areas : const [],
            from: isMonitor ? from : null,
            until: isMonitor ? until : null,
          );
        if (birthDate != null && birthDate != p.birthDate) await notifier.setBirthDate(p, birthDate!);
      },
      'Saved changes for ${p.name}',
    );
  }

  Future<void> _remove(Person p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: Text(
          p.invited
              ? 'The invitation as ${p.role.label} will be cancelled.'
              : 'Their ${p.role.label} access${p.flatNumber != null ? ' for ${p.flatNumber}' : ''} ends now. '
                    'Their ID proofs for this flat move to the archive. Other roles they hold are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(directoryProvider.notifier).removePerson(p), '${p.name} removed as ${p.role.label}');
  }

  // ---------------------------------------------------------------- Monitors

  List<Widget> _monitors(DirectoryState st, bool canAssign) {
    final today = DateUtils.dateOnly(DateTime.now());
    final mons = st.people.where((p) => p.role == Role.monitor).toList()
      ..sort((a, b) => (a.monitorUntil ?? DateTime(9999)).compareTo(b.monitorUntil ?? DateTime(9999)));
    final current = mons.where((p) => _isCurrentMonitor(p, today)).toList();
    final covered = {for (final p in current) ...p.monitorCategories};
    final areas = {...monitorAreas, ...covered}.toList();
    final uncovered = areas.where((a) => !covered.contains(a)).toList();
    final ending = current.where((p) => p.monitorUntil != null && p.monitorUntil!.difference(today).inDays <= 30);
    String who(String area) {
      final names = current.where((p) => p.monitorCategories.contains(area)).map((p) => p.name.split(' ').first);
      return names.isEmpty ? '' : ' · ${names.join(', ')}';
    }

    return [
      StatGrid(
        children: [
          StatCard(
            label: 'Active monitors',
            value: '${current.length}',
            icon: Icons.badge_outlined,
            sub: '${mons.length - current.length} invited, ended or not started',
          ),
          StatCard(
            label: 'Areas covered',
            value: '${covered.length} of ${areas.length}',
            icon: Icons.task_alt,
            color: AppColors.green,
          ),
          StatCard(
            label: 'Areas without a monitor',
            value: '${uncovered.length}',
            icon: Icons.report_gmailerrorred,
            color: uncovered.isEmpty ? AppColors.green : AppColors.red,
          ),
          StatCard(
            label: 'Ending within 30 days',
            value: '${ending.length}',
            icon: Icons.event_busy_outlined,
            color: ending.isEmpty ? AppColors.green : AppColors.amber,
            sub: ending.isEmpty ? null : ending.map((p) => p.name.split(' ').first).join(', '),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Coverage by area (as of ${dateFmt.format(today)})',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in areas)
              Pill(
                '$a${who(a)}',
                color: covered.contains(a) ? AppColors.green : AppColors.red,
                icon: covered.contains(a) ? Icons.check : Icons.close,
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Monitor assignments',
        padding: false,
        child: mons.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No monitors yet. Add a person with the Monitor role from People.'),
              )
            : Column(
                children: [
                  for (final p in mons)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        'Areas: ${p.monitorCategories.isEmpty ? 'none' : p.monitorCategories.join(', ')}\n'
                        '${_period(p)}\nAssigned by ${p.assignedBy ?? '—'}',
                      ),
                      isThreeLine: true,
                      trailing: Builder(
                        builder: (_) {
                          final (label, color) = _monitorStatus(p, today);
                          return Pill(label, color: color);
                        },
                      ),
                      onTap: canAssign ? () => _editDetails(p) : () => _openPerson(p, canAssign),
                    ),
                ],
              ),
      ),
      if (canAssign)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Tap a monitor to change their areas or dates.', style: TextStyle(fontSize: 12)),
        ),
    ];
  }
}

String _ageLabel(DateTime birthDate, AppLocalizations l) {
  var age = DateTime.now().year - birthDate.year;
  final today = DateTime.now();
  if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) age--;
  if (age < 18) return l.child;
  if (age >= 60) return l.seniorCitizen;
  return l.adult;
}

String _localizedAgeCategory(AgeCategory? category, AppLocalizations l) => switch (category) {
  AgeCategory.child => l.child,
  AgeCategory.adult => l.adult,
  AgeCategory.seniorCitizen => l.seniorCitizen,
  null => l.ageNotRecorded,
};

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error)),
  );
}

class _AreaPicker extends StatelessWidget {
  const _AreaPicker({required this.areas, required this.from, required this.until, required this.onChanged});

  final List<String> areas;
  final DateTime? from;
  final DateTime? until;
  final void Function(List<String> areas, DateTime? from, DateTime? until) onChanged;

  @override
  Widget build(BuildContext context) {
    Future<DateTime?> pick(DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Monitor areas', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in {...monitorAreas, ...areas})
              FilterChip(
                label: Text(a),
                selected: areas.contains(a),
                onSelected: (v) => onChanged(v ? [...areas, a] : areas.where((x) => x != a).toList(), from, until),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Assignment period', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('From: ${from == null ? 'choose' : dateFmt.format(from!)}'),
              onPressed: () async {
                final d = await pick(from);
                if (d != null) onChanged(areas, d, until);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available),
              label: Text('Until: ${until == null ? 'choose' : dateFmt.format(until!)}'),
              onPressed: () async {
                final d = await pick(until ?? from?.add(const Duration(days: 90)));
                if (d != null) onChanged(areas, from, d);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Person details with private ID proofs (upload, view via a 60-second link; every view is logged).
class _PersonDialog extends ConsumerStatefulWidget {
  const _PersonDialog({required this.person, required this.canAssign, required this.onEdit, required this.onRemove});

  final Person person;
  final bool canAssign;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  ConsumerState<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends ConsumerState<_PersonDialog> {
  late Future<List<IdDocument>> docs = _load();
  bool busy = false;

  Person get p => widget.person;

  Future<List<IdDocument>> _load() => ref.read(directoryProvider.notifier).docs(p);

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  Future<void> _upload() async {
    var type = idDocTypes.first;
    final last4 = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Add ID proof · ${p.name}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Document type'),
                  items: [for (final t in idDocTypes) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => set(() => type = v ?? type),
                ),
                TextField(
                  controller: last4,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]'))],
                  decoration: const InputDecoration(labelText: 'Last 4 digits / characters of the ID number'),
                ),
                const Text(
                  'Upload only masked Aadhaar (first 8 digits hidden). JPG, PNG, WEBP or PDF, up to 5 MB. '
                  'Stored privately; only the President, Secretary, Membership desk, the flat owner and the person '
                  'can open it, and every view is logged.',
                  style: TextStyle(fontSize: 12),
                ),
                if (err != null) _ErrorText(err!),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              onPressed: () {
                if (type.startsWith('Aadhaar') && last4.text.trim().length != 4) {
                  return set(() => err = 'Enter the last 4 digits of the Aadhaar number');
                }
                Navigator.pop(ctx, true);
              },
              label: const Text('Choose file'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (files.isEmpty) return;
    final f = files.first;
    setState(() => busy = true);
    try {
      final size = await f.length();
      if (size == null || size > maxSourceUploadBytes(f.extension ?? '')) {
        return _toast('File exceeds the supported source size');
      }
      final bytes = await f.readAsBytes();
      await ref.read(directoryProvider.notifier).uploadDoc(p, type, last4.text.trim(), bytes, f.extension ?? 'jpg');
      setState(() => docs = _load());
      _toast('ID proof uploaded');
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _view(IdDocument d) async {
    try {
      final url = await ref.read(directoryProvider.notifier).viewUrl(d);
      if (url == null) return _toast('Demo mode: files are not stored');
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRemove = widget.canAssign || p.role == Role.owner || p.role == Role.resident;
    final editable = widget.canAssign && (p.role == Role.monitor || p.role == Role.ecMember);
    Widget row(String k, String? v) => v == null || v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110, child: Text(k, style: theme.textTheme.bodySmall)),
                Expanded(child: Text(v)),
              ],
            ),
          );
    return AlertDialog(
      title: Text(p.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Role', p.role.label + (p.invited ? ' (invite pending)' : '')),
              row('Flat', p.flatNumber),
              row('Email', p.email),
              row('Mobile', p.mobile),
              row('Designations', p.designations.join(', ')),
              if (p.role == Role.monitor) ...[
                row('Monitor areas', p.monitorCategories.join(', ')),
                row('Period', _period(p)),
                row('Assigned by', p.assignedBy),
              ],
              row(p.invited ? 'Invited on' : 'Since', p.since == null ? null : dateFmt.format(p.since!)),
              const Divider(height: 24),
              Text('ID proofs', style: theme.textTheme.titleSmall),
              FutureBuilder<List<IdDocument>>(
                future: docs,
                builder: (_, snap) {
                  if (snap.hasError) return _ErrorText(friendlyError(snap.error!));
                  if (!snap.hasData) return const LinearProgressIndicator();
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('None uploaded.'));
                  }
                  return Column(
                    children: [
                      for (final d in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            d.path?.endsWith('.pdf') == true ? Icons.picture_as_pdf_outlined : Icons.badge_outlined,
                          ),
                          title: Text(d.type),
                          subtitle: Text(
                            '${d.last4 == null ? '' : 'ending ${d.last4} · '}uploaded ${dateFmt.format(d.uploadedAt)}'
                            '${d.archived ? ' · archived' : ''}',
                          ),
                          trailing: IconButton(
                            tooltip: 'View (link valid 60 seconds)',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => _view(d),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (canRemove)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: widget.onRemove,
            child: const Text('Remove'),
          ),
        if (editable) TextButton(onPressed: widget.onEdit, child: const Text('Edit areas / designation')),
        OutlinedButton.icon(
          onPressed: busy ? null : _upload,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: const Text('Add ID proof'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
