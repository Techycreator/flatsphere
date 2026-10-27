import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'pin_vault.dart';

/// Supplied at build time: flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// When absent the app runs in demo mode on in-memory data.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const backendEnabled = supabaseUrl != '' && supabaseAnonKey != '';

Future<void> initBackend() async {
  if (!backendEnabled) return;
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: PinVault('sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'),
    ),
  );
}

SupabaseClient get db => Supabase.instance.client;

const _roleByDb = {
  'admin': Role.admin,
  'president': Role.president,
  'secretary': Role.secretary,
  'treasurer': Role.treasurer,
  'vice_president': Role.vicePresident,
  'joint_secretary': Role.jointSecretary,
  'joint_treasurer': Role.jointTreasurer,
  'ec_member': Role.ecMember,
  'monitor': Role.monitor,
  'owner': Role.owner,
  'resident': Role.resident,
  'caretaker': Role.caretaker,
  'security': Role.security,
  'auditor': Role.auditor,
};

class AuthService {
  static String? get currentUserEmail => db.auth.currentUser?.email;

  static Future<void> sendCode(String email) => db.auth.signInWithOtp(email: email.trim());

  static Future<void> verifyCode(String email, String code) =>
      db.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);

  static Future<void> signOut() => db.auth.signOut();

  /// Builds the signed-in user's roles from active memberships; null if none.
  static Future<DemoUser?> loadUser({String? associationId}) async {
    final u = db.auth.currentUser;
    if (u == null) return null;
    await db.rpc('claim_eligible_family_members');
    final profile = await db.from('profiles').select('full_name').eq('id', u.id).maybeSingle();
    final rows = await db
        .from('memberships')
        .select('association_id, role, designations, monitor_categories, monitor_until, assigned_by, flats(number)')
        .eq('user_id', u.id)
        .isFilter('ended_at', null);
    if (rows.isEmpty) return null;
    final associationRows = await db.rpc('my_associations') as List;
    final associations = [
      for (final row in associationRows)
        AssociationInfo(
          id: row['id'] as String,
          name: row['name'] as String,
          state: row['state'] as String? ?? '',
          city: row['city'] as String?,
          settings: Map<String, dynamic>.from(row['settings'] as Map? ?? const {}),
        ),
    ];
    final availableIds = associations.map((a) => a.id).toSet();
    final selectedId = associationId != null && availableIds.contains(associationId)
        ? associationId
        : (await db.rpc('my_association') as String?) ?? associations.first.id;
    if (!availableIds.contains(selectedId)) throw StateError('No active membership for the selected association');
    await db.rpc('set_active_association', params: {'assoc': selectedId});
    final roles = <Role>{};
    final designations = <String>{};
    final categories = <String>{};
    String? flat;
    DateTime? monitorUntil;
    String? assignedBy;
    for (final r in rows) {
      if (r['association_id'] != selectedId) continue;
      if (r['role'] == 'monitor') {
        monitorUntil = DateTime.tryParse(r['monitor_until'] as String? ?? '');
        assignedBy = r['assigned_by'] as String?;
      }
      final role = _roleByDb[r['role']];
      if (role != null) roles.add(role);
      flat ??= (r['flats'] as Map?)?['number'] as String?;
      designations.addAll(List<String>.from(r['designations'] as List? ?? const []));
      categories.addAll(List<String>.from(r['monitor_categories'] as List? ?? const []));
    }
    if (roles.isEmpty) return null;
    return DemoUser(
      id: u.id,
      name: profile?['full_name'] as String? ?? u.email ?? '',
      mobile: '',
      roles: roles.toList()..sort((a, b) => a.index.compareTo(b.index)),
      flatNumber: flat,
      designations: designations.toList(),
      monitorCategories: categories.toList(),
      monitorUntil: monitorUntil,
      monitorAssignedBy: assignedBy,
      associationId: selectedId,
      associations: associations,
    );
  }
}

String dbRole(Role r) => _roleByDb.entries.firstWhere((e) => e.value == r).key;

Role? roleFromDb(Object? v) => _roleByDb[v];
