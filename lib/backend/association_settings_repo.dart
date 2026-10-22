import 'backend.dart';

class AssociationSettingsRepo {
  static Future<String> createAssociation({
    required String name,
    required String state,
    required String city,
    required String brandPrimary,
  }) async => await db.rpc('create_association_for_admin', params: {
    'p_name': name.trim(),
    'p_state': state.trim(),
    'p_city': city.trim(),
    'p_brand_primary': brandPrimary.trim(),
  }) as String;

  static Future<void> update({
    required String name,
    required String state,
    required String city,
    required String brandPrimary,
    required int fiscalYearStartMonth,
    required int defaultDueDay,
  }) => db.rpc('update_active_association_settings', params: {
    'p_name': name.trim(),
    'p_state': state.trim(),
    'p_city': city.trim(),
    'p_brand_primary': brandPrimary.trim(),
    'p_fiscal_year_start_month': fiscalYearStartMonth,
    'p_default_due_day': defaultDueDay,
  });
}
