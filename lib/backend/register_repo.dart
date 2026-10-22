import '../models/models.dart';
import 'backend.dart';

class RegisterRepo {
  static Future<List<AssociationRegisterItem>> list() async {
    final rows = await db
        .from('association_register_items')
        .select('id, record_type, name, category, status, vendor, purchase_date, warranty_end, amc_end, expires_on, expected_life_years, replacement_cost, details, created_at')
        .order('created_at', ascending: false);
    return [for (final row in rows) _item(row)];
  }

  static Future<List<AssociationRegisterItem>> expiringSoon({int days = 90}) async {
    final rows = await db.rpc('expiring_association_records', params: {'p_days': days}) as List;
    return [for (final row in rows.cast<Map<String, dynamic>>()) _item(row)];
  }

  static Future<void> submit({
    required String type,
    required String name,
    required String category,
    required String vendor,
    required DateTime? purchaseDate,
    required DateTime? warrantyEnd,
    required DateTime? amcEnd,
    required DateTime? expiresOn,
    required int? expectedLifeYears,
    required int? replacementCost,
    required Map<String, dynamic> details,
    required String requestRef,
  }) async {
    await db.rpc(
      'submit_association_register_item',
      params: {
        'p_type': type,
        'p_name': name,
        'p_category': category,
        'p_vendor': vendor,
        'p_purchase_date': _date(purchaseDate),
        'p_warranty_end': _date(warrantyEnd),
        'p_amc_end': _date(amcEnd),
        'p_expires_on': _date(expiresOn),
        'p_expected_life_years': expectedLifeYears,
        'p_replacement_cost': replacementCost,
        'p_details': details,
        'p_ref': requestRef,
      },
    );
  }

  static AssociationRegisterItem _item(Map<String, dynamic> row) => AssociationRegisterItem(
    id: row['id'] as String,
    type: row['record_type'] as String,
    name: row['name'] as String,
    category: row['category'] as String? ?? '',
    status: row['status'] as String? ?? 'pending',
    vendor: row['vendor'] as String?,
    purchaseDate: _parseDate(row['purchase_date']),
    warrantyEnd: _parseDate(row['warranty_end']),
    amcEnd: _parseDate(row['amc_end']),
    expiresOn: _parseDate(row['expires_on']),
    expectedLifeYears: (row['expected_life_years'] as num?)?.toInt(),
    replacementCost: (row['replacement_cost'] as num?)?.toInt(),
    details: Map<String, dynamic>.from(row['details'] as Map? ?? const {}),
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

  static DateTime? _parseDate(Object? value) => value == null ? null : DateTime.parse(value as String);
  static String? _date(DateTime? value) => value?.toIso8601String().substring(0, 10);
}