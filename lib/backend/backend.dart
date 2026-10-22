import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Supplied at build time: flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// When absent the app runs in demo mode on in-memory data.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const backendEnabled = supabaseUrl != '' && supabaseAnonKey != '';

Future<void> initBackend() async {
  if (backendEnabled) await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
}

SupabaseClient get db => Supabase.instance.client;

const _roleByDb = {
  'president': Role.president,
  'secretary': Role.secretary,
  'treasurer': Role.treasurer,
  'vice_president': Role.vicePresident,
  'joint_secretary': Role.jointSecretary,
  'ec_member': Role.ecMember,
  'monitor': Role.monitor,
  'owner': Role.owner,
  'resident': Role.resident,
  'caretaker': Role.caretaker,
  'auditor': Role.auditor,
};

class AuthService {
  static Future<void> sendCode(String email) => db.auth.signInWithOtp(email: email.trim());

  static Future<void> verifyCode(String email, String code) =>
      db.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);

  static Future<void> signOut() => db.auth.signOut();

  /// Builds the signed-in user's roles from active memberships; null if none.
  static Future<DemoUser?> loadUser() async {
    final u = db.auth.currentUser;
    if (u == null) return null;
    final profile = await db.from('profiles').select('full_name').eq('id', u.id).maybeSingle();
    final rows = await db
        .from('memberships')
        .select('role, designations, monitor_categories, flats(number)')
        .eq('user_id', u.id)
        .isFilter('ended_at', null);
    final roles = <Role>{};
    final designations = <String>{};
    final categories = <String>{};
    String? flat;
    for (final r in rows) {
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
    );
  }
}
