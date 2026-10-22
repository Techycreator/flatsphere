import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'backend/backend.dart';
import 'app/theme.dart';
import 'l10n/app_localizations.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackend();
  final container = ProviderContainer();
  if (backendEnabled) {
    final user = await AuthService.loadUser();
    if (user != null) container.read(sessionProvider.notifier).login(user);
  }
  runApp(UncontrolledProviderScope(container: container, child: const FlatSphereApp()));
}

class FlatSphereApp extends ConsumerWidget {
  const FlatSphereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'FlatSphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
