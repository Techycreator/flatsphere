import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../backend/backend.dart' show backendEnabled;
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/upload_preparation.dart' show maxSourceUploadBytes;
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/directory_state.dart';
import '../../state/demo_data.dart';
import '../../widgets/common.dart';
import '../../validation/input_validation.dart';

/// New membership / committee change requests (spec W20–W22).
enum MembershipRequestType {
  owner('W20', 'Owner change', 'Sale, gift or inheritance of a flat'),
  resident('W21', 'Tenant / resident change', 'New or outgoing tenant / occupant'),
  committee('W22', 'Committee member change', 'President, Secretary, other office bearer or EC member');

  const MembershipRequestType(this.code, this.label, this.hint);
  final String code;
  final String label;
  final String hint;

  static MembershipRequestType? parse(String s) => values.where((v) => v.name == s).firstOrNull;
}

class _FamilyDependentDraft {
  final name = TextEditingController();
  final email = TextEditingController();
  DateTime? dateOfBirth;

  void dispose() {
    name.dispose();
    email.dispose();
  }
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
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _deed = TextEditingController();
  final _lease = TextEditingController(text: '1 Nov 2026 – 31 Oct 2027');
  final List<_FamilyDependentDraft> _familyMembers = [];
  bool _docs = false;
  bool _police = false;
  bool _submitting = false;
  String _proofType = 'Aadhaar (masked)';
  List<({PlatformFile file, String type})> _proofs = [];
  String _position = 'Joint Secretary';
  String _changeType = 'Resignation and replacement';
  final _outgoing = TextEditingController();
  String _mom = 'EC-2026-10 · Decision #3';
  final _for = TextEditingController(text: '7');
  final _against = TextEditingController(text: '1');
  final _abstain = TextEditingController(text: '0');

