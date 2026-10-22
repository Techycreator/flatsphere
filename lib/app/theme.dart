import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/sla.dart';

class AppColors {
  static const seed = Color(0xFF0F766E);
  static const green = Color(0xFF16A34A);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFDC2626);

  static Color sla(SlaColor c) => switch (c) {
    SlaColor.blue => const Color(0xFF2563EB),
    SlaColor.amber => amber,
    SlaColor.red => red,
    SlaColor.green => green,
    SlaColor.grey => const Color(0xFF64748B),
  };

  static Color complaintStatus(TicketStatus status) => switch (status) {
    TicketStatus.pendingReview => const Color(0xFF7C3AED),
    TicketStatus.newTicket || TicketStatus.assigned || TicketStatus.inProgress => const Color(0xFF2563EB),
    TicketStatus.onHold => amber,
    TicketStatus.resolved => green,
    TicketStatus.closed || TicketStatus.rejected => const Color(0xFF64748B),
    TicketStatus.planned => const Color(0xFF0F766E),
  };
}

class AppTheme {
  static ThemeData get light => lightForSeed(AppColors.seed);

  static ThemeData lightForSeed(Color seed) {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
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
