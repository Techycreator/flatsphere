import 'backend.dart';
import '../models/models.dart';

class AssociationSettingsRepo {
  static Future<List<IdDocumentAccessEntry>> idDocumentAccess() async {
    final rows = await db.rpc('list_id_document_access') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        IdDocumentAccessEntry(
          userId: row['user_id'] as String,
          name: row['full_name'] as String,
          roles: row['role_labels'] as String,
          canViewAll: row['can_view_all'] as bool,
          isOfficeBearer: row['is_office_bearer'] as bool,
        ),
    ];
  }

  static Future<void> setIdDocumentAccess(String userId, bool enabled) =>
      db.rpc('set_id_document_access', params: {'p_user_id': userId, 'p_can_view': enabled});

  static Future<String> createFirstAssociation({
    required String name,
    required String state,
    required String city,
    required String brandPrimary,
    required String adminName,
  }) async => await db.rpc(
    'create_first_association',
    params: {
      'p_name': name.trim(),
      'p_state': state.trim(),
      'p_city': city.trim(),
      'p_brand_primary': brandPrimary.trim(),
      'p_full_name': adminName.trim(),
    },
  ) as String;

  static Future<String> createAssociation({
    required String name,
    required String state,
    required String city,
    required String brandPrimary,
  }) async => await db.rpc(
    'create_association_for_admin',
    params: {
      'p_name': name.trim(),
      'p_state': state.trim(),
      'p_city': city.trim(),
      'p_brand_primary': brandPrimary.trim(),
    },
  ) as String;

  static Future<void> update({
    required String name,
    required String state,
    required String city,
    required String brandPrimary,
    required int fiscalYearStartMonth,
    required int defaultDueDay,
  }) => db.rpc(
    'update_active_association_settings',
    params: {
      'p_name': name.trim(),
      'p_state': state.trim(),
      'p_city': city.trim(),
      'p_brand_primary': brandPrimary.trim(),
      'p_fiscal_year_start_month': fiscalYearStartMonth,
      'p_default_due_day': defaultDueDay,
    },
  );

  static Future<void> updateFamilyRules({required int minimumLoginAge, required int memberLimit}) => db.rpc(
    'update_family_account_rules',
    params: {'p_min_login_age': minimumLoginAge, 'p_member_limit': memberLimit},
  );
}
