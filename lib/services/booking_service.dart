import 'api_service.dart';

class BookingService {
  /// Creates a booking for the given tutor/time/duration.
  /// Returns the booking id on success.
  static Future<int> createBooking({
    required int tutorId,
    required DateTime startAt,
    required int durationMinutes,
    String? studentNote,
  }) async {
    final body = <String, dynamic>{
      'tutor_id': tutorId,
      'start_at': _toIso8601WithOffset(startAt),
      'duration_minutes': durationMinutes,
      if (studentNote != null && studentNote.trim().isNotEmpty)
        'student_note': studentNote.trim(),
    };
    final result = await ApiService.post('/bookings/', body);
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    final id = payload['id'] ?? payload['booking_id'];
    if (id is num) return id.toInt();
    throw const ApiException('Could not read booking id from response');
  }

  /// Pays the given booking from the student's wallet balance.
  static Future<void> payFromWallet({required int bookingId}) async {
    final body = {'booking_id': bookingId};
    final result = await ApiService.post('/payments/bookings/pay/', body);
  }

  /// Formats [dt] as ISO 8601 with timezone offset (e.g. 2026-03-25T14:00:00+05:00).
  /// The backend rejects naive datetimes.
  static String _toIso8601WithOffset(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');

    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absMin = offset.inMinutes.abs();
    final offH = (absMin ~/ 60).toString().padLeft(2, '0');
    final offM = (absMin % 60).toString().padLeft(2, '0');

    return '$y-$mo-${d}T$h:$mi:$s$sign$offH:$offM';
  }
}
