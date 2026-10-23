import 'dart:typed_data';

import '../models/vendor.dart';
import 'backend.dart';
import 'upload_preparation.dart';

class VendorsRepo {
  static Future<List<AssociationVendor>> list() async {
    final rows = await db
        .from('association_vendors')
        .select('*,vendor_amc_contracts(*),vendor_contract_documents(*)')
        .order('name');
    return [for (final row in rows) _vendor(row)];
  }

  static Future<void> save({
    String? id,
    required String name,
    required String serviceCategory,
    required String contactName,
    required String phone,
    required String email,
    required String address,
    required num securityDeposit,
    required List<String> escalationContacts,
  }) async {
    final data = {
      'name': name.trim(),
      'service_category': serviceCategory,
      'contact_name': contactName.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'address': address.trim(),
      'security_deposit': securityDeposit,
      'escalation_contacts': escalationContacts,
    };
    if (id == null) {
      await db.from('association_vendors').insert(data);
    } else {
      await db.from('association_vendors').update(data).eq('id', id);
    }
  }

  static Future<void> setActive(String id, bool active) =>
      db.from('association_vendors').update({'active': active}).eq('id', id);

  static Future<void> addContract({
    required String vendorId,
    required String serviceName,
    required DateTime startDate,
    required DateTime endDate,
    required int renewalNoticeDays,
    num? annualCost,
  }) async {
    await db.from('vendor_amc_contracts').insert({
      'vendor_id': vendorId,
      'service_name': serviceName.trim(),
      'start_date': _date(startDate),
      'end_date': _date(endDate),
      'renewal_notice_days': renewalNoticeDays,
      'annual_cost': annualCost,
    });
  }

  static Future<void> updateContract({
    required String id,
    required String serviceName,
    required DateTime startDate,
    required DateTime endDate,
    required int renewalNoticeDays,
    num? annualCost,
  }) async {
    await db.from('vendor_amc_contracts').update({
      'service_name': serviceName.trim(),
      'start_date': _date(startDate),
      'end_date': _date(endDate),
      'renewal_notice_days': renewalNoticeDays,
      'annual_cost': annualCost,
    }).eq('id', id);
  }

  static Future<void> setContractActive(String id, bool active) =>
      db.from('vendor_amc_contracts').update({'active': active}).eq('id', id);

  static Future<void> uploadDocument({
    required String vendorId,
    String? contractId,
    required String type,
    required String title,
    required Uint8List bytes,
    required String extension,
    DateTime? expiresOn,
  }) async {
    final prepared = await prepareUpload(bytes, extension);
    final association = await db.rpc('my_association') as String;
    final path = '$association/${DateTime.now().microsecondsSinceEpoch}.${prepared.extension}';
    await db.storage.from('vendor-contracts').uploadBinary(path, prepared.bytes);
    try {
      await db.rpc('register_vendor_document', params: {
        'p_vendor': vendorId,
        'p_contract': contractId,
        'p_type': type,
        'p_title': title.trim(),
        'p_storage_path': path,
        'p_expires_on': _date(expiresOn),
      });
    } catch (_) {
      await db.storage.from('vendor-contracts').remove([path]);
      rethrow;
    }
  }

  static Future<String> documentUrl(String id) async {
    final path = await db.rpc('log_vendor_document_view', params: {'p_document': id}) as String;
    return db.storage.from('vendor-contracts').createSignedUrl(path, 60);
  }

  static AssociationVendor _vendor(Map<String, dynamic> row) => AssociationVendor(
    id: row['id'] as String,
    name: row['name'] as String,
    serviceCategory: row['service_category'] as String,
    contactName: row['contact_name'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    address: row['address'] as String? ?? '',
    securityDeposit: row['security_deposit'] as num? ?? 0,
    escalationContacts: [
      for (final contact in (row['escalation_contacts'] as List? ?? const [])) contact.toString(),
    ],
    active: row['active'] as bool? ?? true,
    contracts: [
      for (final contract in (row['vendor_amc_contracts'] as List? ?? const []))
        VendorAmcContract(
          id: contract['id'] as String,
          serviceName: contract['service_name'] as String,
          startDate: DateTime.parse(contract['start_date'] as String),
          endDate: DateTime.parse(contract['end_date'] as String),
          annualCost: contract['annual_cost'] as num?,
          renewalNoticeDays: contract['renewal_notice_days'] as int? ?? 90,
          active: contract['active'] as bool? ?? true,
        ),
    ],
    documents: [
      for (final document in (row['vendor_contract_documents'] as List? ?? const []))
        VendorDocument(
          id: document['id'] as String,
          contractId: document['contract_id'] as String?,
          type: document['document_type'] as String,
          title: document['title'] as String,
          createdAt: DateTime.parse(document['created_at'] as String).toLocal(),
          expiresOn: document['expires_on'] == null ? null : DateTime.parse(document['expires_on'] as String),
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  static String? _date(DateTime? date) => date?.toIso8601String().substring(0, 10);
}
