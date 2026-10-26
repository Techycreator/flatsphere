import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../backend/amenities_repo.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

final amenitiesProvider = FutureProvider.autoDispose<List<Amenity>>((ref) => AmenitiesRepo.amenities());
final amenityBookingsProvider = FutureProvider.autoDispose<List<AmenityBooking>>((ref) => AmenitiesRepo.bookings());
final amenityFlatsProvider = FutureProvider.autoDispose<List<(String id, String number)>>(
  (ref) => AmenitiesRepo.myFlats(),
);

class AmenitiesScreen extends ConsumerWidget {
  const AmenitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)!.activeRole;
    final canReserve = role == Role.owner || role == Role.resident;
    final canRecordPayment = role == Role.treasurer || role == Role.jointTreasurer || role == Role.secretary;
    final amenities = ref.watch(amenitiesProvider);
    final bookings = ref.watch(amenityBookingsProvider);
    final flats = canReserve ? ref.watch(amenityFlatsProvider) : null;

    Future<void> createBooking() async {
      if (!amenities.hasValue || flats == null || !flats.hasValue) return;
      final draft = await _bookingDialog(context, amenities.value!, flats.value!);
      if (draft == null || !context.mounted) return;
      try {
        await AmenitiesRepo.request(
          amenityId: draft.amenityId,
          flatId: draft.flatId,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          guestCount: draft.guestCount,
          note: draft.note,
        );
        ref.invalidate(amenityBookingsProvider);
        await ref.read(approvalsProvider.notifier).refresh();
        if (context.mounted) toast(context, 'Booking submitted for approval');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    Future<void> recordPayment(AmenityBooking booking) async {
      final reference = await promptText(context, title: 'Record amenity payment', hint: 'Receipt / reference');
      if (reference == null || !context.mounted) return;
      try {
        await AmenitiesRepo.recordPayment(booking.id, reference: reference);
        ref.invalidate(amenityBookingsProvider);
        if (context.mounted) toast(context, 'Payment recorded');
      } catch (error) {
        if (context.mounted) toast(context, '$error');
      }
    }

    return PageBody(
      maxWidth: 1000,
      children: [
        Row(
          children: [
            Expanded(child: Text('Amenity booking', style: Theme.of(context).textTheme.headlineSmall)),
            if (canReserve)
              FilledButton.icon(
                onPressed: amenities.hasValue && flats?.hasValue == true ? createBooking : null,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Request booking'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (amenities.isLoading || bookings.isLoading) const LinearProgressIndicator(),
        if (amenities.hasError)
          Card(
            child: ListTile(leading: const Icon(Icons.error_outline), title: Text('${amenities.error}')),
          ),
        SectionCard(
          title: 'Available amenities',
          child: amenities.hasValue && amenities.value!.isNotEmpty
              ? Column(
                  children: [
                    for (final amenity in amenities.value!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.meeting_room_outlined),
                        title: Text(amenity.name),
                        subtitle: Text('${amenity.rules}${amenity.requiresApproval ? ' · Approval required' : ''}'),
                        trailing: Text(amenity.fee == 0 ? 'No fee' : inr.format(amenity.fee)),
                      ),
                  ],
                )
              : const EmptyState('No amenities are configured.', icon: Icons.meeting_room_outlined),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Bookings',
          padding: false,
          child: bookings.hasValue && bookings.value!.isNotEmpty
              ? Column(
                  children: [
                    for (final booking in bookings.value!)
                      ListTile(
                        leading: Icon(Icons.event_outlined, color: _bookingColor(booking.status)),
                        title: Text('${booking.amenityName} · ${booking.flatNumber}'),
                        subtitle: Text(
                          '${dateTimeFmt.format(booking.startsAt)} – ${dateTimeFmt.format(booking.endsAt)}'
                          ' · ${booking.hostName}${booking.note.isEmpty ? '' : '\n${booking.note}'}',
                        ),
                        isThreeLine: booking.note.isNotEmpty,
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Pill(booking.status.name, color: _bookingColor(booking.status)),
                                const SizedBox(height: 4),
                                Pill(
                                  _paymentLabel(booking.paymentStatus),
                                  color:
                                      booking.paymentStatus == AmenityPaymentStatus.paid ||
                                          booking.paymentStatus == AmenityPaymentStatus.waived
                                      ? AppColors.green
                                      : AppColors.amber,
                                ),
                              ],
                            ),
                            if (canRecordPayment &&
                                booking.status == AmenityBookingStatus.approved &&
                                booking.paymentStatus == AmenityPaymentStatus.unpaid)
                              IconButton(
                                tooltip: 'Record payment',
                                onPressed: () => recordPayment(booking),
                                icon: const Icon(Icons.payments_outlined),
                              ),
                          ],
                        ),
                      ),
                  ],
                )
              : const Padding(
                  padding: EdgeInsets.all(16),
                  child: EmptyState('No bookings found.', icon: Icons.event_busy_outlined),
                ),
        ),
      ],
    );
  }
}

class _BookingDraft {
  const _BookingDraft({
    required this.amenityId,
    required this.flatId,
    required this.startsAt,
    required this.endsAt,
    required this.guestCount,
    required this.note,
  });
  final String amenityId;
  final String flatId;
  final DateTime startsAt;
  final DateTime endsAt;
  final int guestCount;
  final String note;
}

