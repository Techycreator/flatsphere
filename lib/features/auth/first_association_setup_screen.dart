import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/association_settings_repo.dart';
import '../../backend/backend.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class FirstAssociationSetupScreen extends ConsumerStatefulWidget {
  const FirstAssociationSetupScreen({super.key});

  @override
  ConsumerState<FirstAssociationSetupScreen> createState() => _FirstAssociationSetupScreenState();
}

class _FirstAssociationSetupScreenState extends ConsumerState<FirstAssociationSetupScreen> {
  final _adminName = TextEditingController();
  final _associationName = TextEditingController();
  final _state = TextEditingController();
  final _city = TextEditingController();
  final _brand = TextEditingController(text: '#26746A');
  bool _creating = false;

  @override
  void dispose() {
    _adminName.dispose();
    _associationName.dispose();
    _state.dispose();
    _city.dispose();
    _brand.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    final email = ref.read(firstAssociationSignupProvider);
    final brand = _brand.text.trim();
    if (email == null) {
      context.go('/login');
      return;
    }
    if (_adminName.text.trim().isEmpty ||
        _associationName.text.trim().isEmpty ||
        _state.text.trim().isEmpty ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(brand)) {
      toast(context, 'Enter your name, association name, state, and a valid #RRGGBB brand color.');
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await AssociationSettingsRepo.createFirstAssociation(
        name: _associationName.text,
        state: _state.text,
        city: _city.text,
        brandPrimary: brand,
        adminName: _adminName.text,
      );
      final user = await AuthService.loadUser(associationId: id);
      if (user == null) throw StateError('The new association membership could not be loaded.');
      ref.read(sessionProvider.notifier).login(user);
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final email = ref.watch(firstAssociationSignupProvider);
    if (email == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: Text(l.createAssociation)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.firstAssociationSetup, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('$email · ${l.verifiedEmailNoAssociation}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _adminName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: '${l.adminName} *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _associationName,
                  decoration: InputDecoration(labelText: '${l.associationName} *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _state,
                  decoration: InputDecoration(labelText: '${l.state} *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _city,
                  decoration: InputDecoration(labelText: l.city),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _brand,
                  inputFormatters: [LengthLimitingTextInputFormatter(7)],
                  decoration: InputDecoration(labelText: '${l.brandColor} *', helperText: '#RRGGBB'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _creating ? null : _create,
                  icon: _creating
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_business_outlined),
                  label: Text(l.createAssociation),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
