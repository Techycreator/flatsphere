import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend.dart';
import '../../backend/devices_repo.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../backend/pin_vault.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final _devicesProvider = FutureProvider.autoDispose((ref) => DevicesRepo.list());

/// Quick unlock with a 6-digit PIN on this device, and the list of trusted devices.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) toast(context, error is PinVaultException ? error.message : friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPin() async {
    final pin = await _askPin('Choose a 6-digit PIN');
    if (pin == null || !mounted) return;
    final again = await _askPin('Enter the PIN again');
    if (again == null || !mounted) return;
    if (again != pin) return toast(context, 'The PINs did not match');
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin) || '0123456789'.contains(pin) || '9876543210'.contains(pin)) {
      return toast(context, 'Choose a less obvious PIN');
    }
    await _guard(() async {
      final session = db.auth.currentSession;
      if (session == null) throw const PinVaultException('Log in again with an email code first.');
      final label = '${kIsWeb ? 'Browser' : defaultTargetPlatform.name} · added ${dateFmt.format(DateTime.now())}';
      final id = await DevicesRepo.register(label, 'pin');
      await PinVault.enablePin(pin, jsonEncode(session.toJson()), id);
      ref.invalidate(_devicesProvider);
      if (mounted) toast(context, 'PIN set. Next time, unlock with your PIN on this device.');
    });
  }

  Future<void> _removePin() => _guard(() async {
    final id = PinVault.deviceId;
    final session = db.auth.currentSession;
    await PinVault.disablePin(session == null ? null : jsonEncode(session.toJson()));
    if (id != null) await DevicesRepo.revoke(id);
    ref.invalidate(_devicesProvider);
  });

  Future<String?> _askPin(String title) async {
    final c = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.length == 6 ? c.text : null),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    c.dispose();
    return pin;
  }

  Future<void> _revokeMember() async {
    final email = await promptText(context, title: 'Remove a member\'s devices (lost phone)', hint: 'member@email.com');
    if (email == null) return;
    await _guard(() async {
      final n = await DevicesRepo.revokeMember(email);
      if (mounted) toast(context, 'Removed $n device(s). They must log in with an email code.');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!backendEnabled) return const PageBody(children: [EmptyState('Available in the cloud version.')]);
    final role = ref.watch(sessionProvider)?.activeRole;
    final devices = ref.watch(_devicesProvider);
    return PageBody(
      maxWidth: 720,
      children: [
        Text('Security', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(PinVault.pinEnabled ? 'PIN unlock is on for this device' : 'Unlock with a 6-digit PIN'),
            subtitle: const Text(
              'Works only on this device after an email-code login. Your PIN is never stored or sent; it encrypts '
              'your saved login. 5 wrong tries sign this device out.',
            ),
            trailing: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : PinVault.pinEnabled
                ? TextButton(onPressed: _removePin, child: const Text('Turn off'))
                : FilledButton(onPressed: _setPin, child: const Text('Set PIN')),
          ),
        ),
        const SizedBox(height: 16),
        Text('Trusted devices', style: Theme.of(context).textTheme.titleMedium),
        if (devices.isLoading) const LinearProgressIndicator(),
        if (devices.hasError) Text(friendlyError(devices.error!)),
        if (devices.hasValue && devices.value!.isEmpty) const Text('No devices use quick unlock.'),
        if (devices.hasValue)
          for (final d in devices.value!)
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text('${d.label}${d.id == PinVault.deviceId ? ' (this device)' : ''}'),
              subtitle: Text('${d.method.toUpperCase()} · last used ${dateTimeFmt.format(d.lastUsed)}'),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _guard(() async {
                  if (d.id == PinVault.deviceId) await PinVault.clearPin();
                  await DevicesRepo.revoke(d.id);
                  ref.invalidate(_devicesProvider);
                }),
              ),
            ),
        if (const {Role.admin, Role.president, Role.secretary}.contains(role)) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _revokeMember,
            icon: const Icon(Icons.phonelink_erase_outlined),
            label: const Text('Remove a member\'s devices (lost phone)'),
          ),
        ],
      ],
    );
  }
}
