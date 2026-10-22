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
    else if (AuthService.currentUserEmail case final String email) {
      container.read(firstAssociationSignupProvider.notifier).setEmail(email);
    }
  }
  runApp(UncontrolledProviderScope(container: container, child: const FlatSphereApp()));
}

class FlatSphereApp extends ConsumerWidget {
  const FlatSphereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final association = ref.watch(sessionProvider)?.user.association;
    final brandValue = association?.settings['brand_primary'] as String?;
    final normalizedBrand = brandValue?.replaceFirst('#', '').replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    final brandRgb = normalizedBrand == null ? null : int.tryParse(normalizedBrand, radix: 16);
    final seed = brandRgb == null ? AppColors.seed : Color(0xFF000000 | (brandRgb & 0xFFFFFF));
    return MaterialApp.router(
      title: 'FlatSphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightForSeed(seed),
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
