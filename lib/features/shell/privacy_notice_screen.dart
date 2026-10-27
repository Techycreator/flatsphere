import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/compliance_repo.dart';
import '../../backend/directory_repo.dart' show friendlyError;
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Shown once per user before first use (Digital Personal Data Protection Act, 2023).
class PrivacyNoticeScreen extends ConsumerWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final association = ref.watch(sessionProvider)?.user.association?.name ?? 'your association';
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy notice')),
      body: PageBody(
        maxWidth: 720,
        children: [
          Text('How $association uses your data', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            '• What we store: your name, email, mobile, flat, role, dues and payments, complaints, approvals, '
            'and ID proofs or photos you or the committee upload.\n'
            '• Why: to run the association: membership, dues and receipts, complaints, meetings, security and records.\n'
            '• Who can see it: only the people your role allows. ID proofs are private, opened only by the Secretary, '
            'President or flat owner, and every view is logged.\n'
            '• Where: encrypted cloud storage in Mumbai, India. PIN or fingerprint unlock stays on your device; '
            'only the device name and last-used time are stored.\n'
            '• How long: finance records for at least 5 years; other data while you are a member, then archived as '
            'required by the bylaws.\n'
            '• Your rights: ask the Secretary to see, correct or delete your data (except records the law requires us to '
            'keep), or withdraw consent. Complaints go to the Secretary as grievance officer.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: () async {
                  try {
                    await ComplianceRepo.acceptPrivacy();
                    ref.invalidate(privacyAcceptedProvider);
                  } catch (error) {
                    if (context.mounted) toast(context, friendlyError(error));
                  }
                },
                child: const Text('I agree'),
              ),
              TextButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('Log out')),
            ],
          ),
        ],
      ),
    );
  }
}
