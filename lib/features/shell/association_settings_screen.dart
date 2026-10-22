import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../backend/association_settings_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class AssociationSettingsScreen extends ConsumerStatefulWidget {
  const AssociationSettingsScreen({super.key});

  @override
  ConsumerState<AssociationSettingsScreen> createState() => _AssociationSettingsScreenState();
}

class _AssociationSettingsScreenState extends ConsumerState<AssociationSettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _state;
  late final TextEditingController _city;
  late final TextEditingController _brand;
  late final TextEditingController _fiscalMonth;
  late final TextEditingController _dueDay;
  late final TextEditingController _familyMinimumAge;
  late final TextEditingController _familyMemberLimit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final association = ref.read(sessionProvider)?.user.association;
    final settings = association?.settings ?? const <String, dynamic>{};
    _name = TextEditingController(text: association?.name ?? '');
    _state = TextEditingController(text: association?.state ?? '');
    _city = TextEditingController(text: association?.city ?? '');
    _brand = TextEditingController(text: settings['brand_primary'] as String? ?? '#26746A');
    _fiscalMonth = TextEditingController(text: '${settings['fiscal_year_start_month'] ?? 4}');
    _dueDay = TextEditingController(text: '${settings['default_due_day'] ?? 10}');
    _familyMinimumAge = TextEditingController(text: '${settings['family_min_login_age'] ?? 12}');
    _familyMemberLimit = TextEditingController(text: '${settings['family_member_limit'] ?? 5}');
  }

  @override
  void dispose() {
    _name.dispose();
    _state.dispose();
    _city.dispose();
    _brand.dispose();
    _fiscalMonth.dispose();
    _dueDay.dispose();
    _familyMinimumAge.dispose();
    _familyMemberLimit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final state = _state.text.trim();
    final brand = _brand.text.trim();
    final fiscalMonth = int.tryParse(_fiscalMonth.text.trim());
    final dueDay = int.tryParse(_dueDay.text.trim());
    final minimumLoginAge = int.tryParse(_familyMinimumAge.text.trim());
    final familyMemberLimit = int.tryParse(_familyMemberLimit.text.trim());
    if (name.isEmpty || state.isEmpty || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(brand) ||
      fiscalMonth == null || fiscalMonth < 1 || fiscalMonth > 12 || dueDay == null || dueDay < 1 || dueDay > 28 ||
      minimumLoginAge == null || minimumLoginAge < 1 || minimumLoginAge > 21 ||
      familyMemberLimit == null || familyMemberLimit < 0 || familyMemberLimit > 30) {
      toast(context, 'Check the required fields and their ranges');
      return;
    }
    final associationId = ref.read(sessionProvider)?.user.associationId;
    if (associationId == null) return;
    setState(() => _saving = true);
    try {
      await AssociationSettingsRepo.update(
        name: name,
        state: state,
        city: _city.text,
        brandPrimary: brand,
        fiscalYearStartMonth: fiscalMonth,
        defaultDueDay: dueDay,
      );
      await AssociationSettingsRepo.updateFamilyRules(
        minimumLoginAge: minimumLoginAge,
        memberLimit: familyMemberLimit,
      );
      await ref.read(sessionProvider.notifier).switchAssociation(associationId);
      if (mounted) toast(context, AppLocalizations.of(context).settingsSaved);
    } catch (error) {
      if (mounted) toast(context, '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createAssociation() async {
    final name = TextEditingController();
    final state = TextEditingController(text: _state.text);
    final city = TextEditingController(text: _city.text);
    final brand = TextEditingController(text: _brand.text);
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create association'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Association name *')),
              TextField(controller: state, decoration: const InputDecoration(labelText: 'State *')),
              TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
              TextField(controller: brand, decoration: const InputDecoration(labelText: 'Brand color *', helperText: '#RRGGBB')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
        ],
      ),
    );
    if (created != true || !mounted) {
      name.dispose();
      state.dispose();
      city.dispose();
      brand.dispose();
      return;
    }
    try {
      final associationId = await AssociationSettingsRepo.createAssociation(
        name: name.text,
        state: state.text,
        city: city.text,
        brandPrimary: brand.text,
      );
      await ref.read(sessionProvider.notifier).switchAssociation(associationId);
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) toast(context, '$error');
    } finally {
      name.dispose();
      state.dispose();
      city.dispose();
      brand.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final role = ref.watch(sessionProvider)?.activeRole;
    if (role != Role.admin) {
      return PageBody(children: [EmptyState(l.adminRequired, icon: Icons.lock_outline)]);
    }
    return PageBody(
      maxWidth: 760,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.associationSettings, style: Theme.of(context).textTheme.headlineSmall)),
            IconButton.filledTonal(
              tooltip: 'Save settings',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _createAssociation,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Create association'),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l.associationIdentity,
          child: Column(
            children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: '${l.associationName} *')),
              TextField(controller: _state, decoration: InputDecoration(labelText: '${l.state} *')),
              TextField(controller: _city, decoration: InputDecoration(labelText: l.city)),
              TextField(
                controller: _brand,
                textCapitalization: TextCapitalization.none,
                inputFormatters: [LengthLimitingTextInputFormatter(7)],
                decoration: InputDecoration(
                  labelText: '${l.brandColor} *',
                  prefixIcon: const Icon(Icons.palette_outlined),
                  helperText: 'Hex color, e.g. #26746A',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l.operatingDefaults,
          child: Column(
            children: [
              TextField(
                controller: _fiscalMonth,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                decoration: InputDecoration(labelText: '${l.fiscalYearStartMonth} *', helperText: '1 = January, 4 = April'),
              ),
              TextField(
                controller: _dueDay,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                decoration: InputDecoration(labelText: '${l.defaultDueDay} *', helperText: 'Choose 1 to 28'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Family account rules',
          child: Column(
            children: [
              TextField(
                controller: _familyMinimumAge,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                decoration: const InputDecoration(
                  labelText: 'Minimum age for an individual login',
                  helperText: 'Age on the birthday; choose 1 to 21',
                ),
              ),
              TextField(
                controller: _familyMemberLimit,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                decoration: const InputDecoration(
                  labelText: 'Maximum additional family members',
                  helperText: 'Counts all dependents, including those below login age; choose 0 to 30',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l.subscription,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text(l.billingProviderNotConfigured),
            subtitle: Text(l.billingProviderDescription),
          ),
        ),
      ],
    );
  }
}
