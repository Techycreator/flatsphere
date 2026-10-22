import 'package:flutter/material.dart';

import '../models/sla.dart';

class AppColors {
  static const seed = Color(0xFF0F766E);
  static const green = Color(0xFF16A34A);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFDC2626);

  static Color sla(SlaColor c) => switch (c) {
    SlaColor.green => green,
    SlaColor.amber => amber,
    SlaColor.red => red,
  };
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F8F8),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      chipTheme: const ChipThemeData(side: BorderSide.none),
    );
  }
}
