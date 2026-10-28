import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/gate_offline.dart';
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
  bool _offline = false;
  int _pending = 0;
  String? _onDuty;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _onDuty = p.getString(GateOffline.guardKey));
    });
    _load();
    if (backendEnabled) GateRepo.purgeOldPhotos().catchError((_) {});
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
      final (sent, failed) = await GateOffline.flush();
      if (mounted && sent > 0) toast(context, '$sent saved gate entr${sent == 1 ? 'y' : 'ies'} sent');
      for (final f in failed) {
        if (mounted) toast(context, 'Not accepted: $f');
      }
      final list = await GateRepo.today();
      await GateOffline.cache(list);
      final pending = (await GateOffline.queue()).length;
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
          _offline = false;
          _pending = pending;
        });
      }
    } catch (e) {
      if (isOffline(e)) {
        final cached = _list.isEmpty ? await GateOffline.cached() : _list;
        final pending = (await GateOffline.queue()).length;
        if (mounted) {
          setState(() {
            _offline = true;
            _list = cached;
            _pending = pending;
            _error = null;
          });
        }
      } else if (mounted) {
        setState(() => _error = friendlyError(e));
      }
    }
  }

  void _setLocal(String id, String status) => setState(
    () => _list = [
      for (final v in _list)
        v.id == id
            ? (
                id: v.id,
                guest: v.guest,
                phone: v.phone,
                flat: v.flat,
                status: status,
                approval: v.approval,
                type: v.type,
                vehicle: v.vehicle,
                passCode: v.passCode,
                arrival: v.arrival,
                photoPath: v.photoPath,
                guardName: v.guardName,
              )
            : v,
    ],
  );

  Future<void> _verify(GateVisitor v, bool checkIn) async {
    final word = checkIn ? 'in' : 'out';
    try {
      await VisitorRepo.verify(v.id, checkIn ? VisitorStatus.checkedIn : VisitorStatus.checkedOut);
      if (mounted) toast(context, '${v.guest} checked $word');
      await _load();
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      await GateOffline.add({
        'kind': 'verify',
        'id': v.id,
        'action': checkIn ? 'check_in' : 'check_out',
        'label': '${v.guest} → ${v.flat}',
      });
      if (!mounted) return;
      _setLocal(v.id, checkIn ? 'checked_in' : 'checked_out');
      setState(() => _pending++);
      toast(context, 'Offline: ${v.guest} checked $word. It will sync when the network is back.');
    }
  }

  Future<void> _callFlat(String flat) async {
    final f = flat.trim().toUpperCase();
    if (f.isEmpty) return;
    List<({String name, String role, String mobile})> people;
    try {
      people = await GateRepo.flatContacts(f);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    if (people.isEmpty) {
      toast(context, 'No phone number saved for flat $f.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Call flat $f', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final p in people)
              ListTile(
                leading: const Icon(Icons.call),
                title: Text(p.name),
                subtitle: Text('${p.role} · ${p.mobile}'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri(scheme: 'tel', path: p.mobile));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _startShift() async {
    List<({String id, String name})> guards;
    try {
      guards = await GateRepo.guards();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    if (guards.isEmpty) {
      toast(context, 'No guards added yet. The Secretary or Admin adds them under Guards.');
      return;
    }
    String? id = guards.first.id;
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: id,
              decoration: const InputDecoration(labelText: 'Guard'),
              items: [for (final g in guards) DropdownMenuItem(value: g.id, child: Text(g.name))],
              onChanged: (v) => id = v,
            ),
            TextField(
              controller: pin,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Guard PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    final gid = id;
    if (ok != true || gid == null) return;
    try {
      final result = await GateRepo.startShift(gid, pin.text);
      final name = result.name;
      if (name == null) {
        if (mounted) toast(context, result.error ?? 'Wrong guard or PIN');
        return;
      }
      await (await SharedPreferences.getInstance()).setString(GateOffline.guardKey, name);
      if (mounted) {
        setState(() => _onDuty = name);
        toast(context, 'Shift started: $name. Entries are recorded under this name.');
      }
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
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      final match = _list.where((v) => v.passCode == code.trim() && v.status == 'expected').firstOrNull;
      if (match == null) {
        if (mounted) toast(context, 'Offline and this code is not in the saved list. Call the flat or use Walk-in.');
        return;
      }
      await _verify(match, true);
    }
  }

  Future<void> _walkIn() async {
    final flat = TextEditingController(), name = TextEditingController(), phone = TextEditingController();
    final vehicle = TextEditingController();
    var type = 'guest';
    Uint8List? photo;
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                      maxWidth: 800,
                      imageQuality: 60,
                    );
                    if (f == null) return;
                    final b = await f.readAsBytes();
                    set(() => photo = b);
                  },
                  icon: Icon(photo == null ? Icons.photo_camera_outlined : Icons.check_circle_outline),
                  label: Text(photo == null ? 'Take visitor photo' : 'Photo added · retake'),
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
    final f = flat.text.trim(), n = name.text.trim(), pic = photo;
    try {
      final id = await GateRepo.walkIn(flat: f, name: n, phone: phone.text, type: type, vehicle: vehicle.text);
      if (pic != null) {
        try {
          await GateRepo.attachPhoto(id, pic);
        } catch (_) {
          if (mounted) toast(context, 'Visitor sent, but the photo could not be uploaded.');
        }
      }
      if (mounted) toast(context, 'Sent to flat ${f.toUpperCase()}. Wait for Approved before letting them in.');
      await _load();
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      await GateOffline.add({
        'kind': 'walkin',
        'flat': f,
        'name': n,
        'phone': phone.text,
        'type': type,
        'vehicle': vehicle.text,
        'photo': pic == null ? null : base64Encode(pic),
        'label': '$n → ${f.toUpperCase()}',
      });
      if (mounted) {
        setState(() => _pending++);
        toast(
          context,
          'Offline: saved. It goes to flat ${f.toUpperCase()} when the network is back. Call the flat meanwhile.',
        );
      }
    }
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
        Row(
          children: [
            Text('Gate', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            if (const {Role.admin, Role.president, Role.secretary}.contains(role))
              TextButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _GuardsDialog()),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Guards'),
              ),
            IconButton(
              tooltip: 'History (30 days)',
              icon: const Icon(Icons.history),
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _GateHistoryDialog()),
            ),
            IconButton(
              tooltip: 'Call a flat',
              icon: const Icon(Icons.call_outlined),
              onPressed: () async {
                final flat = await promptText(context, title: 'Call a flat', hint: 'Flat number, e.g. A-101');
                if (flat != null) await _callFlat(flat);
              },
            ),
            TextButton.icon(
              onPressed: _startShift,
              icon: const Icon(Icons.how_to_reg_outlined),
              label: Text(_onDuty == null ? 'Start shift' : 'On duty: $_onDuty'),
            ),
          ],
        ),
        if (_offline)
          Card(
            color: AppColors.amber.withValues(alpha: .15),
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Offline – entries are saved on this phone'),
              subtitle: Text('$_pending waiting to send. Pass codes are checked against the last saved list.'),
            ),
          )
        else if (_pending > 0)
          Text('$_pending saved entries waiting to send…'),
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
              leading: v.photoPath == null ? null : VisitorPhoto(path: v.photoPath!),
              title: Text('${v.guest} → ${v.flat}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  v.type,
                  if (v.vehicle != null) v.vehicle!,
                  if (v.phone != null) v.phone!,
                  dateTimeFmt.format(v.arrival),
                  if (v.guardName != null) 'by ${v.guardName}',
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Call flat ${v.flat}',
                    icon: const Icon(Icons.call_outlined),
                    onPressed: () => _callFlat(v.flat),
                  ),
                  switch ((v.approval, v.status)) {
                    ('awaiting', _) => const Pill('Waiting for flat', color: AppColors.amber),
                    ('denied', _) => const Pill('Denied', color: AppColors.red),
                    (_, 'checked_in') => OutlinedButton(
                      onPressed: () => _verify(v, false),
                      child: const Text('Check out'),
                    ),
                    _ => FilledButton(
                      onPressed: () => _verify(v, true),
                      child: Text(v.approval == 'approved' ? 'Approved · Let in' : 'Check in'),
                    ),
                  },
                ],
              ),
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
                leading: v.photoPath == null
                    ? const Icon(Icons.doorbell_outlined, color: AppColors.amber)
                    : VisitorPhoto(path: v.photoPath!),
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

