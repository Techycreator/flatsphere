import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/gate_repo.dart';
import '../../backend/visitor_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Full-screen gate desk for Security: pass codes, walk-ins waiting for the flat's approval, check in/out.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key});

  @override
  ConsumerState<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<GateScreen> {
  List<GateVisitor> _list = const [];
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!backendEnabled) return;
    try {
      final list = await GateRepo.today();
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _guard(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) toast(context, done);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _pass() async {
    final code = await promptText(context, title: 'Visitor pass code', hint: '6-digit code from the resident');
    if (code == null) return;
    try {
      final who = await GateRepo.checkPass(code);
      if (mounted)
        toast(context, who == null ? 'Code not valid for today. Ask the resident or use Walk-in.' : 'Checked in: $who');
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _walkIn() async {
    final flat = TextEditingController(), name = TextEditingController(), phone = TextEditingController();
    final vehicle = TextEditingController();
    var type = 'guest';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Walk-in visitor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'guest', label: Text('Guest')),
                    ButtonSegment(value: 'delivery', label: Text('Delivery')),
                    ButtonSegment(value: 'cab', label: Text('Cab')),
                    ButtonSegment(value: 'service', label: Text('Service')),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => set(() => type = v.first),
                ),
                TextField(
                  controller: flat,
                  decoration: const InputDecoration(labelText: 'Flat number *'),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Visitor name / company *'),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                TextField(
                  controller: vehicle,
                  decoration: const InputDecoration(labelText: 'Vehicle number'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, flat.text.trim().isNotEmpty && name.text.trim().isNotEmpty),
              child: const Text('Ask flat to approve'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _guard(
      () => GateRepo.walkIn(flat: flat.text, name: name.text, phone: phone.text, type: type, vehicle: vehicle.text),
      'Sent to flat ${flat.text.trim().toUpperCase()}. Wait for Approved before letting them in.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider)?.activeRole;
    if (!backendEnabled) return const PageBody(children: [EmptyState('Gate mode works in the cloud version.')]);
    if (!const {Role.security, Role.caretaker, Role.admin, Role.president, Role.secretary}.contains(role)) {
      return const PageBody(children: [EmptyState('Gate mode is for security staff.')]);
    }
    Widget big(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: SizedBox(
        height: 96,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 32),
          label: Text(label, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
    final active = _list.where((v) => v.status == 'expected' || v.status == 'checked_in').toList();
    return PageBody(
      maxWidth: 900,
      children: [
        Text('Gate', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            big(Icons.pin_outlined, 'Pass code', _pass),
            const SizedBox(width: 12),
            big(Icons.person_add_alt_1_outlined, 'Walk-in', _walkIn),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!),
        if (active.isEmpty) const EmptyState('No visitors expected right now.'),
        for (final v in active)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${v.guest} → ${v.flat}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  v.type,
                  if (v.vehicle != null) v.vehicle!,
                  if (v.phone != null) v.phone!,
                  dateTimeFmt.format(v.arrival),
                ].join(' · '),
              ),
              trailing: switch ((v.approval, v.status)) {
                ('awaiting', _) => const Pill('Waiting for flat', color: AppColors.amber),
                ('denied', _) => const Pill('Denied', color: AppColors.red),
                (_, 'checked_in') => OutlinedButton(
                  onPressed: () =>
                      _guard(() => VisitorRepo.verify(v.id, VisitorStatus.checkedOut), '${v.guest} checked out'),
                  child: const Text('Check out'),
                ),
                _ => FilledButton(
                  onPressed: () =>
                      _guard(() => VisitorRepo.verify(v.id, VisitorStatus.checkedIn), '${v.guest} checked in'),
                  child: Text(v.approval == 'approved' ? 'Approved · Let in' : 'Check in'),
                ),
              },
            ),
          ),
      ],
    );
  }
}

/// Shown to residents: walk-ins waiting at the gate, plus pass codes to share with expected guests.
class GateAlertsCard extends StatefulWidget {
  const GateAlertsCard({super.key});

  @override
  State<GateAlertsCard> createState() => _GateAlertsCardState();
}

class _GateAlertsCardState extends State<GateAlertsCard> {
  List<GateVisitor> _list = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!backendEnabled) return;
    try {
      final list = await GateRepo.today();
      if (mounted) setState(() => _list = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _list.where((v) => v.approval == 'awaiting').toList();
    final codes = _list.where((v) => v.status == 'expected' && v.passCode != null).toList();
    if (waiting.isEmpty && codes.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final v in waiting)
              ListTile(
                leading: const Icon(Icons.doorbell_outlined, color: AppColors.amber),
                title: Text('${v.guest} is at the gate for ${v.flat}'),
                subtitle: Text([v.type, if (v.vehicle != null) v.vehicle!].join(' · ')),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await GateRepo.decide(v.id, false);
                        } catch (e) {
                          if (context.mounted) toast(context, friendlyError(e));
                        }
                        _load();
                      },
                      child: const Text('Deny'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await GateRepo.decide(v.id, true);
                        } catch (e) {
                          if (context.mounted) toast(context, friendlyError(e));
                        }
                        _load();
                      },
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ),
            if (codes.isNotEmpty) ...[
              const Text('Gate pass codes – share with your guest', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final v in codes)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text('${v.guest} · ${dateTimeFmt.format(v.arrival)}'),
                  trailing: SelectableText(
                    v.passCode!,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 2),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
