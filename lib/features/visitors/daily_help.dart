import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/daily_help_repo.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/gate_offline.dart';
import '../../backend/visitor_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _residents = {Role.owner, Role.resident};
const _committee = {Role.caretaker, Role.admin, Role.president, Role.secretary};

String _kind(String k) => k[0].toUpperCase() + k.substring(1);

String _schedule(DailyHelp h) {
  final days = h.days.length == 7 ? 'Every day' : [for (final d in h.days) _dayNames[d - 1]].join(' ');
  final time = h.start == null && h.end == null ? 'any time' : '${h.start ?? '00:00'}–${h.end ?? '23:59'}';
  return '$days, $time';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _dm(DateTime d) => '${_two(d.day)}/${_two(d.month)}';
String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
        ],
      ),
    ) ??
    false;

/// Visitors page: residents manage their flat's daily help; committee/caretaker see all and add common services.
class DailyHelpSection extends ConsumerStatefulWidget {
  const DailyHelpSection({super.key});

  @override
  ConsumerState<DailyHelpSection> createState() => _DailyHelpSectionState();
}

class _DailyHelpSectionState extends ConsumerState<DailyHelpSection> {
  List<DailyHelp>? _list;
  List<(String id, String number)> _flats = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!backendEnabled) return;
    final role = ref.read(sessionProvider)?.activeRole;
    try {
      final list = await DailyHelpRepo.load();
      final flats = _residents.contains(role) ? await VisitorRepo.myFlats() : const <(String, String)>[];
      if (mounted) {
        setState(() {
          _list = list;
          _flats = flats;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _edit([DailyHelp? h]) async {
    final role = ref.read(sessionProvider)!.activeRole;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _HelpDialog(existing: h, flats: _residents.contains(role) ? _flats : const []),
    );
    if (saved == true) await _load();
  }

  Future<void> _remove(DailyHelp h) async {
    final role = ref.read(sessionProvider)!.activeRole;
    final myFlat = _flats.map((f) => f.$1).where(h.flatIds.contains).firstOrNull;
    final block = !_residents.contains(role);
    if (block && !_committee.contains(role)) return;
    if (!block && myFlat == null) return;
    final ok = await _confirm(
      context,
      block ? 'Block ${h.name}?' : 'Remove ${h.name}?',
      block
          ? 'The pass stops working at the gate for every flat in this association.'
          : 'The pass is removed from your flat. Other flats they work for are not affected.',
    );
    if (!ok) return;
    try {
      await DailyHelpRepo.remove(h.id, flatId: block ? null : myFlat);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!backendEnabled) return const SizedBox.shrink();
    final role = ref.watch(sessionProvider)?.activeRole;
    if (!_residents.contains(role) && !_committee.contains(role)) return const SizedBox.shrink();
    final canAdd = _committee.contains(role) || _flats.isNotEmpty;
    final list = _list;
    return SectionCard(
      title: 'Daily help',
      action: canAdd
          ? TextButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(_committee.contains(role) ? 'Add common service' : 'Add daily help'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) Text(_error!),
          if (list == null && _error == null) const LinearProgressIndicator(),
          if (list != null && list.isEmpty)
            const Text('Maid, cook, driver, newspaper or milk: register them once and they get a permanent gate code.'),
          for (final h in list ?? const <DailyHelp>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(h.inside ? Icons.login : Icons.badge_outlined, color: h.inside ? AppColors.amber : null),
              title: Text('${h.name} · ${_kind(h.kind)}${h.inside ? ' · inside now' : ''}'),
              subtitle: Text('Code ${h.code} · ${h.flats} · ${_schedule(h)}${h.notify ? '' : ' · alerts off'}'),
              onTap: () => showDialog<void>(context: context, builder: (_) => _VisitsDialog(h)),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _edit(h) : _remove(h),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(_residents.contains(role) ? 'Remove from my flat' : 'Block for association'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HelpDialog extends StatefulWidget {
  const _HelpDialog({this.existing, required this.flats});
  final DailyHelp? existing;
  final List<(String id, String number)> flats;

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late String _kindValue = widget.existing?.kind ?? 'maid';
  late final Set<int> _days = {
    ...(widget.existing?.days ?? const [1, 2, 3, 4, 5, 6, 7]),
  };
  late String? _start = widget.existing?.start, _end = widget.existing?.end;
  late bool _notify = widget.existing?.notify ?? true;
  late String? _flat = widget.flats.firstOrNull?.$1;
  bool _busy = false;

  Future<void> _pickTime(bool start) async {
    final cur = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: cur == null
          ? TimeOfDay(hour: start ? 6 : 11, minute: 0)
          : TimeOfDay(hour: int.parse(cur.substring(0, 2)), minute: int.parse(cur.substring(3))),
    );
    if (t == null) return;
    setState(() => start ? _start = '${_two(t.hour)}:${_two(t.minute)}' : _end = '${_two(t.hour)}:${_two(t.minute)}');
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return toast(context, 'Enter the name');
    if (_days.isEmpty) return toast(context, 'Choose at least one day');
    if (_start != null && _end != null && _start!.compareTo(_end!) >= 0) {
      return toast(context, 'End time must be after start time');
    }
    setState(() => _busy = true);
    try {
      await DailyHelpRepo.save(
        id: widget.existing?.id,
        flatId: widget.existing == null ? _flat : null,
        name: _name.text.trim(),
        kind: _kindValue,
        phone: _phone.text.trim(),
        days: (_days.toList()..sort()),
        start: _start,
        end: _end,
        notify: _notify,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Add daily help' : 'Edit ${widget.existing!.name}'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _kindValue,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final k in dailyHelpKinds) DropdownMenuItem(value: k, child: Text(_kind(k)))],
              onChanged: (v) => setState(() => _kindValue = v ?? _kindValue),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                helperText: 'If they already work for another flat here, the same pass is shared',
              ),
            ),
            if (widget.existing == null && widget.flats.length > 1) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _flat,
                decoration: const InputDecoration(labelText: 'Flat'),
                items: [for (final f in widget.flats) DropdownMenuItem(value: f.$1, child: Text(f.$2))],
                onChanged: (v) => setState(() => _flat = v),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Allowed days'),
            Wrap(
              spacing: 4,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(_dayNames[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (s) => setState(() => s ? _days.add(d) : _days.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _pickTime(true), child: Text('From ${_start ?? 'any'}')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(onPressed: () => _pickTime(false), child: Text('To ${_end ?? 'any'}')),
                ),
                IconButton(
                  tooltip: 'Any time',
                  onPressed: () => setState(() => _start = _end = null),
                  icon: const Icon(Icons.clear),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
              title: const Text('Alert the flat on entry and exit'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
    ],
  );
}

class _VisitsDialog extends StatelessWidget {
  const _VisitsDialog(this.h);
  final DailyHelp h;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${h.name} · code ${h.code}'),
    content: SizedBox(
      width: 420,
      child: FutureBuilder<List<DailyHelpVisit>>(
        future: DailyHelpRepo.visits(h.id),
        builder: (context, snap) {
          if (snap.hasError) return Text(friendlyError(snap.error!));
          if (!snap.hasData) return const LinearProgressIndicator();
          final list = snap.data!;
          final now = DateTime.now();
          final days = {
            for (final v in list)
              if (v.inAt.year == now.year && v.inAt.month == now.month) _dm(v.inAt),
          }.length;
          return ListView(
            shrinkWrap: true,
            children: [
              Text('$days day${days == 1 ? '' : 's'} this month', style: Theme.of(context).textTheme.titleSmall),
              if (list.isEmpty) const Text('No entries yet.'),
              for (final v in list)
                ListTile(
                  dense: true,
                  title: Text('${_dm(v.inAt)}  in ${_hm(v.inAt)}  ·  out ${v.outAt == null ? '—' : _hm(v.outAt!)}'),
                  subtitle: v.guard == null ? null : Text('by ${v.guard}'),
                ),
            ],
          );
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}

/// Gate: find a daily-help pass by code or name and check them in/out. Works offline from the last saved list.
class DailyHelpGateDialog extends StatefulWidget {
  const DailyHelpGateDialog({super.key, required this.onQueued});
  final VoidCallback onQueued;

  @override
  State<DailyHelpGateDialog> createState() => _DailyHelpGateDialogState();
}

class _DailyHelpGateDialogState extends State<DailyHelpGateDialog> {
  List<DailyHelp> _list = const [];
  bool _loading = true, _offline = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DailyHelpRepo.load();
      await GateOffline.cacheHelp(list);
      if (mounted) {
        setState(() {
          _list = list;
          _loading = _offline = false;
        });
      }
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
      }
      final cached = await GateOffline.cachedHelp();
      if (mounted) {
        setState(() {
          _list = cached;
          _loading = false;
          _offline = isOffline(e);
        });
      }
    }
  }

  Future<void> _go(DailyHelp h) async {
    final checkIn = !h.inside;
    try {
      final name = await DailyHelpRepo.entry(h.id, checkIn: checkIn);
      if (mounted) toast(context, '$name ${checkIn ? 'entered' : 'left'}');
      await _load();
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      if (checkIn && !DailyHelpRepo.allowedNow(h, DateTime.now())) {
        if (mounted) toast(context, '${h.name} is outside allowed days/hours. Use Walk-in.');
        return;
      }
      await GateOffline.add({'kind': 'help', 'id': h.id, 'in': checkIn, 'label': '${h.name} (daily help)'});
      final updated = [
        for (final x in _list)
          x.id == h.id ? DailyHelpRepo.fromJson({...DailyHelpRepo.toJson(x), 'inside': checkIn}) : x,
      ];
      await GateOffline.cacheHelp(updated);
      widget.onQueued();
      if (mounted) {
        setState(() => _list = updated);
        toast(context, 'Saved on this phone – will send when online');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final h in _list)
        if (q.isEmpty || h.code == q || h.name.toLowerCase().contains(q) || h.flats.toLowerCase().contains(q)) h,
    ]..sort((a, b) => (b.inside ? 1 : 0) - (a.inside ? 1 : 0));
    return AlertDialog(
      title: Text(_offline ? 'Daily help (offline)' : 'Daily help'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '6-digit code, name or flat'),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && shown.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('No matching pass.')),
            Expanded(
              child: ListView(
                children: [
                  for (final h in shown)
                    ListTile(
                      title: Text('${h.name} · ${_kind(h.kind)}'),
                      subtitle: Text('${h.flats} · ${_schedule(h)}'),
                      trailing: h.inside
                          ? OutlinedButton(onPressed: () => _go(h), child: const Text('Out'))
                          : FilledButton(onPressed: () => _go(h), child: const Text('In')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
