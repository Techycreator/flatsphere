import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';

/// New membership / committee change requests (spec W20–W22).
enum MembershipRequestType {
  owner('W20', 'Owner change', 'Sale, gift or inheritance of a flat'),
  resident('W21', 'Resident change', 'New or outgoing tenant / occupant'),
  committee('W22', 'Committee member change', 'President, Secretary, other office bearer or EC member');

  const MembershipRequestType(this.code, this.label, this.hint);
  final String code;
  final String label;
  final String hint;

  static MembershipRequestType? parse(String s) => values.where((v) => v.name == s).firstOrNull;
}

class MembershipRequestScreen extends ConsumerStatefulWidget {
  const MembershipRequestScreen({super.key, required this.type});
  final MembershipRequestType type;

  @override
  ConsumerState<MembershipRequestScreen> createState() => _MembershipRequestScreenState();
}

class _MembershipRequestScreenState extends ConsumerState<MembershipRequestScreen> {
  String _flat = demoFlats.first.number;
  final _newName = TextEditingController();
  final _mobile = TextEditingController();
  final _deed = TextEditingController();
  final _lease = TextEditingController(text: '1 Nov 2026 – 31 Oct 2027');
  int _family = 1;
  bool _docs = false;
  bool _police = false;
  String _position = 'Joint Secretary';
  String _changeType = 'Resignation and replacement';
  final _outgoing = TextEditingController();
  String _mom = 'EC-2026-10 · Decision #3';
  final _for = TextEditingController(text: '7');
  final _against = TextEditingController(text: '1');
  final _abstain = TextEditingController(text: '0');

  Flat get flat => demoFlats.firstWhere((f) => f.number == _flat);

