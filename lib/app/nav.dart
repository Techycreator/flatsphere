import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';

class NavItem {
  const NavItem(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String Function(AppLocalizations) label;
}

final _home = NavItem('/home', Icons.space_dashboard_outlined, (l) => l.dashboard);
final _complaints = NavItem('/complaints', Icons.report_problem_outlined, (l) => l.complaints);
final _checklist = NavItem('/checklist', Icons.checklist_rtl, (l) => l.checklist);
final _approvals = NavItem('/approvals', Icons.verified_outlined, (l) => l.approvals);
final _finance = NavItem('/finance', Icons.account_balance_wallet_outlined, (l) => l.finance);
final _dues = NavItem('/dues', Icons.payments_outlined, (l) => l.myDues);
final _meetings = NavItem('/meetings', Icons.groups_outlined, (l) => l.meetings);
final _notices = NavItem('/notices', Icons.campaign_outlined, (l) => l.notices);

/// Max 5 items per role so the mobile bottom bar stays usable.
List<NavItem> navFor(Role r) => switch (r) {
      Role.president => [_home, _approvals, _complaints, _finance, _meetings],
      Role.secretary => [_home, _approvals, _complaints, _checklist, _meetings],
      Role.treasurer => [_home, _finance, _approvals, _complaints, _meetings],
      Role.vicePresident || Role.jointSecretary => [_home, _approvals, _complaints, _checklist, _meetings],
      Role.ecMember || Role.monitor => [_home, _checklist, _complaints, _finance, _meetings],
      Role.owner => [_home, _dues, _complaints, _meetings, _notices],
      Role.resident => [_home, _complaints, _notices],
      Role.caretaker => [_home, _checklist, _complaints, _notices],
      Role.auditor => [_home, _finance],
    };
