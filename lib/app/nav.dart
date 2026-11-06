import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';

class NavItem {
  const NavItem(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String Function(AppLocalizations) label;
}

final _gate = NavItem('/gate', Icons.shield_outlined, (l) => 'Gate');
final _home = NavItem('/home', Icons.space_dashboard_outlined, (l) => l.dashboard);
final _complaints = NavItem('/complaints', Icons.report_problem_outlined, (l) => l.complaints);
final _checklist = NavItem('/checklist', Icons.checklist_rtl, (l) => l.checklist);
final _approvals = NavItem('/approvals', Icons.verified_outlined, (l) => l.approvals);
final _finance = NavItem('/finance', Icons.account_balance_wallet_outlined, (l) => l.finance);
final _statements = NavItem('/statements', Icons.description_outlined, (_) => 'Statements');
final _dues = NavItem('/dues', Icons.payments_outlined, (l) => l.myDues);
final _meetings = NavItem('/meetings', Icons.groups_outlined, (l) => l.meetings);
final _directory = NavItem('/directory', Icons.apartment_outlined, (l) => l.directory);
final _familyAccounts = NavItem('/family-accounts', Icons.family_restroom_outlined, (_) => 'Family accounts');
final _attendance = NavItem('/attendance', Icons.fact_check_outlined, (l) => l.attendance);
final _householdStaff = NavItem('/household-staff', Icons.cleaning_services_outlined, (l) => l.householdStaff);
final _visitors = NavItem('/visitors', Icons.directions_walk_outlined, (l) => l.visitors);
final _vehicles = NavItem('/vehicles', Icons.directions_car_outlined, (l) => l.vehicleLookup);
final _archive = NavItem('/archive', Icons.inventory_2_outlined, (l) => l.archive);
final _registers = NavItem('/registers', Icons.inventory_2_outlined, (l) => l.registers);
final _amenities = NavItem('/amenities', Icons.meeting_room_outlined, (l) => l.amenities);
final _community = NavItem('/community', Icons.hub_outlined, (l) => l.community);
final _associationDocs = NavItem('/association-documents', Icons.folder_shared_outlined, (l) => l.associationDocuments);
final _associationSettings = NavItem('/association-settings', Icons.settings_outlined, (_) => 'Association settings');
final _workflows = NavItem('/workflows', Icons.account_tree_outlined, (_) => 'Approval workflows');
final _notices = NavItem('/notices', Icons.campaign_outlined, (l) => l.notices);

const navGroups = ['Money', 'People', 'Building', 'Records'];

String navGroupOf(String path) => switch (path) {
  '/finance' || '/statements' || '/dues' => 'Money',
  '/directory' || '/family-accounts' || '/attendance' || '/household-staff' || '/visitors' || '/vehicles' => 'People',
  '/complaints' || '/checklist' || '/amenities' || '/community' || '/notices' => 'Building',
  _ => 'Records',
};

/// On mobile, items beyond the fourth go under "More" when a role has more than five.
/// A designated Membership-desk EC member/monitor also gets Approvals and Flats & people.
List<NavItem> navFor(Role r, {bool membershipDesk = false}) {
  final base = _baseNav(r);
  if (!membershipDesk || base.contains(_approvals)) return base;
  return [base.first, _approvals, ...base.skip(1), _directory];
}

List<NavItem> _baseNav(Role r) => switch (r) {
  Role.admin => [
    _home,
    _approvals,
    _complaints,
    _finance,
    _directory,
    _attendance,
    _visitors,
    _gate,
    _vehicles,
    _archive,
    _registers,
    _amenities,
    _community,
    _associationDocs,
    _associationSettings,
    _workflows,
  ],
  Role.president => [
    _home,
    _approvals,
    _complaints,
    _finance,
    _meetings,
    _directory,
    _attendance,
    _visitors,
    _gate,
    _householdStaff,
    _vehicles,
    _archive,
    _registers,
    _amenities,
    _community,
    _associationDocs,
  ],
  Role.secretary => [
    _home,
    _approvals,
    _complaints,
    _finance,
    _checklist,
    _meetings,
    _directory,
    _attendance,
    _visitors,
    _gate,
    _householdStaff,
    _vehicles,
    _archive,
    _registers,
    _amenities,
    _community,
    _associationDocs,
  ],
  Role.treasurer => [
    _home,
    _finance,
    _approvals,
    _complaints,
    _meetings,
    _attendance,
    _visitors,
    _householdStaff,
    _vehicles,
    _registers,
    _amenities,
    _community,
    _associationDocs,
  ],
  Role.jointTreasurer => [
    _home,
    _finance,
    _approvals,
    _complaints,
    _meetings,
    _attendance,
    _visitors,
    _vehicles,
    _registers,
    _amenities,
    _community,
    _associationDocs,
  ],
  Role.vicePresident => [
    _home,
    _approvals,
    _complaints,
    _finance,
    _meetings,
    _attendance,
    _visitors,
    _householdStaff,
    _registers,
    _amenities,
    _community,
    _associationDocs,
  ],
  Role.jointSecretary => [
    _home,
    _approvals,
    _complaints,
    _finance,
    _checklist,
    _meetings,
    _directory,
    _attendance,
    _visitors,
    _householdStaff,
    _registers,
    _amenities,
    _community,
    _associationDocs,
  ],
  Role.ecMember => [
    _home,
    _checklist,
    _complaints,
    _finance,
    _meetings,
    _attendance,
    _householdStaff,
    _vehicles,
    _community,
    _associationDocs,
  ],
  Role.monitor => [_home, _checklist, _attendance, _complaints, _finance, _meetings, _community, _associationDocs],
  Role.owner => [
    _home,
    _dues,
    _visitors,
    _complaints,
    _statements,
    _familyAccounts,
    _meetings,
    _householdStaff,
    _amenities,
    _approvals,
    _community,
    _associationDocs,
    _notices,
  ],
  Role.resident => [
    _home,
    _visitors,
    _complaints,
    _amenities,
    _familyAccounts,
    _householdStaff,
    _approvals,
    _community,
    _notices,
  ],
  Role.caretaker => [
    _home,
    _checklist,
    _attendance,
    _complaints,
    _visitors,
    _householdStaff,
    _vehicles,
    _community,
    _associationDocs,
    _notices,
    _gate,
  ],
  Role.security => [_gate, _vehicles, _community],
  Role.auditor => [_home, _finance, _registers],
};
