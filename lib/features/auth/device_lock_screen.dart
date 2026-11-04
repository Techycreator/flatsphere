import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;

import '../../widgets/tr_text.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../security/device_lock.dart';
import '../../state/app_state.dart';

/// Fingerprint / face unlock only; there is no app PIN. Anyone who cannot unlock can sign out and sign in again with
/// the email code.
class DeviceLockScreen extends ConsumerStatefulWidget {
  const DeviceLockScreen({super.key, required this.setup});

  final bool setup;

  @override
  ConsumerState<DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends ConsumerState<DeviceLockScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.setup) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await DeviceLock.authenticateBiometric('Unlock FlatSphere');
    if (!mounted) return;
    if (ok) return ref.read(lockProvider.notifier).unlock();
    setState(() {
      _busy = false;
      _error = 'Not recognised. Try again, or sign out and sign in with the email code.';
    });
  }

  Future<void> _turnOn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final user = ref.read(sessionProvider)!.user;
    if (!await DeviceLock.enrollBiometric(user.name)) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not turn on fingerprint / face. Try again.';
        });
      }
      return;
    }
    await DeviceLock.enableBiometric(user.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final big = const EdgeInsets.all(14);
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
                    Icon(Icons.fingerprint, size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      widget.setup ? 'Unlock with fingerprint / face?' : 'Unlock FlatSphere',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.setup
                          ? 'FlatSphere will ask for your fingerprint or face each time it opens on this device. '
                                'It is checked by this device only and never sent to our servers.'
                          : 'Use your fingerprint or face to continue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : (widget.setup ? _turnOn : _unlock),
                      icon: const Icon(Icons.fingerprint),
                      label: Padding(padding: big, child: Text(widget.setup ? 'Turn on' : 'Unlock')),
                    ),
                    if (widget.setup) TextButton(onPressed: _busy ? null : _skip, child: const Text('Not now')),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              ref.read(sessionProvider.notifier).logout();
                            },
                      child: const Text('Sign out'),
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
