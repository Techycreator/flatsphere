import '../models/models.dart';
import 'backend.dart';

class AmenitiesRepo {
  static Future<List<Amenity>> amenities() async {
    final rows = await db
        .from('amenities')
        .select('id,name,rules,fee,requires_approval')
        .eq('active', true)
        .order('name');
    return [
      for (final row in rows)
        Amenity(
          id: row['id'] as String,
          name: row['name'] as String,
          rules: row['rules'] as String? ?? '',
          fee: (row['fee'] as num?)?.toInt() ?? 0,
          requiresApproval: row['requires_approval'] as bool? ?? true,
        ),
    ];
  }

  static Future<List<(String id, String number)>> myFlats() async {
    final rows = await db
        .from('memberships')
        .select('flat_id,flats(number)')
        .eq('user_id', db.auth.currentUser!.id)
        .isFilter('ended_at', null)
        .inFilter('role', ['owner', 'resident']);
    final unique = <String, String>{};
    for (final row in rows) {
      if (row['flat_id'] case final String id) {
        unique[id] = ((row['flats'] as Map?)?['number'] as String?) ?? '';
      }
    }
    return [for (final e in unique.entries) (e.key, e.value)];
  }

  static Future<List<AmenityBooking>> bookings() async {
    final rows = await db
        .from('amenity_bookings')
        .select(
          'id,starts_at,ends_at,guest_count,amount_due,payment_status,status,note,amenities(name),flats(number),'
          'host:profiles!amenity_bookings_booked_by_fkey(full_name)',
        )
        .order('starts_at', ascending: false);
    return [
      for (final row in rows)
        AmenityBooking(
          id: row['id'] as String,
          amenityName: ((row['amenities'] as Map?)?['name'] as String?) ?? 'Amenity',
          flatNumber: ((row['flats'] as Map?)?['number'] as String?) ?? '',
          hostName: ((row['host'] as Map?)?['full_name'] as String?) ?? '',
          startsAt: DateTime.parse(row['starts_at'] as String).toLocal(),
          endsAt: DateTime.parse(row['ends_at'] as String).toLocal(),
          status: _bookingStatus(row['status']),
          paymentStatus: _paymentStatus(row['payment_status']),
          amountDue: (row['amount_due'] as num?)?.toInt() ?? 0,
          guestCount: (row['guest_count'] as num?)?.toInt() ?? 0,
          note: row['note'] as String? ?? '',
        ),
    ];
  }

  static Future<void> request({
    required String amenityId,
    required String flatId,
    required DateTime startsAt,
    required DateTime endsAt,
    required int guestCount,
    required String note,
  }) async {
    await db.rpc(
      'request_amenity_booking',
      params: {
        'p_amenity': amenityId,
        'p_flat': flatId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_guest_count': guestCount,
        'p_note': note,
      },
    );
  }

  static Future<void> recordPayment(String id, {String reference = '', bool waive = false}) =>
      db.rpc('record_amenity_payment', params: {'p_booking': id, 'p_reference': reference, 'p_waive': waive});

  /// Pending/approved bookings that overlap [day] (India time), without personal details.
  static Future<List<(DateTime, DateTime, String)>> busySlots(String amenityId, DateTime day) async {
    final rows = await db.rpc(
      'amenity_busy_slots',
      params: {'p_amenity': amenityId, 'p_day': day.toIso8601String().substring(0, 10)},
    ) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (
          DateTime.parse(r['starts_at'] as String).toLocal(),
          DateTime.parse(r['ends_at'] as String).toLocal(),
          r['status'] as String,
        ),
    ];
  }
}

AmenityBookingStatus _bookingStatus(Object? value) => switch (value) {
  'approved' => AmenityBookingStatus.approved,
  'rejected' => AmenityBookingStatus.rejected,
  'cancelled' => AmenityBookingStatus.cancelled,
  'completed' => AmenityBookingStatus.completed,
  _ => AmenityBookingStatus.pending,
};

AmenityPaymentStatus _paymentStatus(Object? value) => switch (value) {
  'paid' => AmenityPaymentStatus.paid,
  'waived' => AmenityPaymentStatus.waived,
  'refunded' => AmenityPaymentStatus.refunded,
  _ => AmenityPaymentStatus.unpaid,
};