class _GuardsDialog extends StatefulWidget {
  const _GuardsDialog();

  @override
  State<_GuardsDialog> createState() => _GuardsDialogState();
}

class _GuardsDialogState extends State<_GuardsDialog> {
  List<({String id, String name})> _guards = const [];
  final _name = TextEditingController(), _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await GateRepo.guards();
      if (mounted) setState(() => _guards = g);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gate guards'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Guards share the gate phone. Each starts a shift with their name and 4-digit PIN.'),
            for (final g in _guards)
              ListTile(
                dense: true,
                leading: const Icon(Icons.badge_outlined),
                title: Text(g.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reset PIN',
                      icon: const Icon(Icons.pin_outlined),
                      onPressed: () async {
                        final pin = await promptText(context, title: 'New PIN for ${g.name}', hint: '4 digits');
                        if (pin != null) await _run(() => GateRepo.saveGuard(g.name, pin.trim(), id: g.id));
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _run(() => GateRepo.removeGuard(g.id)),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Guard name'),
            ),
            TextField(
              controller: _pin,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '4-digit PIN'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(
        onPressed: () => _run(() async {
          await GateRepo.saveGuard(_name.text, _pin.text);
          _name.clear();
          _pin.clear();
        }),
        child: const Text('Add guard'),
      ),
    ],
  );
}

