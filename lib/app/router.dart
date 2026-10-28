import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/approvals/approval_detail_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/amenities/amenities_screen.dart';
import '../features/approvals/membership_request_screen.dart';
import '../features/archive/archive_screen.dart';
import '../features/attendance/staff_attendance_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/first_association_setup_screen.dart';
import '../features/checklist/checklist_screen.dart';
import '../features/complaints/complaint_detail_screen.dart';
import '../features/complaints/complaints_screen.dart';
import '../features/complaints/raise_complaint_screen.dart';
import '../features/community/community_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/directory/directory_screen.dart';
import '../features/directory/family_accounts_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/registers/association_register_screen.dart';
import '../features/registers/association_documents_screen.dart';
import '../features/finance/my_dues_screen.dart';
import '../features/attendance/household_staff_screen.dart';
import '../features/meetings/meetings_screen.dart';
import '../features/notices/notices_screen.dart';
import '../features/visitors/gate_screen.dart';
import '../features/visitors/visitors_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/association_settings_screen.dart';
import '../features/shell/workflow_admin_screen.dart';
import '../features/shell/audit_export_screen.dart';
import '../features/shell/data_tools_screen.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'nav.dart';
import '../backend/backend.dart' show backendEnabled;
import '../features/auth/device_lock_screen.dart';
import '../security/device_lock.dart';

Page<void> _page(Widget child) => NoTransitionPage(child: child);

/// Route guard: a role may only open sections in its own menu (deep links included).
/// Owners may also open approvals that need their consent (W21); Membership-desk EC members raise W20–W22.
bool canAccess(Role role, String location, {bool membershipDesk = false}) {
  final allowed = [
    ...navFor(role, membershipDesk: membershipDesk).map((i) => i.path),
    if (role == Role.owner) '/approvals',
    '/notices',
    if (const {Role.admin, Role.president, Role.secretary}.contains(role)) ...['/audit', '/data-tools'],
    if (const {Role.admin, Role.president, Role.secretary}.contains(role)) '/gate',
  ];
  return allowed.any((p) => location == p || location.startsWith('$p/'));
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(firstAssociationSignupProvider, (_, _) => refresh.value++);
  ref.listen(lockProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final signupEmail = ref.read(firstAssociationSignupProvider);
      final atLogin = state.matchedLocation == '/login';
      final atAssociationSetup = state.matchedLocation == '/setup-association';
      if (session == null) {
        if (signupEmail != null) return atAssociationSetup ? null : '/setup-association';
        return atLogin ? null : '/login';
      }
      if (backendEnabled) {
        final lock = ref.read(lockProvider);
        if (lock == LockStatus.locked) return state.matchedLocation == '/unlock' ? null : '/unlock';
        if (lock == LockStatus.needsSetup) return state.matchedLocation == '/set-pin' ? null : '/set-pin';
      }
      if (state.matchedLocation == '/unlock') return '/home';
      if (state.matchedLocation == '/set-pin') return null;
      if (atAssociationSetup) return '/home';
      if (atLogin) return '/home';
      return canAccess(
            session.activeRole,
            state.matchedLocation,
            membershipDesk: session.user.canInitiateMembership(session.activeRole),
          )
          ? null
          : '/home';
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/unlock', builder: (_, _) => const DeviceLockScreen(setup: false)),
      GoRoute(path: '/set-pin', builder: (_, _) => const DeviceLockScreen(setup: true)),
      GoRoute(path: '/setup-association', builder: (_, _) => const FirstAssociationSetupScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: (_, _) => _page(const DashboardScreen())),
          GoRoute(
            path: '/complaints',
            pageBuilder: (_, s) => _page(ComplaintsScreen(initialFilter: s.uri.queryParameters['filter'])),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const RaiseComplaintScreen()),
              GoRoute(
                path: ':id',
                builder: (_, s) => ComplaintDetailScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/checklist', pageBuilder: (_, _) => _page(const ChecklistScreen())),
          GoRoute(path: '/attendance', pageBuilder: (_, _) => _page(const StaffAttendanceScreen())),
          GoRoute(path: '/household-staff', pageBuilder: (_, _) => _page(const HouseholdStaffScreen())),
          GoRoute(path: '/archive', pageBuilder: (_, _) => _page(const ArchiveScreen())),
          GoRoute(path: '/registers', pageBuilder: (_, _) => _page(const AssociationRegisterScreen())),
          GoRoute(path: '/association-documents', pageBuilder: (_, _) => _page(const AssociationDocumentsScreen())),
          GoRoute(path: '/association-settings', pageBuilder: (_, _) => _page(const AssociationSettingsScreen())),
          GoRoute(path: '/workflows', pageBuilder: (_, _) => _page(const WorkflowAdminScreen())),
          GoRoute(path: '/audit', pageBuilder: (_, _) => _page(const AuditExportScreen())),
          GoRoute(path: '/data-tools', pageBuilder: (_, _) => _page(const DataToolsScreen())),
          GoRoute(path: '/amenities', pageBuilder: (_, _) => _page(const AmenitiesScreen())),
          GoRoute(
            path: '/community',
            pageBuilder: (_, state) {
              final initialTab = switch (state.uri.queryParameters['tab']) {
                'events' => 2,
                'marketplace' => 1,
                _ => 0,
              };
              return _page(CommunityScreen(initialTab: initialTab));
            },
          ),
          GoRoute(
            path: '/approvals',
            pageBuilder: (_, _) => _page(const ApprovalsScreen()),
            routes: [
              GoRoute(
                path: 'new/:type',
                builder: (_, s) {
                  final t = MembershipRequestType.parse(s.pathParameters['type']!);
                  return t == null ? const ApprovalsScreen() : MembershipRequestScreen(type: t);
                },
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => ApprovalDetailScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/finance', pageBuilder: (_, _) => _page(const FinanceScreen())),
          GoRoute(path: '/statements', pageBuilder: (_, _) => _page(const StatementsScreen())),
          GoRoute(path: '/dues', pageBuilder: (_, _) => _page(const MyDuesScreen())),
          GoRoute(path: '/meetings', pageBuilder: (_, _) => _page(const MeetingsScreen())),
          GoRoute(path: '/directory', pageBuilder: (_, _) => _page(const DirectoryScreen())),
          GoRoute(path: '/family-accounts', pageBuilder: (_, _) => _page(const FamilyAccountsScreen())),
          GoRoute(path: '/notices', pageBuilder: (_, _) => _page(const NoticesScreen())),
          GoRoute(path: '/visitors', pageBuilder: (_, _) => _page(const VisitorsScreen())),
          GoRoute(path: '/gate', pageBuilder: (_, _) => _page(const GateScreen())),
          GoRoute(path: '/vehicles', pageBuilder: (_, _) => _page(const VehicleLookupScreen())),
        ],
      ),
    ],
  );
});
