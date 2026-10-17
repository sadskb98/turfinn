import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/booking_model.dart';
import 'dio_client.dart';

part 'booking_remote_source.g.dart';

@riverpod
BookingRemoteSource bookingRemoteSource(BookingRemoteSourceRef ref) =>
    BookingRemoteSource(ref.watch(dioProvider));

class BookingRemoteSource {
  BookingRemoteSource(this._dio);
  final Dio _dio;

  /// Create a booking. `paymentMode`:
  ///   - `null` / `''` — pitch's default applies
  ///   - `'full_online'` — SSL collects total
  ///   - `'partial_online'` — SSL collects only Turfinn commission; rest as cash at venue
  Future<BookingModel> createBooking({
    required String pitchId,
    required DateTime startsAt,
    required DateTime endsAt,
    String notes = '',
    String? paymentMode,
  }) async {
    final resp = await _dio.post('/bookings', data: {
      'pitch_id': pitchId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'notes': notes,
      if (paymentMode != null && paymentMode.isNotEmpty)
        'payment_mode': paymentMode,
    });
    return BookingModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<List<BookingModel>> listMyBookings({int page = 1, int limit = 20}) async {
    const cacheKey = 'cache_bookings';
    const tsKey = 'cache_bookings_ts';
    try {
      final resp = await _dio.get('/bookings/me', queryParameters: {'page': page, 'limit': limit});
      final data = resp.data['data'] as List;
      final list = data.map((e) => BookingModel.fromJson(e as Map<String, dynamic>)).toList();
      // Persist to cache (only cache first page)
      if (page == 1) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, jsonEncode(data));
        await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
      }
      return list;
    } catch (_) {
      // Fall back to cached data if < 5 minutes old
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      final ts = prefs.getInt(tsKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (cached != null && age < 5 * 60 * 1000) {
        return (jsonDecode(cached) as List)
            .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      rethrow;
    }
  }

  Future<void> cancelBooking(String id) async {
    await _dio.delete('/bookings/$id');
  }

  /// Initiate a split-pay booking. The captain pays only their share via
  /// the returned [gatewayUrl]; friends pay through the [token]'s public
  /// page. Booking auto-confirms when all shares hit, auto-cancels (with
  /// refunds) at [deadlineAt] otherwise.
  Future<SplitInitiateResult> initiateSplit({
    required String pitchId,
    required DateTime startsAt,
    required DateTime endsAt,
    required int totalShares,
    String notes = '',
  }) async {
    final resp = await _dio.post('/bookings/split', data: {
      'pitch_id': pitchId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'total_shares': totalShares,
      'notes': notes,
    });
    final m = resp.data['data'] as Map<String, dynamic>;
    return SplitInitiateResult(
      bookingId: m['booking_id'] as String,
      token: m['token'] as String,
      gatewayUrl: m['gateway_url'] as String,
      deadlineAt: DateTime.parse(m['deadline_at'] as String),
      perSharePaisa: (m['per_share_paisa'] as num).toInt(),
    );
  }

  /// Public split-status read — same data the magic link page sees, used
  /// by the captain's SplitStatusScreen to poll progress.
  Future<Map<String, dynamic>> getSplitByToken(String token) async {
    final resp = await _dio.get('/split/$token');
    return resp.data['data'] as Map<String, dynamic>;
  }
}

class SplitInitiateResult {
  const SplitInitiateResult({
    required this.bookingId,
    required this.token,
    required this.gatewayUrl,
    required this.deadlineAt,
    required this.perSharePaisa,
  });
  final String bookingId;
  final String token;
  final String gatewayUrl;
  final DateTime deadlineAt;
  final int perSharePaisa;
}
