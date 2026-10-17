import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/approvals/approval_detail_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/checklist/checklist_screen.dart';
import '../features/complaints/complaint_detail_screen.dart';
import '../features/complaints/complaints_screen.dart';
import '../features/complaints/raise_complaint_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/finance/my_dues_screen.dart';
import '../features/meetings/meetings_screen.dart';
import '../features/notices/notices_screen.dart';
import '../features/shell/app_shell.dart';
import '../state/app_state.dart';

Page<void> _page(Widget child) => NoTransitionPage(child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: (_, _) => _page(const DashboardScreen())),
          GoRoute(
            path: '/complaints',
            pageBuilder: (_, _) => _page(const ComplaintsScreen()),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const RaiseComplaintScreen()),
              GoRoute(path: ':id', builder: (_, s) => ComplaintDetailScreen(id: s.pathParameters['id']!)),
            ],
          ),
          GoRoute(path: '/checklist', pageBuilder: (_, _) => _page(const ChecklistScreen())),
          GoRoute(
            path: '/approvals',
            pageBuilder: (_, _) => _page(const ApprovalsScreen()),
            routes: [
              GoRoute(path: ':id', builder: (_, s) => ApprovalDetailScreen(id: s.pathParameters['id']!)),
            ],
          ),
          GoRoute(path: '/finance', pageBuilder: (_, _) => _page(const FinanceScreen())),
          GoRoute(path: '/dues', pageBuilder: (_, _) => _page(const MyDuesScreen())),
          GoRoute(path: '/meetings', pageBuilder: (_, _) => _page(const MeetingsScreen())),
          GoRoute(path: '/notices', pageBuilder: (_, _) => _page(const NoticesScreen())),
        ],
      ),
    ],
  );
});