  @override
  void dispose() {
    for (final member in _familyMembers) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _pickProofs() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (files.isEmpty) return;
    if (!mounted) return;
    for (final file in files) {
      final size = await file.length();
      if (!mounted) return;
      if (size == null || size > maxSourceUploadBytes(file.extension ?? '')) {
        toast(context, 'File exceeds the supported source size');
        return;
      }
    }
    setState(() => _proofs = [..._proofs, for (final file in files) (file: file, type: _proofType)]);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final s = ref.read(sessionProvider)!;
    final role = s.activeRole;
    if (_newName.text.trim().isEmpty) {
      toast(context, 'Enter the incoming person\'s name');
      return;
    }
    if (_newName.text.trim().length > 120) {
      toast(context, 'Name must be 120 characters or fewer');
      return;
    }
    if (widget.type != MembershipRequestType.committee &&
        (!InputValidation.isEmail(_email.text) ||
          !InputValidation.isPhone(_mobile.text) ||
            _proofs.isEmpty)) {
      toast(context, 'Enter a valid email and phone number, and attach at least one ID proof');
      return;
    }
    if (widget.type == MembershipRequestType.resident) {
      final settings = ref.read(sessionProvider)!.user.association?.settings ?? const <String, dynamic>{};
      final minimumAgeSetting = settings['family_min_login_age'];
      final minimumAge = minimumAgeSetting is num ? minimumAgeSetting.toInt() : 12;
      final limitSetting = settings['family_member_limit'];
      final familyLimit = limitSetting is num ? limitSetting.toInt() : 5;
      if (!FamilyAccountRules.isWithinMemberLimit(_familyMembers.length, familyLimit)) {
        toast(context, 'This association allows at most $familyLimit family members');
        return;
      }
      for (final member in _familyMembers) {
        final birthDate = member.dateOfBirth;
        final email = member.email.text.trim();
        if (member.name.text.trim().isEmpty || birthDate == null) {
          toast(context, 'Enter a name and date of birth for every family member');
          return;
        }
        if (FamilyAccountRules.isLoginEligible(birthDate, minimumAge, DateUtils.dateOnly(DateTime.now())) &&
            !InputValidation.isEmail(email)) {
          toast(context, 'An eligible family member needs a unique email address for login');
          return;
        }
        if (email.isNotEmpty && !InputValidation.isEmail(email)) {
          toast(context, 'Enter a valid family-member email address');
          return;
        }
      }
    }
    if (widget.type == MembershipRequestType.committee &&
        [_for, _against, _abstain].any((controller) => !RegExp(r'^\d{1,6}$').hasMatch(controller.text.trim()))) {
      toast(context, 'Vote counts must be non-negative whole numbers');
      return;
    }
    final notifier = ref.read(approvalsProvider.notifier);
    final id = notifier.nextId();
    final directory = ref.read(directoryProvider);
    final selectedFlat = directory.flat(_flat);
    if (widget.type != MembershipRequestType.committee && selectedFlat == null) {
      toast(context, 'Choose a valid flat');
      return;
    }
    final flatOwner = directory.at(_flat, Role.owner).firstOrNull?.name ?? 'Owner not listed';
    final outgoingResident = directory.at(_flat, Role.resident).firstOrNull?.name;
    final pendingDues = ref.read(duesProvider).pendingFor(_flat);
    final ownerSelf = widget.type == MembershipRequestType.resident && role == Role.owner;
    late final ApprovalRequest req;
    switch (widget.type) {
      case MembershipRequestType.owner:
        const steps = [ApproverStep(role: Role.president, name: 'President · first review')];
        req = ApprovalRequest(
          id: id,
          code: 'W20',
          category: 'Membership',
          title: 'Owner change – $_flat: $flatOwner → ${_newName.text.trim()}',
          initiatorName: s.user.name,
          initiatorRole: role,
          createdAt: DateTime.now(),
          steps: steps,
          details: {
            'Flat': '${selectedFlat?.number ?? _flat} (${selectedFlat?.type ?? ''})',
            'Current owner': flatOwner,
            'New owner(s)': '${_newName.text.trim()} · ${_mobile.text.trim()}',
            'Sale deed': _deed.text.trim().isEmpty ? 'Not entered' : _deed.text.trim(),
            'Documents': _proofs.isNotEmpty ? '${_proofs.length} proof(s) attached' : 'Pending upload',
            'Payment gate': 'Dues are checked after the first President approval. Any balance holds the new occupant out of active records until paid and reapproved.',
          },
        );
      case MembershipRequestType.resident:
        req = ApprovalRequest(
          id: id,
          code: 'W21',
          category: 'Membership',
          title: 'Resident change – $_flat: ${outgoingResident ?? 'vacant'} → ${_newName.text.trim()}',
          initiatorName: s.user.name,
          initiatorRole: role,
          createdAt: DateTime.now(),
          steps: [
            if (!ownerSelf) ApproverStep(role: Role.owner, name: flatOwner),
            const ApproverStep(role: Role.president, name: 'President · first review'),
          ],
          details: {
            'Flat': '$_flat (owner: $flatOwner)',
            'Owner consent': ownerSelf ? 'Given – request raised by the owner' : 'Requested in the owner\'s app',
            'Outgoing resident': outgoingResident ?? 'None (vacant / owner-occupied)',
            'Incoming resident': '${_newName.text.trim()} + ${_familyMembers.length} family member(s)',
            'Lease': _lease.text.trim(),
            'ID proofs': _proofs.isNotEmpty ? '${_proofs.length} proof(s) attached' : 'Pending upload',
            'Police verification': _police ? 'Form submitted' : 'Pending',
            'Payment gate': 'After the first President approval, all flat dues are checked. Any balance keeps the new resident out of active gate-clearance records until paid and reapproved.',
          },
        );
      case MembershipRequestType.committee:
        final steps = _position == 'President'
            ? const [ApproverStep(role: Role.vicePresident, name: 'Vice President', onBehalfOf: 'President')]
            : const [ApproverStep(role: Role.president, name: 'Rajesh Menon')];
        req = ApprovalRequest(
          id: id,
          code: 'W22',
          category: 'Committee',
          title:
              'Committee change – $_position: ${_outgoing.text.trim().isEmpty ? 'vacancy' : _outgoing.text.trim()} → ${_newName.text.trim()}',
          initiatorName: s.user.name,
          initiatorRole: role,
          createdAt: DateTime.now(),
          momRequired: true,
          momRef: _mom,
          steps: steps,
          details: {
            'Position': _position,
            'Change type': _changeType,
            'Outgoing': _outgoing.text.trim().isEmpty ? '—' : _outgoing.text.trim(),
            'Incoming': _newName.text.trim(),
            'EC formal vote': '${_for.text} for · ${_against.text} against · ${_abstain.text} abstain',
            'GBM ratification': _position == 'EC member'
                ? 'Not required'
                : 'Required at next General Body (office bearer)',
          },
        );
    }
    setState(() => _submitting = true);
    try {
      final requestId = await notifier.add(req);
      if (backendEnabled && widget.type != MembershipRequestType.committee) {
        final f = selectedFlat!;
        await ref.read(directoryProvider.notifier).createMembershipChange(
          requestId: requestId!,
          flat: f,
          type: widget.type == MembershipRequestType.owner ? 'owner' : 'resident',
          name: _newName.text.trim(),
          email: _email.text.trim(),
          mobile: _mobile.text.trim(),
          leasePeriod: _lease.text.trim(),
          familyMembers: [
            for (final member in _familyMembers)
              (
                name: member.name.text.trim(),
                dateOfBirth: member.dateOfBirth!,
                email: member.email.text.trim().isEmpty ? null : member.email.text.trim(),
              ),
          ],
        );
        for (final proof in _proofs) {
          final bytes = await proof.file.xFile.readAsBytes();
          await ref.read(directoryProvider.notifier).uploadMembershipProof(
            requestId: requestId,
            name: _newName.text.trim(),
            email: _email.text.trim(),
            flatId: f.id!,
            type: proof.type,
            bytes: bytes,
            ext: proof.file.extension ?? '',
          );
        }
      }
      if (!mounted) return;
      toast(context, '$id submitted. Approvers notified.');
      context.go('/approvals/$id');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider)!;
    final t = widget.type;
    final ownerSelf = t == MembershipRequestType.resident && s.activeRole == Role.owner;
    final canSelfRequest = (t == MembershipRequestType.owner && s.activeRole == Role.owner) ||
      (t == MembershipRequestType.resident && (s.activeRole == Role.owner || s.activeRole == Role.resident));
    final settings = s.user.association?.settings ?? const <String, dynamic>{};
    final minimumAgeSetting = settings['family_min_login_age'];
    final minimumLoginAge = minimumAgeSetting is num ? minimumAgeSetting.toInt() : 12;
    final limitSetting = settings['family_member_limit'];
    final familyLimit = limitSetting is num ? limitSetting.toInt() : 5;
    final directory = ref.watch(directoryProvider);
    if (directory.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.label)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (directory.error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.label)),
        body: PageBody(children: [EmptyState(directory.error!, icon: Icons.error_outline)]),
      );
    }
    final ownFlats = directory.flats.where((f) => directory.myFlatNumbers.contains(f.number)).toList();
    if (ownerSelf && ownFlats.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t.label)),
        body: const EmptyState(
          'You have no rented or vacant flat to change the resident for.',
          icon: Icons.home_outlined,
        ),
      );
    }
    if (!s.user.canInitiateMembership(s.activeRole) && !canSelfRequest) {
      return Scaffold(
        appBar: AppBar(title: Text(t.label)),
        body: const EmptyState(
          'Only the President, Secretary or a designated EC member (Membership desk) can start this request.',
          icon: Icons.lock_outline,
        ),
      );
    }
    final pendingDues = ref.watch(duesProvider).pendingFor(_flat);
    final flats = canSelfRequest
      ? ownFlats
        : t == MembershipRequestType.resident
      ? directory.flats.where((f) => f.occupancy != Occupancy.ownerOccupied).toList()
      : directory.flats;
    if (t != MembershipRequestType.committee && flats.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t.label)),
        body: const PageBody(
          children: [EmptyState('Add a flat before creating a membership change.', icon: Icons.home_outlined)],
        ),
      );
    }
    if (flats.isNotEmpty && !flats.any((f) => f.number == _flat)) _flat = flats.first.number;
    final flatOwner = directory.at(_flat, Role.owner).firstOrNull?.name ?? 'Owner not listed';
    final outgoingResident = directory.at(_flat, Role.resident).firstOrNull?.name;

    final flatPicker = DropdownButtonFormField<String>(
      initialValue: _flat,
      decoration: const InputDecoration(labelText: 'Flat'),
      items: [
        for (final f in flats)
          DropdownMenuItem(
            value: f.number,
            child: Text('${f.number} · ${f.type} · ${f.occupancy.name}'),
          ),
      ],
      onChanged: (v) => setState(() => _flat = v!),
    );

    final approvalsText = switch (t) {
      MembershipRequestType.owner => 'First: President review. After this, outstanding flat dues are checked; once paid, Secretary and President approve again before the new owner is activated.',
      MembershipRequestType.resident =>
        ownerSelf
            ? 'First: President review. After this, dues are checked; any balance pauses activation. Once paid, Secretary and President approve again before the new resident is activated.'
            : 'First: flat-owner consent, then President review. After this, dues are checked; once paid, Secretary and President approve again before the new resident is activated.',
      MembershipRequestType.committee => 'Approvals: formal EC vote recorded in the MOM, then President (VP if the President is being changed). Office bearer changes need General Body ratification if bylaws require.',
    };

    return Scaffold(
      appBar: AppBar(title: Text(t.label)),
      body: PageBody(
        maxWidth: 720,
        children: [
          Card(
            color: Colors.indigo.withValues(alpha: 0.05),
            child: ListTile(
              leading: const Icon(Icons.route_outlined, color: Colors.indigo),
              title: Text(t.hint),
              subtitle: Text(approvalsText),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (t != MembershipRequestType.committee) ...[flatPicker, const SizedBox(height: 12)],
                  if (t == MembershipRequestType.owner) ...[
                    _info('Current owner', flatOwner),
                    if (pendingDues > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Pill(
                          'Pending dues ${inr.format(pendingDues)} – must be cleared before final approval',
                          color: AppColors.red,
                          icon: Icons.warning_amber,
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Pill('All dues cleared', color: AppColors.green, icon: Icons.check),
                      ),
                    TextField(
                      controller: _newName,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'New owner name(s) *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'New owner email *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+() -]'))],
                      decoration: const InputDecoration(labelText: 'New owner phone *', prefixText: '+91 '),
                    ),
                    TextField(
                      controller: _deed,
                      decoration: const InputDecoration(labelText: 'Sale deed / registration number'),
                    ),
                  ],
                  if (t == MembershipRequestType.resident) ...[
                    _info(ownerSelf ? 'Owner' : 'Owner (will be asked to consent)', flatOwner),
                    _info('Outgoing resident', outgoingResident ?? 'None'),
                    TextField(
                      controller: _newName,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Incoming resident name *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Incoming resident email *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+() -]'))],
                      decoration: const InputDecoration(labelText: 'Incoming resident phone *', prefixText: '+91 '),
                    ),
                    TextField(
                      controller: _lease,
                      decoration: const InputDecoration(labelText: 'Lease period'),
                    ),
                    const SizedBox(height: 12),
                    if (canSelfRequest) ...[
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context).familyDobPrivacyNotice),
                      const SizedBox(height: 8),
                      for (var index = 0; index < _familyMembers.length; index++)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text('Family member ${index + 1}', style: Theme.of(context).textTheme.titleSmall)),
                                    IconButton(
                                      tooltip: 'Remove family member',
                                      onPressed: _submitting ? null : () => setState(() {
                                        _familyMembers.removeAt(index).dispose();
                                      }),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                TextField(
                                  controller: _familyMembers[index].name,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: const InputDecoration(labelText: 'Family member name *'),
                                ),
                                TextButton.icon(
                                  onPressed: _submitting ? null : () async {
                                    final selected = await showDatePicker(
                                      context: context,
                                      initialDate: _familyMembers[index].dateOfBirth ?? DateTime.now().subtract(const Duration(days: 365 * 10)),
                                      firstDate: DateTime(1900),
                                      lastDate: DateUtils.dateOnly(DateTime.now()),
                                    );
                                    if (selected != null && mounted) {
                                      setState(() => _familyMembers[index].dateOfBirth = selected);
                                    }
                                  },
                                  icon: const Icon(Icons.cake_outlined),
                                  label: Text(_familyMembers[index].dateOfBirth == null
                                      ? 'Date of birth *'
                                      : 'Date of birth · ${dateFmt.format(_familyMembers[index].dateOfBirth!)}'),
                                ),
                                TextField(
                                  controller: _familyMembers[index].email,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: 'Login email (required from age $minimumLoginAge)',
                                    helperText: 'An owner or resident can add the email when this member is eligible.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _submitting || _familyMembers.length >= familyLimit
                              ? null
                              : () => setState(() => _familyMembers.add(_FamilyDependentDraft())),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: Text('Add family member (${_familyMembers.length}/$familyLimit)'),
                        ),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _police,
                      onChanged: (v) => setState(() => _police = v!),
                      title: const Text('Police verification form submitted'),
                    ),
                  ],
                  if (t == MembershipRequestType.committee) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _position,
                      decoration: const InputDecoration(labelText: 'Position'),
                      items: [
                        for (final p in const [
                          'President',
                          'Secretary',
                          'Treasurer',
                          'Vice President',
                          'Joint Secretary',
                          'Joint Treasurer',
                          'EC member',
                        ])
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => setState(() => _position = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _changeType,
                      decoration: const InputDecoration(labelText: 'Change type'),
                      items: [
                        for (final p in const [
                          'Resignation and replacement',
                          'Co-option to vacancy',
                          'Removal (as per bylaws)',
                          'Role swap within EC',
                        ])
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => setState(() => _changeType = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _outgoing,
                      decoration: const InputDecoration(labelText: 'Outgoing member (if any)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newName,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Incoming member *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _mom,
                      decoration: const InputDecoration(labelText: 'Linked MOM decision (mandatory)'),
                      items: [
                        for (final m in const ['EC-2026-10 · Decision #3', 'EC-2026-09 · Decision #5'])
                          DropdownMenuItem(value: m, child: Text(m)),
                      ],
                      onChanged: (v) => setState(() => _mom = v!),
                    ),
                    const SizedBox(height: 12),
                    const Text('EC formal vote'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _for,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            decoration: const InputDecoration(labelText: 'For'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _against,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            decoration: const InputDecoration(labelText: 'Against'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _abstain,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            decoration: const InputDecoration(labelText: 'Abstain'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (t != MembershipRequestType.committee) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _proofType,
                      decoration: const InputDecoration(labelText: 'ID proof type'),
                      items: [for (final type in idDocTypes) DropdownMenuItem(value: type, child: Text(type))],
                      onChanged: (value) => setState(() => _proofType = value ?? _proofType),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickProofs,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Attach ID proof (max 5 MB each)'),
                    ),
                    for (var i = 0; i < _proofs.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(_proofs[i].file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_proofs[i].type),
                        trailing: IconButton(
                          tooltip: 'Remove file',
                          onPressed: _submitting ? null : () => setState(() => _proofs.removeAt(i)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                  ] else
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _docs,
                      onChanged: (v) => setState(() => _docs = v!),
                      title: const Text('Resignation letter / consent uploaded'),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: const Icon(Icons.send),
                    label: const Padding(padding: EdgeInsets.all(12), child: Text('Submit for approval')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 200,
          child: Text(k, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}
