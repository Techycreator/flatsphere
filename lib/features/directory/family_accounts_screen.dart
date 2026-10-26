import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend.dart' show backendEnabled;
import '../../backend/attendance_repo.dart';
import '../../backend/directory_repo.dart' show DirectoryRepo, friendlyError;
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../validation/input_validation.dart';

class FamilyAccountsScreen extends ConsumerStatefulWidget {
  const FamilyAccountsScreen({super.key});

  @override
  ConsumerState<FamilyAccountsScreen> createState() => _FamilyAccountsScreenState();
}

class _FamilyAccountsScreenState extends ConsumerState<FamilyAccountsScreen> {
  List<FamilyMemberRecord> _members = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!backendEnabled) {
      setState(() {
        _members = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await DirectoryRepo.familyMembers();
      if (mounted) setState(() => _members = members);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addEmail(FamilyMemberRecord member) async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add login email for ${member.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email address', hintText: 'name@example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !mounted) return;
    if (!InputValidation.isEmail(email)) {
      toast(context, 'Enter a valid email address');
      return;
    }
    try {
      await DirectoryRepo.updateFamilyMemberEmail(member.id, email);
      await _load();
      if (mounted) toast(context, 'Email saved. ${member.name} can sign in with email OTP.');
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    }
  }

  Future<void> _addMember() async {
    final flats = await AttendanceRepo.myResidentialFlats();
    if (!mounted) return;
    if (flats.isEmpty) return toast(context, 'No active owner/resident flat is linked to this account.');
    final name = TextEditingController();
    var flat = flats.first;
    DateTime? dob;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add family member'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (flats.length > 1) ...[
                  DropdownButtonFormField<(String, String)>(
                    initialValue: flat,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Flat'),
                    items: [for (final f in flats) DropdownMenuItem(value: f, child: Text(f.$2))],
                    onChanged: (v) => set(() => flat = v ?? flat),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name *')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: dob ?? DateTime.now().subtract(const Duration(days: 365 * 10)),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) set(() => dob = d);
                  },
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(dob == null ? 'Date of birth *' : 'Date of birth · ${dateFmt.format(dob!)}'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The Secretary must approve this request. After approval you can add a login email for members who meet the age rule.',
                  style: TextStyle(fontSize: 12),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || dob == null) return set(() => err = 'Enter a name and date of birth');
                Navigator.pop(ctx, true);
              },
              child: const Text('Submit for approval'),
            ),
          ],
        ),
      ),
    );
    final memberName = name.text.trim();
    name.dispose();
    if (ok != true || dob == null || !mounted) return;
    try {
      await DirectoryRepo.requestFamilyMemberAddition(flatId: flat.$1, name: memberName, dateOfBirth: dob!);
      await _load();
      if (mounted) toast(context, 'Request sent to the Secretary for approval.');
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final role = session?.activeRole;
    if (role != Role.owner && role != Role.resident) {
      return const PageBody(children: [EmptyState('Only owners and residents can view family DOBs.', icon: Icons.lock_outline)]);
    }
    final setting = session?.user.association?.settings['family_min_login_age'];
    final minimumAge = setting is num ? setting.toInt() : 12;
    final l = AppLocalizations.of(context);

    return PageBody(
      maxWidth: 900,
      children: [
        Row(
          children: [
            Expanded(child: Text('Family accounts', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: backendEnabled ? _addMember : null,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add family member'),
            ),
            IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          ],
        ),
        Text(l.familyDobPrivacyNotice),
        const SizedBox(height: 12),
        if (_loading) const Center(child: CircularProgressIndicator())
        else if (_error != null) EmptyState(_error!, icon: Icons.error_outline)
        else if (_members.isEmpty) const EmptyState('No family members are recorded for your flat yet.', icon: Icons.people_outline)
        else
          SectionCard(
            title: '${_members.length} family member${_members.length == 1 ? '' : 's'}',
            padding: false,
            child: Column(
              children: [
                for (final member in _members)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(member.name),
                    subtitle: Text(
                      '${member.flatNumber} · DOB ${dateFmt.format(member.dateOfBirth)} · '
                      '${member.approved ? 'Approved' : 'Pending approval'}',
                    ),
                    trailing: !member.approved
                        ? const Text('Pending')
                        : !FamilyAccountRules.isLoginEligible(member.dateOfBirth, minimumAge, DateUtils.dateOnly(DateTime.now()))
                        ? Text('Login at age $minimumAge')
                        : member.email != null
                        ? const Icon(Icons.mark_email_read_outlined)
                        : IconButton(
                            tooltip: 'Add login email',
                            onPressed: () => _addEmail(member),
                            icon: const Icon(Icons.alternate_email),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
