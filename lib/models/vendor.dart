class AssociationVendor {
  const AssociationVendor({
    required this.id,
    required this.name,
    required this.serviceCategory,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.address,
    required this.securityDeposit,
    required this.escalationContacts,
    required this.active,
    this.contracts = const [],
    this.documents = const [],
  });

  final String id;
  final String name;
  final String serviceCategory;
  final String contactName;
  final String phone;
  final String email;
  final String address;
  final num securityDeposit;
  final List<String> escalationContacts;
  final bool active;
  final List<VendorAmcContract> contracts;
  final List<VendorDocument> documents;
}

class VendorAmcContract {
  const VendorAmcContract({
    required this.id,
    required this.serviceName,
    required this.startDate,
    required this.endDate,
    required this.renewalNoticeDays,
    required this.active,
    this.annualCost,
  });

  final String id;
  final String serviceName;
  final DateTime startDate;
  final DateTime endDate;
  final int renewalNoticeDays;
  final bool active;
  final num? annualCost;
}

class VendorDocument {
  const VendorDocument({
    required this.id,
    required this.contractId,
    required this.type,
    required this.title,
    required this.createdAt,
    this.expiresOn,
  });

  final String id;
  final String? contractId;
  final String type;
  final String title;
  final DateTime createdAt;
  final DateTime? expiresOn;
}