/// Visitor photo thumbnail from the private bucket; tap to enlarge.
class VisitorPhoto extends StatefulWidget {
  const VisitorPhoto({super.key, required this.path});
  final String path;

  @override
  State<VisitorPhoto> createState() => _VisitorPhotoState();
}

class _VisitorPhotoState extends State<VisitorPhoto> {
  late final Future<String> _url = GateRepo.photoUrl(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, s) {
      final url = s.data;
      if (url == null) return const CircleAvatar(radius: 24, child: Icon(Icons.person_outline));
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(child: Image.network(url)),
        ),
        child: CircleAvatar(radius: 24, backgroundImage: NetworkImage(url)),
      );
    },
  );
}

class _GateHistoryDialog extends StatelessWidget {
  const _GateHistoryDialog();

  static String _when(DateTime d) {
    final t = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  static String _status(GateVisitor v) => switch ((v.approval, v.status)) {
    ('denied', _) => 'Denied',
    ('awaiting', _) => 'Waiting for flat',
    (_, 'checked_in') => 'Inside',
    (_, 'checked_out') => 'Left',
    (_, 'expected') => 'Expected',
    (_, final s) => s.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gate history (30 days)'),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<List<GateVisitor>>(
        future: GateRepo.history(),
        builder: (context, snap) {
          if (snap.hasError) return Text(friendlyError(snap.error!));
          if (!snap.hasData) return const LinearProgressIndicator();
          final list = snap.data!;
          if (list.isEmpty) return const Text('No visitors in the last 30 days.');
          return ListView(
            shrinkWrap: true,
            children: [
              for (final v in list)
                ListTile(
                  dense: true,
                  title: Text('${v.guest} · flat ${v.flat}'),
                  subtitle: Text(
                    '${_when(v.arrival)} · ${v.type}'
                    '${v.vehicle == null ? '' : ' · ${v.vehicle}'}'
                    '${v.guardName == null ? '' : ' · by ${v.guardName}'}',
                  ),
                  trailing: Text(_status(v)),
                ),
            ],
          );
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}
