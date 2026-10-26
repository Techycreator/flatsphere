import 'package:flutter/material.dart' hide Text;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
import '../../validation/input_validation.dart';
import '../shell/app_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _mobile = TextEditingController();
  final _otp = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      final msg = e.toString();
      setState(
        () => _error = msg.contains('not_invited') || msg.contains('Database error saving new user')
            ? 'This email is not registered with any association. Ask your Secretary for an invite.'
            : msg.contains('expired') || msg.contains('invalid')
            ? 'Code is wrong or expired. Request a new one.'
            : msg.contains('security purposes') || msg.contains('rate limit')
            ? 'Please wait a minute before requesting another code.'
            : 'Could not complete login. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() {
    if (!InputValidation.isEmail(_mobile.text)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    _run(() async {
      await AuthService.sendCode(_mobile.text);
      setState(() => _otpSent = true);
    });
  }

  void _resend() => _run(() async {
    await AuthService.sendCode(_mobile.text);
    setState(() {
      _otp.clear();
      _info = 'New code sent. Any earlier code no longer works.';
    });
  });

  void _verifyEmail() {
    if (!RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code from the email');
      return;
    }
    _run(() async {
      await AuthService.verifyCode(_mobile.text, _otp.text);
      final user = await AuthService.loadUser();
      if (user == null) {
        final email = AuthService.currentUserEmail;
        if (email == null) throw Exception('verified_email_missing');
        ref.read(firstAssociationSignupProvider.notifier).setEmail(email);
        if (mounted) context.go('/setup-association');
        return;
      }
      ref.read(sessionProvider.notifier).login(user);
    });
  }

  void _verify() {
    final digits = _mobile.text.replaceAll(RegExp(r'\D'), '');
    final user = demoUsers.where((u) => u.mobile.replaceAll(' ', '') == digits).firstOrNull;
    if (_otp.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP (demo: any 6 digits)');
      return;
    }
    if (user == null) {
      setState(() => _error = 'Mobile number not registered. Pick a demo user below.');
      return;
    }
    ref.read(sessionProvider.notifier).login(user);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final theme = Theme.of(context);

    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.login, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const LanguageToggle(),
              ],
            ),
            const SizedBox(height: 4),
            Text(backendEnabled ? 'Sign in to your association' : associationName, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            TextField(
              controller: _mobile,
              keyboardType: backendEnabled ? TextInputType.emailAddress : TextInputType.phone,
              enabled: !_otpSent,
              decoration: backendEnabled
                  ? const InputDecoration(labelText: 'Email')
                  : InputDecoration(labelText: l.mobileNumber, prefixText: '+91 '),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(labelText: l.enterOtp, counterText: ''),
                onSubmitted: (_) => backendEnabled ? _verifyEmail() : _verify(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_otpSent && backendEnabled && _error == null) ...[
              const SizedBox(height: 8),
              Text(_info ?? 'The code is valid for 10 minutes.', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : backendEnabled
                  ? (_otpSent ? _verifyEmail : _sendCode)
                  : () => _otpSent ? _verify() : setState(() => _otpSent = true),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_otpSent ? l.verify : l.sendOtp)),
            ),
            if (backendEnabled && _otpSent)
              TextButton(
                onPressed: _busy ? null : _resend,
                child: const Text('Resend code'),
              ),
            if (backendEnabled && _otpSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _otpSent = false;
                        _otp.clear();
                      }),
                child: const Text('Use a different email'),
              ),
            if (!backendEnabled) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(l.demoPersonas, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final u in demoUsers) _PersonaTile(user: u),
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      body: Row(
        children: [
          if (wide) const Expanded(child: _BrandPanel()),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: form),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonaTile extends ConsumerWidget {
  const _PersonaTile({required this.user});
  final DemoUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = user.name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(initials)),
      title: Text(user.name),
      subtitle: Text([user.roles.map((r) => r.label).join(' · '), ?user.flatNumber].join('  ·  ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => ref.read(sessionProvider.notifier).login(user),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.apartment, color: Colors.white, size: 56),
          const SizedBox(height: 16),
          Text(
            'FlatSphere',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Apartment association management – transparent, accountable, simple.',
            style: white.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 32),
          for (final f in const [
            (Icons.verified_user_outlined, 'Maker-checker approvals with MOM links'),
            (Icons.report_problem_outlined, 'Complaints with Green / Amber / Red SLA tracking'),
            (Icons.account_balance_outlined, 'Dues, UPI payments and audit-ready accounts'),
            (Icons.checklist_rtl, 'Caretaker daily checklist with voice notes'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(f.$1, color: Colors.white70),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f.$2, style: white)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            backendEnabled ? 'Beta · secure cloud login' : 'Beta prototype · demo data only',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}