Future<_BookingDraft?> _bookingDialog(
  BuildContext context,
  List<Amenity> amenities,
  List<(String id, String number)> flats,
) async {
  if (amenities.isEmpty || flats.isEmpty) return null;
  var amenityId = amenities.first.id;
  var flatId = flats.first.$1;
  var startsAt = DateTime.now().add(const Duration(days: 1));
  var endsAt = startsAt.add(const Duration(hours: 2));
  final guests = TextEditingController(text: '10');
  final note = TextEditingController();
  String? error;
  String? busyKey;
  Future<List<(DateTime, DateTime, String)>>? busy;
  var lastSlots = const <(DateTime, DateTime, String)>[];
  bool clashes(List<(DateTime, DateTime, String)> slots) =>
      slots.any((s) => startsAt.isBefore(s.$2) && endsAt.isAfter(s.$1));
  final hm = DateFormat('h:mm a');
  final draft = await showDialog<_BookingDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Request amenity booking'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: amenityId,
                  decoration: const InputDecoration(labelText: 'Amenity'),
                  items: [
                    for (final amenity in amenities)
                      DropdownMenuItem(
                        value: amenity.id,
                        child: Text('${amenity.name} · ${amenity.fee == 0 ? 'No fee' : inr.format(amenity.fee)}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => amenityId = value ?? amenityId),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: flatId,
                  decoration: const InputDecoration(labelText: 'Flat'),
                  items: [for (final flat in flats) DropdownMenuItem(value: flat.$1, child: Text(flat.$2))],
                  onChanged: (value) => setState(() => flatId = value ?? flatId),
                ),
                const SizedBox(height: 12),
                _dateTimeButton(dialogContext, 'Starts', startsAt, (value) => setState(() => startsAt = value)),
                _dateTimeButton(dialogContext, 'Ends', endsAt, (value) => setState(() => endsAt = value)),
                Builder(
                  builder: (_) {
                    final key = '$amenityId|${DateUtils.dateOnly(startsAt)}';
                    if (key != busyKey) {
                      busyKey = key;
                      busy = AmenitiesRepo.busySlots(
                        amenityId,
                        DateUtils.dateOnly(startsAt),
                      ).catchError((_) => <(DateTime, DateTime, String)>[]);
                    }
                    return FutureBuilder(
                      future: busy,
                      builder: (_, snap) {
                        if (!snap.hasData) return const LinearProgressIndicator();
                        lastSlots = snap.data!;
                        final clash = clashes(lastSlots);
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                lastSlots.isEmpty
                                    ? 'No bookings on ${dateFmt.format(startsAt)} – the whole day is free'
                                    : 'Already booked on ${dateFmt.format(startsAt)}:',
                              ),
                              for (final s in lastSlots) Text('• ${hm.format(s.$1)} – ${hm.format(s.$2)} (${s.$3})'),
                              const SizedBox(height: 4),
                              Pill(
                                clash ? 'Selected time clashes with a booking' : 'Selected time is available',
                                color: clash ? AppColors.red : AppColors.green,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                TextField(
                  controller: guests,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 5,
                  decoration: const InputDecoration(labelText: 'Expected guests'),
                ),
                TextField(
                  controller: note,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note / event type'),
                ),
                if (error != null) Align(alignment: Alignment.centerLeft, child: Text(error!)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final guestCount = int.tryParse(guests.text.trim());
              if (guestCount == null || guestCount <= 0) {
                return setState(() => error = 'Enter at least one expected guest');
              }
              if (endsAt.isBefore(startsAt) || endsAt.isAtSameMomentAs(startsAt))
                return setState(() => error = 'End time must be after start time');
              if (clashes(lastSlots)) return setState(() => error = 'That time is already booked. Choose a free slot.');
              Navigator.pop(
                dialogContext,
                _BookingDraft(
                  amenityId: amenityId,
                  flatId: flatId,
                  startsAt: startsAt,
                  endsAt: endsAt,
                  guestCount: guestCount,
                  note: note.text.trim(),
                ),
              );
            },
            child: const Text('Send for approval'),
          ),
        ],
      ),
    ),
  );
  guests.dispose();
  note.dispose();
  return draft;
}

Widget _dateTimeButton(BuildContext context, String label, DateTime value, void Function(DateTime) onSelected) =>
    TextButton.icon(
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateUtils.dateOnly(DateTime.now()),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value));
        if (time != null) onSelected(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      icon: const Icon(Icons.event_outlined),
      label: Text('$label · ${dateTimeFmt.format(value)}'),
    );

Color _bookingColor(AmenityBookingStatus status) => switch (status) {
  AmenityBookingStatus.approved => AppColors.green,
  AmenityBookingStatus.pending => AppColors.amber,
  AmenityBookingStatus.rejected || AmenityBookingStatus.cancelled => AppColors.red,
  AmenityBookingStatus.completed => Colors.blueGrey,
};

String _paymentLabel(AmenityPaymentStatus status) => switch (status) {
  AmenityPaymentStatus.unpaid => 'Unpaid',
  AmenityPaymentStatus.paid => 'Paid',
  AmenityPaymentStatus.waived => 'Waived',
  AmenityPaymentStatus.refunded => 'Refunded',
};
