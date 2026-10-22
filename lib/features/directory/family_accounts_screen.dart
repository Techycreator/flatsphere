import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/directory_repo.dart' show DirectoryRepo, friendlyError;
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

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

  int _age(DateTime date) {
    final now = DateTime.now();
    var years = now.year - date.year;
    if (now.month < date.month || (now.month == date.month && now.day < date.day)) years--;
    return years;
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
    try {
      await DirectoryRepo.updateFamilyMemberEmail(member.id, email);
      await _load();
      if (mounted) toast(context, 'Email saved. ${member.name} can sign in with email OTP.');
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
                        : _age(member.dateOfBirth) < minimumAge
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