  void _submit() {
    final s = ref.read(sessionProvider)!;
    final role = s.activeRole;
    if (_newName.text.trim().isEmpty) {
      toast(context, 'Enter the incoming person\'s name');
      return;
    }
    final notifier = ref.read(approvalsProvider.notifier);
    final id = notifier.nextId();
    final f = flat;
    final pendingDues = ref.read(duesProvider).pendingFor(f.number);
    final ownerSelf = widget.type == MembershipRequestType.resident && role == Role.owner;
    late final ApprovalRequest req;
    switch (widget.type) {
      case MembershipRequestType.owner:
        // Secretary AND President; the VP takes the initiator's slot (maker-checker).
        final steps = switch (role) {
          Role.secretary => const [ApproverStep(role: Role.president, name: 'Rajesh Menon'), ApproverStep(role: Role.vicePresident, name: 'Vice President', onBehalfOf: 'Secretary')],
          Role.president => const [ApproverStep(role: Role.secretary, name: 'Anitha Nair'), ApproverStep(role: Role.vicePresident, name: 'Vice President', onBehalfOf: 'President')],
          _ => const [ApproverStep(role: Role.secretary, name: 'Anitha Nair'), ApproverStep(role: Role.president, name: 'Rajesh Menon')],
        };
        req = ApprovalRequest(
          id: id, code: 'W20', category: 'Membership', title: 'Owner change – ${f.number}: ${f.ownerName} → ${_newName.text.trim()}',
          initiatorName: s.user.name, initiatorRole: role, createdAt: DateTime.now(), steps: steps,
          details: {
            'Flat': '${f.number} (${f.type})',
            'Current owner': f.ownerName,
            'New owner(s)': '${_newName.text.trim()} · ${_mobile.text.trim()}',
            'Sale deed': _deed.text.trim().isEmpty ? 'Not entered' : _deed.text.trim(),
            'Documents': _docs ? 'Sale deed + ID proofs uploaded' : 'Pending upload',
            'Dues check': pendingDues == 0 ? 'All dues cleared ✓' : 'Pending ${inr.format(pendingDues)} – must be cleared before final approval',
          },
        );
      case MembershipRequestType.resident:
        req = ApprovalRequest(
          id: id, code: 'W21', category: 'Membership', title: 'Resident change – ${f.number}: ${f.residentName ?? 'vacant'} → ${_newName.text.trim()}',
          initiatorName: s.user.name, initiatorRole: role, createdAt: DateTime.now(),
          steps: [
            if (!ownerSelf) ApproverStep(role: Role.owner, name: f.ownerName),
            const ApproverStep(role: Role.secretary, alternateRole: Role.president, name: 'Anitha Nair / Rajesh Menon'),
          ],
          details: {
            'Flat': '${f.number} (owner: ${f.ownerName})',
            'Owner consent': ownerSelf ? 'Given – request raised by the owner' : 'Requested in the owner\'s app',
            'Outgoing resident': f.residentName ?? 'None (vacant / owner-occupied)',
            'Incoming resident': '${_newName.text.trim()} + $_family family member(s)',
            'Lease': _lease.text.trim(),
            'ID proofs': _docs ? 'Uploaded (Aadhaar masked)' : 'Pending upload',
            'Police verification': _police ? 'Form submitted' : 'Pending',
            'On approval': 'Resident record updated; outgoing tenant and family logins disabled immediately and archived; new logins (age 12+) created; caretaker informed',
          },
        );
      case MembershipRequestType.committee:
        final steps = _position == 'President'
            ? const [ApproverStep(role: Role.vicePresident, name: 'Vice President', onBehalfOf: 'President')]
            : const [ApproverStep(role: Role.president, name: 'Rajesh Menon')];
        req = ApprovalRequest(
          id: id, code: 'W22', category: 'Committee', title: 'Committee change – $_position: ${_outgoing.text.trim().isEmpty ? 'vacancy' : _outgoing.text.trim()} → ${_newName.text.trim()}',
          initiatorName: s.user.name, initiatorRole: role, createdAt: DateTime.now(), momRequired: true, momRef: _mom, steps: steps,
          details: {
            'Position': _position,
            'Change type': _changeType,
            'Outgoing': _outgoing.text.trim().isEmpty ? '—' : _outgoing.text.trim(),
            'Incoming': _newName.text.trim(),
            'EC formal vote': '${_for.text} for · ${_against.text} against · ${_abstain.text} abstain',
            'GBM ratification': _position == 'EC member' ? 'Not required' : 'Required at next General Body (office bearer)',
          },
        );
    }
    notifier.add(req);
    toast(context, '$id submitted. Approvers notified.');
    context.go('/approvals/$id');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider)!;
    final t = widget.type;
    final ownerSelf = t == MembershipRequestType.resident && s.activeRole == Role.owner;
    final ownFlats = demoFlats.where((f) => f.ownerName == s.user.name && f.occupancy != Occupancy.ownerOccupied).toList();
    if (ownerSelf && ownFlats.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(t.label)), body: const EmptyState('You have no rented or vacant flat to change the resident for.', icon: Icons.home_outlined));
    }
    if (!s.user.canInitiateMembership(s.activeRole) && !ownerSelf) {
      return Scaffold(
        appBar: AppBar(title: Text(t.label)),
        body: const EmptyState('Only the President, Secretary or a designated EC member (Membership desk) can start this request.', icon: Icons.lock_outline),
      );
    }
    final pendingDues = ref.watch(duesProvider).pendingFor(_flat);
    final flats = ownerSelf
        ? ownFlats
        : t == MembershipRequestType.resident
            ? demoFlats.where((f) => f.occupancy != Occupancy.ownerOccupied).toList()
            : demoFlats;
    if (!flats.any((f) => f.number == _flat)) _flat = flats.first.number;

    final flatPicker = DropdownButtonFormField<String>(
      initialValue: _flat,
      decoration: const InputDecoration(labelText: 'Flat'),
      items: [for (final f in flats) DropdownMenuItem(value: f.number, child: Text('${f.number} · ${f.ownerName}${f.residentName != null ? ' · tenant ${f.residentName}' : ''}'))],
      onChanged: (v) => setState(() => _flat = v!),
    );

    final approvalsText = switch (t) {
      MembershipRequestType.owner => 'Approvals: Secretary AND President (if one of them starts it, the VP takes that slot). Old owner is archived after approval.',
      MembershipRequestType.resident => ownerSelf
          ? 'Your consent is recorded. Secretary OR President approves; nothing changes until then. On approval the outgoing tenant\'s logins are disabled.'
          : 'Approvals: flat owner\'s consent in the app, then Secretary OR President. Caretaker is informed.',
      MembershipRequestType.committee => 'Approvals: formal EC vote recorded in the MOM, then President (VP if the President is being changed). Office bearer changes need General Body ratification if bylaws require.',
    };

    return Scaffold(
      appBar: AppBar(title: Text('${t.code} · ${t.label}')),
      body: PageBody(maxWidth: 720, children: [
        Card(
          color: Colors.indigo.withValues(alpha: 0.05),
          child: ListTile(leading: const Icon(Icons.route_outlined, color: Colors.indigo), title: Text(t.hint), subtitle: Text(approvalsText)),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (t != MembershipRequestType.committee) ...[flatPicker, const SizedBox(height: 12)],
              if (t == MembershipRequestType.owner) ...[
                _info('Current owner', flat.ownerName),
                if (pendingDues > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Pill('Pending dues ${inr.format(pendingDues)} – must be cleared before final approval', color: AppColors.red, icon: Icons.warning_amber),
                  )
                else
                  const Padding(padding: EdgeInsets.only(bottom: 8), child: Pill('All dues cleared', color: AppColors.green, icon: Icons.check)),
                TextField(controller: _newName, decoration: const InputDecoration(labelText: 'New owner name(s) *')),
                const SizedBox(height: 12),
                TextField(controller: _mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'New owner mobile', prefixText: '+91 ')),
                const SizedBox(height: 12),
                TextField(controller: _deed, decoration: const InputDecoration(labelText: 'Sale deed / registration number')),
              ],
              if (t == MembershipRequestType.resident) ...[
                _info(ownerSelf ? 'Owner' : 'Owner (will be asked to consent)', flat.ownerName),
                _info('Outgoing resident', flat.residentName ?? 'None'),
                TextField(controller: _newName, decoration: const InputDecoration(labelText: 'Incoming resident name *')),
                const SizedBox(height: 12),
                TextField(controller: _lease, decoration: const InputDecoration(labelText: 'Lease period')),
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(child: Text('Family members (logins for age 12+)')),
                  IconButton(onPressed: _family > 0 ? () => setState(() => _family--) : null, icon: const Icon(Icons.remove_circle_outline)),
                  Text('$_family'),
                  IconButton(onPressed: () => setState(() => _family++), icon: const Icon(Icons.add_circle_outline)),
                ]),
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: _police, onChanged: (v) => setState(() => _police = v!), title: const Text('Police verification form submitted')),
              ],
              if (t == MembershipRequestType.committee) ...[
                DropdownButtonFormField<String>(
                  initialValue: _position,
                  decoration: const InputDecoration(labelText: 'Position'),
                  items: [for (final p in const ['President', 'Secretary', 'Treasurer', 'Vice President', 'Joint Secretary', 'Joint Treasurer', 'EC member']) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) => setState(() => _position = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _changeType,
                  decoration: const InputDecoration(labelText: 'Change type'),
                  items: [for (final p in const ['Resignation and replacement', 'Co-option to vacancy', 'Removal (as per bylaws)', 'Role swap within EC']) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) => setState(() => _changeType = v!),
                ),
                const SizedBox(height: 12),
                TextField(controller: _outgoing, decoration: const InputDecoration(labelText: 'Outgoing member (if any)')),
                const SizedBox(height: 12),
                TextField(controller: _newName, decoration: const InputDecoration(labelText: 'Incoming member *')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mom,
                  decoration: const InputDecoration(labelText: 'Linked MOM decision (mandatory)'),
                  items: [for (final m in const ['EC-2026-10 · Decision #3', 'EC-2026-09 · Decision #5']) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (v) => setState(() => _mom = v!),
                ),
                const SizedBox(height: 12),
                const Text('EC formal vote'),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: TextField(controller: _for, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'For'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _against, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Against'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _abstain, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Abstain'))),
                ]),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _docs,
                onChanged: (v) => setState(() => _docs = v!),
                title: Text(t == MembershipRequestType.committee ? 'Resignation letter / consent uploaded' : 'Documents and ID proofs uploaded'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.send), label: const Padding(padding: EdgeInsets.all(12), child: Text('Submit for approval'))),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [SizedBox(width: 200, child: Text(k, style: const TextStyle(color: Colors.black54))), Expanded(child: Text(v))]),
      );
}
