import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show AssociationContext, backendEnabled, db;
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/gate_offline.dart';
import '../../backend/gate_repo.dart';
import '../../backend/visitor_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'daily_help.dart';
import 'gate_widgets.dart';

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
  int _legacyPending = 0;
  bool _recoveringLegacy = false;
  String? _onDuty;
  String? _activeAssociationId;
  Future<void>? _loading;
  bool _loadAgain = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (backendEnabled) GateRepo.purgeOldPhotos().catchError((_) {});
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_loading == null) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() {
    if (!backendEnabled) return Future<void>.value();
    final loading = _loading;
    if (loading != null) {
      _loadAgain = true;
      return loading;
    }
    final next = _drainLoads();
    _loading = next;
    return next;
  }

  Future<void> _drainLoads() async {
    try {
      do {
        _loadAgain = false;
        await _loadOnce();
      } while (_loadAgain && mounted);
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadOnce() async {
    if (!backendEnabled) return;
    final associationId = ref.read(sessionProvider)?.user.associationId;
    if (associationId == null) return;
    if (_activeAssociationId != associationId) {
      _activeAssociationId = associationId;
      _list = const [];
      _pending = 0;
      _onDuty = null;
      final p = await SharedPreferences.getInstance();
      if (!mounted || _activeAssociationId != associationId) return;
      setState(() => _onDuty = p.getString(GateOffline.guardKey(associationId)));
    }
    if (ref.read(sessionProvider)?.user.associationId != associationId) return;
    final legacy = await GateOffline.legacyQueue();
    if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
    if (_legacyPending != legacy.length) setState(() => _legacyPending = legacy.length);
    try {
      await GateOffline.recoverAssignedLegacyQueue(associationId);
      final remainingLegacy = await GateOffline.legacyQueue();
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      if (_legacyPending != remainingLegacy.length) {
        setState(() => _legacyPending = remainingLegacy.length);
      }
      final onDuty = await GateRepo.currentShift(associationId);
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      final preferences = await SharedPreferences.getInstance();
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      if (onDuty == null) {
        await preferences.remove(GateOffline.guardKey(associationId));
      } else {
        await preferences.setString(GateOffline.guardKey(associationId), onDuty);
      }
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      setState(() => _onDuty = onDuty);
      final (sent, failed) = await GateOffline.flush(associationId);
      if (ref.read(sessionProvider)?.user.associationId != associationId) return;
      if (mounted && sent > 0) toast(context, '$sent saved gate entr${sent == 1 ? 'y' : 'ies'} sent');
      for (final f in failed) {
        if (mounted) toast(context, 'Not accepted: $f');
      }
      final list = await GateRepo.today(associationId: associationId);
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      await GateOffline.cache(associationId, list);
      final pending = (await GateOffline.queue(associationId)).length;
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
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
        final cached = _list.isEmpty ? await GateOffline.cached(associationId) : _list;
        final pending = (await GateOffline.queue(associationId)).length;
        if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
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

  Future<void> _recoverLegacyQueue() async {
    if (_recoveringLegacy) return;
    final user = ref.read(sessionProvider)?.user;
    if (user == null || user.associations.isEmpty) return;
    setState(() => _recoveringLegacy = true);
    try {
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Recover older saved gate entries'),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'These entries were saved before queues were separated by association. '
                'Choose the association they belong to; they will stay saved until you choose.',
              ),
            ),
            for (final association in user.associations)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, association.id),
                child: Text(association.name),
              ),
            SimpleDialogOption(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      final currentUser = ref.read(sessionProvider)?.user;
      if (currentUser == null || !currentUser.associations.any((a) => a.id == selected)) return;
      final recovered = await GateOffline.recoverLegacyQueue(selected);
      final remaining = await GateOffline.legacyQueue();
      if (mounted) {
        setState(() => _legacyPending = remaining.length);
        if (recovered > 0) {
          toast(
            context,
            '$recovered older gate ${recovered == 1 ? 'entry' : 'entries'} assigned to the selected association.',
          );
        }
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _recoveringLegacy = false);
    }
  }

  void _setLocal(String id, String status, {String? approval}) => setState(
    () => _list = [
      for (final v in _list)
        v.id == id
            ? (
                id: v.id,
                guest: v.guest,
                phone: v.phone,
                flat: v.flat,
                status: status,
                approval: approval ?? v.approval,
                type: v.type,
                vehicle: v.vehicle,
                passCode: v.passCode,
                arrival: v.arrival,
                note: v.note,
                photoPath: v.photoPath,
                guardName: v.guardName,
              )
            : v,
    ],
  );

  Future<bool> _verify(GateVisitor v, bool checkIn) async {
    final word = checkIn ? 'in' : 'out';
    final associationId = ref.read(sessionProvider)?.user.associationId;
    if (associationId == null) return false;
    try {
      await VisitorRepo.verify(v.id, checkIn ? VisitorStatus.checkedIn : VisitorStatus.checkedOut);
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return false;
      toast(context, '${v.guest} checked $word');
      await _load();
      return true;
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return false;
      }
      if (!mounted) return false;
      if (ref.read(sessionProvider)?.user.associationId != associationId) return false;
      await GateOffline.add(associationId, {
        'kind': 'verify',
        'id': v.id,
        'action': checkIn ? 'check_in' : 'check_out',
        'label': '${v.guest} → ${v.flat}',
      });
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return false;
      _setLocal(v.id, checkIn ? 'checked_in' : 'checked_out');
      setState(() => _pending++);
      toast(context, 'Offline: ${v.guest} checked $word. It will sync when the network is back.');
      return true;
    }
  }

  String _walkInDoneMessage(WalkInData d) => switch (d.mode) {
    'lobby' => 'Logged: ${d.name} left at the lobby for flat ${d.flat}. Tap Check out when they leave.',
    'staff' => 'Logged: ${d.name} let in to meet ${d.meet}. Tap Check out when they leave.',
    _ => 'Sent to flat ${d.flat}. Wait for Approved before letting them in.',
  };

  /// The flat did not answer: leave the delivery at the lobby and track it until it leaves.
  Future<void> _lobby(GateVisitor v) async {
    final associationId = ref.read(sessionProvider)?.user.associationId;
    if (associationId == null) return;
    try {
      await GateRepo.lobbyDrop(v.id);
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      toast(context, '${v.guest}: left at the lobby. Tap Check out when they leave.');
      await _load();
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      await GateOffline.add(associationId, {'kind': 'lobby', 'id': v.id, 'label': '${v.guest} → ${v.flat} (lobby)'});
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      _setLocal(v.id, 'checked_in', approval: 'lobby');
      await GateOffline.cache(associationId, _list);
      setState(() => _pending++);
      toast(context, 'Offline: ${v.guest} left at the lobby. It will sync when the network is back.');
    }
  }

  Future<void> _callFlat([String? flat]) async {
    final flats = await loadGateFlats(ref.read(sessionProvider)?.user.associationId);
    if (!mounted) return;
    await openGatePage<void>(context, CallFlatPage(flats: flats, initial: flat?.trim().toUpperCase()));
  }

  Future<void> _startShift() async {
    final associationId = ref.read(sessionProvider)?.user.associationId;
    if (associationId == null) return;
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
    final g = await openGatePage<({String id, String name})>(context, GuardPickPage(guards: guards));
    if (g == null || !mounted) return;
    final pin = await showCodePad(
      context,
      title: 'Guard PIN',
      subtitle: 'Hi ${g.name}, enter your 4-digit PIN',
      length: 4,
      obscure: true,
      action: 'Start shift',
    );
    if (pin == null) return;
    final gid = g.id;
    try {
      final result = await AssociationContext.run(() async {
        if (await db.rpc('my_association') != associationId) {
          throw StateError('The active association changed. Reopen the gate action and try again.');
        }
        return GateRepo.startShift(gid, pin);
      });
      final name = result.name;
      if (name == null) {
        if (mounted) toast(context, result.error ?? 'Wrong guard or PIN');
        return;
      }
      if (ref.read(sessionProvider)?.user.associationId != associationId) return;
      await (await SharedPreferences.getInstance()).setString(GateOffline.guardKey(associationId), name);
      if (!mounted || ref.read(sessionProvider)?.user.associationId != associationId) return;
      if (mounted) {
        setState(() => _onDuty = name);
        toast(context, 'Shift started: $name. Entries are recorded under this name.');
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _pass() async {
    final code = await showCodePad(
      context,
      title: 'Visitor pass code',
      subtitle: 'Enter the 6-digit code the guest shows',
      action: 'Check in',
    );
    if (code == null || !mounted) return;
    try {
      final who = await GateRepo.checkPass(code);
      if (mounted) {
        await showGateResult(
          context,
          ok: who != null,
          message: who == null ? 'Code $code is not valid today.\nCall the flat or use Walk-in.' : 'Let in:\n$who',
        );
      }
      await _load();
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      final match = _list.where((v) => v.passCode == code && v.status == 'expected').firstOrNull;
      if (match == null) {
        if (mounted) {
          await showGateResult(
            context,
            ok: false,
            message: 'Offline and this code is not in the saved list.\nCall the flat or use Walk-in.',
          );
        }
        return;
      }
      if (await _verify(match, true) && mounted) {
        await showGateResult(context, ok: true, message: 'Let in:\n${match.guest} → ${match.flat}');
      }
    }
  }

  Future<void> _walkIn() async {
    final associationId = ref.read(sessionProvider)?.user.associationId;
    if (associationId == null) return;
    final flats = await loadGateFlats(associationId);
    final staff = await loadGateStaff(associationId);
    if (!mounted) return;
    final d = await openGatePage<WalkInData>(context, WalkInPage(flats: flats, staff: staff));
    if (d == null) return;
    final f = d.flat, pic = d.photo;
    final requestId = GateRepo.newWalkInRequestId();
    var photoFailed = false;
    try {
      await AssociationContext.run(() async {
        if (await db.rpc('my_association') != associationId) {
          throw StateError('The active association changed. Reopen the gate action and try again.');
        }
        final id = await GateRepo.walkIn(
          requestId: requestId,
          flat: f,
          name: d.name,
          phone: d.phone,
          type: d.type,
          vehicle: d.vehicle,
          mode: d.mode,
          note: d.note,
          meet: d.meet,
          staffId: d.staffId,
        );
        if (pic != null) {
          try {
            await GateRepo.attachPhoto(id, pic);
          } catch (_) {
            photoFailed = true;
          }
        }
      });
      if (photoFailed && mounted) toast(context, 'Visitor sent, but the photo could not be uploaded.');
      if (mounted) toast(context, _walkInDoneMessage(d));
      await _load();
    } catch (e) {
      if (!isOffline(e)) {
        if (mounted) toast(context, friendlyError(e));
        return;
      }
      await GateOffline.add(associationId, {
        'kind': 'walkin',
        'flat': f,
        'name': d.name,
        'phone': d.phone,
        'type': d.type,
        'vehicle': d.vehicle,
        'photo': pic == null ? null : base64Encode(pic),
        'request_id': requestId,
        'mode': d.mode,
        'note': d.note,
        'meet': d.meet,
        'staff_id': d.staffId,
        'label': '${d.name} → ${d.mode == 'staff' ? d.meet : f}',
      });
      if (mounted && ref.read(sessionProvider)?.user.associationId == associationId) {
        final local = (
          id: requestId,
          guest: d.name,
          phone: d.phone.isEmpty ? null : d.phone,
          flat: d.mode == 'staff' ? 'Staff: ${d.meet}' : f,
          status: d.mode == 'ask' ? 'expected' : 'checked_in',
          approval: switch (d.mode) {
            'lobby' => 'lobby',
            'staff' => 'staff_confirmed',
            _ => 'awaiting',
          },
          type: d.type,
          vehicle: d.vehicle.isEmpty ? null : d.vehicle,
          passCode: null,
          arrival: DateTime.now(),
          note: d.note,
          photoPath: null,
          guardName: null,
        );
        setState(() {
          _list = [..._list, local];
          _pending++;
        });
        await GateOffline.cache(associationId, _list);
        if (mounted) {
          toast(
            context,
            d.mode == 'ask'
                ? 'Offline: saved. It goes to flat $f when the network is back. Call the flat meanwhile.'
                : 'Offline: ${_walkInDoneMessage(d)} It will sync when the network is back.',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s?.user.associationId), (_, _) {
      setState(() {
        _list = const [];
        _pending = 0;
        _onDuty = null;
        _offline = false;
        _error = null;
        _activeAssociationId = null;
      });
      _load();
    });
    final role = ref.watch(sessionProvider)?.activeRole;
    final associationId = ref.watch(sessionProvider)?.user.associationId;
    if (!backendEnabled) return const PageBody(children: [EmptyState('Gate mode works in the cloud version.')]);
    if (!const {Role.security, Role.caretaker, Role.admin, Role.president, Role.secretary}.contains(role)) {
      return const PageBody(children: [EmptyState('Gate mode is for security staff.')]);
    }
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final canManage = const {Role.admin, Role.president, Role.secretary}.contains(role);
    final primary = Theme.of(context).colorScheme.primary;
    Widget tile(IconData icon, String label, Color color, VoidCallback onTap) => SizedBox(
      height: narrow ? 116 : 136,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    final tiles = [
      tile(Icons.pin, 'Pass code', primary, _pass),
      tile(Icons.person_add_alt_1, 'Walk-in', primary, _walkIn),
      tile(Icons.cleaning_services, 'Daily help', const Color(0xFF00796B), () {
        if (associationId != null) {
          openGatePage<void>(context, DailyHelpGateDialog(associationId: associationId, onQueued: () => _load()));
        }
      }),
      tile(Icons.call, 'Call a flat', AppColors.green, () => _callFlat()),
    ];
    int rank(GateVisitor v) => switch ((v.approval, v.status)) {
      ('approved', 'expected') => 0,
      ('awaiting', _) => 1,
      (_, 'expected') => 2,
      _ => 3,
    };
    final active = _list.where((v) => v.status == 'expected' || v.status == 'checked_in').toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    Widget grid(List<Widget> items, int cols, {double gap = 12}) => LayoutBuilder(
      builder: (_, c) {
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final i in items) SizedBox(width: w, child: i)],
        );
      },
    );
    return PageBody(
      maxWidth: 1100,
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: (_onDuty == null ? AppColors.amber : AppColors.green).withValues(alpha: .15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _onDuty == null ? Icons.warning_amber_rounded : Icons.verified_user,
                      size: 32,
                      color: _onDuty == null ? AppColors.amber : AppColors.green,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _onDuty == null ? 'No guard on duty' : 'On duty: $_onDuty',
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: _startShift,
                    icon: const Icon(Icons.how_to_reg, size: 30),
                    label: Text(
                      _onDuty == null ? 'Start shift' : 'Change guard',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_offline)
          Card(
            color: AppColors.amber.withValues(alpha: .15),
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined, size: 32),
              title: const Text('Offline – entries are saved on this phone', style: TextStyle(fontSize: 18)),
              subtitle: Text('$_pending waiting to send. Pass codes are checked against the last saved list.'),
            ),
          )
        else if (_pending > 0)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('$_pending saved entries waiting to send…')),
        if (_legacyPending > 0)
          Card(
            color: AppColors.amber.withValues(alpha: .15),
            child: ListTile(
              leading: const Icon(Icons.history, size: 32),
              title: Text(
                '$_legacyPending older saved gate ${_legacyPending == 1 ? 'entry' : 'entries'} need an association',
              ),
              subtitle: const Text('Choose where to recover them before they can sync.'),
              trailing: TextButton(
                onPressed: _recoveringLegacy ? null : _recoverLegacyQueue,
                child: const Text('Recover'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        grid(tiles, narrow ? 2 : 4),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              'At the gate now (${active.length})',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => const _GateHistoryDialog()),
                  icon: const Icon(Icons.history, size: 26),
                  label: const Text('History', style: TextStyle(fontSize: 17)),
                ),
                if (canManage)
                  TextButton.icon(
                    onPressed: () => showDialog<void>(context: context, builder: (_) => const _GuardsDialog()),
                    icon: const Icon(Icons.badge_outlined, size: 26),
                    label: const Text('Guards', style: TextStyle(fontSize: 17)),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null) Text(_error!),
        if (active.isEmpty) const EmptyState('No visitors expected right now.'),
        grid([for (final v in active) _visitorCard(v)], MediaQuery.sizeOf(context).width >= 1000 ? 2 : 1),
      ],
    );
  }

  Widget _visitorCard(GateVisitor v) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (v.photoPath != null) ...[VisitorPhoto(path: v.photoPath!), const SizedBox(width: 12)],
              Expanded(
                child: Text(
                  '${v.guest} → ${v.flat}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              v.type,
              if (v.approval == 'lobby') 'left at lobby',
              if (v.approval == 'staff_confirmed') 'confirmed by staff',
              if (v.vehicle != null) v.vehicle!,
              if (v.phone != null) v.phone!,
              if (v.note.isNotEmpty) 'Purpose: ${v.note}',
              dateTimeFmt.format(v.arrival),
              if (v.guardName != null) 'by ${v.guardName}',
            ].join(' · '),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    foregroundColor: AppColors.green,
                    side: const BorderSide(color: AppColors.green, width: 1.5),
                  ),
                  onPressed: () => _callFlat(v.flat),
                  icon: const Icon(Icons.call, size: 26),
                  label: const Text('Call flat', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: switch ((v.approval, v.status)) {
                  ('awaiting', _) when v.type == 'delivery' => OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      foregroundColor: AppColors.amber,
                      side: const BorderSide(color: AppColors.amber, width: 1.5),
                    ),
                    onPressed: () => _lobby(v),
                    child: const Text('No answer · Lobby', style: TextStyle(fontSize: 18), textAlign: TextAlign.center),
                  ),
                  ('awaiting', _) => const Center(child: Pill('Waiting for flat', color: AppColors.amber)),
                  ('denied', _) => const Center(child: Pill('Denied', color: AppColors.red)),
                  (_, 'checked_in') => OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                    onPressed: () => _verify(v, false),
                    child: const Text('Check out', style: TextStyle(fontSize: 18)),
                  ),
                  _ => FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                    onPressed: () => _verify(v, true),
                    child: Text(
                      v.approval == 'approved' ? 'Approved · Let in' : 'Check in',
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Shown to residents: walk-ins waiting at the gate, plus pass codes to share with expected guests.
class GateAlertsCard extends ConsumerStatefulWidget {
  const GateAlertsCard({super.key});

  @override
  ConsumerState<GateAlertsCard> createState() => _GateAlertsCardState();
}

class _GateAlertsCardState extends ConsumerState<GateAlertsCard> {
  List<GateVisitor> _list = const [];
  Timer? _timer;
  (String?, bool)? _loadedScope;

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
    final session = ref.read(sessionProvider);
    final associationId = session?.user.associationId;
    if (associationId == null) return;
    final hostOnly = session?.activeRole == Role.owner || session?.activeRole == Role.resident;
    try {
      final list = await GateRepo.today(associationId: associationId, hostOnly: hostOnly);
      final current = ref.read(sessionProvider);
      if (mounted &&
          current?.user.associationId == associationId &&
          (current?.activeRole == Role.owner || current?.activeRole == Role.resident) == hostOnly) {
        setState(() {
          _list = list;
          _loadedScope = (associationId, hostOnly);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => (s?.user.associationId, s?.activeRole)), (_, _) {
      setState(() {
        _list = const [];
        _loadedScope = null;
      });
      _load();
    });
    final session = ref.watch(sessionProvider);
    final hostOnly = session?.activeRole == Role.owner || session?.activeRole == Role.resident;
    final currentScope = (session?.user.associationId, hostOnly);
    final list = _loadedScope == currentScope ? _list : const <GateVisitor>[];
    // Approve/Deny only for the user's own flats (owner or resident) in this association.
    final myFlats = {...?session?.user.flatsFor(Role.owner), ...?session?.user.flatsFor(Role.resident)};
    final waiting = list.where((v) => v.approval == 'awaiting' && myFlats.contains(v.flat)).toList();
    final codes = list.where((v) => v.status == 'expected' && v.passCode != null).toList();
    if (waiting.isEmpty && codes.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final v in waiting) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: v.photoPath == null
                    ? const Icon(Icons.doorbell_outlined, color: AppColors.amber)
                    : VisitorPhoto(path: v.photoPath!),
                title: Text('${v.guest} is at the gate for ${v.flat}'),
                subtitle: Text([
                  v.type,
                  if (v.note.isNotEmpty) 'Purpose: ${v.note}',
                  if (v.vehicle != null) v.vehicle!,
                ].join(' · ')),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(110, 48)),
                    onPressed: () async {
                      try {
                        await GateRepo.decide(v.id, false);
                      } catch (e) {
                        if (context.mounted) toast(context, friendlyError(e));
                      }
                      if (!mounted) return;
                      _load();
                    },
                    child: const Text('Deny'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
                    onPressed: () async {
                      try {
                        await GateRepo.decide(v.id, true);
                      } catch (e) {
                        if (context.mounted) toast(context, friendlyError(e));
                      }
                      if (!mounted) return;
                      _load();
                    },
                    child: const Text('Approve'),
                  ),
                ],
              ),
              const Divider(),
            ],
            if (codes.isNotEmpty) ...[
              const Text(
                'Gate pass codes – tell this number to your guest',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              for (final v in codes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pin_outlined, size: 30),
                  title: Text(v.guest, style: const TextStyle(fontSize: 17)),
                  subtitle: Text('${v.flat} · ${dateTimeFmt.format(v.arrival)}'),
                  trailing: SelectableText(
                    v.passCode!,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3),
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
            const SizedBox(height: 12),
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
    ('lobby', 'checked_out') => 'Lobby drop · Left',
    ('lobby', _) => 'Lobby drop · Inside',
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
