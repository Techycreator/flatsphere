import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../security/device_lock.dart';
import '../../state/app_state.dart';

class DeviceLockScreen extends ConsumerStatefulWidget {
  const DeviceLockScreen({super.key, required this.setup});

  final bool setup;

  @override
  ConsumerState<DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends ConsumerState<DeviceLockScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _enableBio = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final available = await DeviceLock.biometricAvailable();
    final enabled = !widget.setup && available && await DeviceLock.biometricEnabled();
    if (!mounted) return;
    setState(() {
      _bioAvailable = available;
      _bioEnabled = enabled;
    });
    if (enabled) _unlockWithBiometric();
  }

  Future<void> _unlockWithBiometric() async {
    if (await DeviceLock.authenticateBiometric('Unlock FlatSphere') && mounted) {
      ref.read(lockProvider.notifier).unlock();
    }
  }

  Future<void> _save() async {
    final pin = _pin.text;
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return setState(() => _error = 'Enter a 6-digit PIN');
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) return setState(() => _error = 'Choose a less obvious PIN');
    if (pin != _confirm.text) return setState(() => _error = 'PINs do not match');
    setState(() {
      _busy = true;
      _error = null;
    });
    await DeviceLock.setPin(pin, ref.read(sessionProvider)!.user.id);
    final bio = _enableBio && await DeviceLock.enrollBiometric(ref.read(sessionProvider)!.user.name);
    await DeviceLock.setBiometricEnabled(bio);
    if (!mounted) return;
    ref.read(lockProvider.notifier).unlock();
    context.go('/home');
  }

  Future<void> _skip() async {
    await DeviceLock.skip(ref.read(sessionProvider)!.user.id);
    if (!mounted) return;
    ref.read(lockProvider.notifier).unlock();
    context.go('/home');
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final left = await DeviceLock.verifyPin(_pin.text);
    if (!mounted) return;
    if (left < 0) return ref.read(lockProvider.notifier).unlock();
    if (left == 0) {
      await DeviceLock.clear();
      return ref.read(sessionProvider.notifier).logout();
    }
    setState(() {
      _busy = false;
      _error = 'Wrong PIN. $left attempt${left == 1 ? '' : 's'} left.';
      _pin.clear();
    });
  }

  Widget _pinField(TextEditingController c, String label, {VoidCallback? onDone}) => TextField(
    controller: c,
    obscureText: true,
    maxLength: 6,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, counterText: ''),
    onSubmitted: onDone == null ? null : (_) => onDone(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.setup ? 'Set a 6-digit PIN' : 'Enter your PIN',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.setup
                          ? 'This PIN unlocks FlatSphere on this device only. It is never sent to our servers.'
                          : 'Unlock FlatSphere on this device.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _pinField(_pin, widget.setup ? 'New PIN' : 'PIN', onDone: widget.setup ? null : _unlock),
                    if (widget.setup) ...[
                      const SizedBox(height: 12),
                      _pinField(_confirm, 'Confirm PIN', onDone: _save),
                      if (_bioAvailable)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enableBio,
                          onChanged: (v) => setState(() => _enableBio = v),
                          title: const Text('Unlock with fingerprint / face'),
                          subtitle: const Text('Stored in this phone only, not in the app or database.'),
                        ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : (widget.setup ? _save : _unlock),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(widget.setup ? 'Save PIN' : 'Unlock'),
                      ),
                    ),
                    if (widget.setup)
                      TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip for now')),
                    if (_bioEnabled)
                      TextButton.icon(
                        onPressed: _busy ? null : _unlockWithBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use fingerprint / face'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (!widget.setup) await DeviceLock.clear();
                              ref.read(sessionProvider.notifier).logout();
                            },
                      child: Text(widget.setup ? 'Sign out' : 'Forgot PIN? Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
