import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/demo_data.dart';
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
  String? _error;

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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(l.login, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
            const LanguageToggle(),
          ]),
          const SizedBox(height: 4),
          Text(associationName, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          TextField(
            controller: _mobile,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.mobileNumber, prefixText: '+91 '),
          ),
          if (_otpSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(labelText: l.enterOtp, counterText: ''),
              onSubmitted: (_) => _verify(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _otpSent ? _verify() : setState(() => _otpSent = true),
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_otpSent ? l.verify : l.sendOtp)),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text(l.demoPersonas, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final u in demoUsers) _PersonaTile(user: u),
        ]),
      ),
    );

    return Scaffold(
      body: Row(children: [
        if (wide) const Expanded(child: _BrandPanel()),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: form),
            ),
          ),
        ),
      ]),
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
        gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF134E4A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.apartment, color: Colors.white, size: 56),
        const SizedBox(height: 16),
        Text('FlatSphere', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Apartment association management – transparent, accountable, simple.', style: white.copyWith(fontSize: 18)),
        const SizedBox(height: 32),
        for (final f in const [
          (Icons.verified_user_outlined, 'Maker-checker approvals with MOM links'),
          (Icons.report_problem_outlined, 'Complaints with Green / Amber / Red SLA tracking'),
          (Icons.account_balance_outlined, 'Dues, UPI payments and audit-ready accounts'),
          (Icons.checklist_rtl, 'Caretaker daily checklist with voice notes'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [Icon(f.$1, color: Colors.white70), const SizedBox(width: 12), Expanded(child: Text(f.$2, style: white))]),
          ),
        const SizedBox(height: 24),
        const Text('Beta prototype · demo data only', style: TextStyle(color: Colors.white60)),
      ]),
    );
  }
}
