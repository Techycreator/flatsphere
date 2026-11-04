import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backend.dart' show backendEnabled;
import '../backend/notifications_repo.dart';
import '../security/web_push.dart';
import 'common.dart';

/// Asks once per device to turn on phone alerts (SOS, visitors at the gate, approvals, dues reminders).
class PushPromptCard extends StatefulWidget {
  const PushPromptCard({super.key});

  @override
  State<PushPromptCard> createState() => _PushPromptCardState();
}

class _PushPromptCardState extends State<PushPromptCard> {
  static const _key = 'push_prompt_done';
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && backendEnabled) {
      SharedPreferences.getInstance().then((p) {
        if (mounted && p.getBool(_key) != true) setState(() => _show = true);
      });
    }
  }

  Future<void> _done() async {
    (await SharedPreferences.getInstance()).setBool(_key, true);
    if (mounted) setState(() => _show = false);
  }

  Future<void> _enable() async {
    try {
      final sub = await subscribeWebPush(PushRepo.vapidPublicKey);
      if (sub == null) {
        if (mounted) {
          toast(
            context,
            'Alerts not turned on. Allow notifications for this site in the browser settings. '
            'On iPhone, first add FlatSphere to the Home Screen.',
          );
        }
        return;
      }
      await PushRepo.save(sub);
      if (mounted) toast(context, 'Alerts are on for this device.');
      await _done();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.notifications_active_outlined, size: 32),
          title: const Text('Turn on alerts on this phone'),
          subtitle: const Text(
            'Get SOS alerts, visitors at the gate, approvals and dues reminders even when the app is closed.',
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              TextButton(onPressed: _done, child: const Text('Not now')),
              FilledButton(onPressed: _enable, child: const Text('Turn on')),
            ],
          ),
          isThreeLine: true,
        ),
      ),
    );
  }
}
