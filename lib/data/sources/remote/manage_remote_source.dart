import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'manage_dio_client.dart';

part 'manage_remote_source.g.dart';

@riverpod
ManageRemoteSource manageRemoteSource(ManageRemoteSourceRef ref) =>
    ManageRemoteSource(ref.watch(manageDioProvider));

class ManageRemoteSource {
  ManageRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> getDashboard() async {
    final resp = await _dio.get('/manage/dashboard');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listMyPitches() async {
    final resp = await _dio.get('/manage/pitches');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createPitch(Map<String, dynamic> data) async {
    await _dio.post('/manage/pitches', data: data);
  }

  Future<void> updatePitch(String id, Map<String, dynamic> data) async {
    await _dio.put('/manage/pitches/$id', data: data);
  }

  Future<void> togglePitch(String id) async {
    await _dio.put('/manage/pitches/$id/toggle');
  }

  Future<Map<String, dynamic>> listBookings({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/manage/bookings', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> confirmBooking(String id) async {
    await _dio.put('/manage/bookings/$id/confirm');
  }

  Future<void> cancelBooking(String id) async {
    await _dio.put('/manage/bookings/$id/cancel');
  }

  // ── Manager Analytics & Financials ────────────────────────────────────
  Future<Map<String, dynamic>> getManagerSummary({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/summary', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getManagerRevenueChart({int days = 30}) async {
    final resp = await _dio.get('/manager/analytics/revenue-chart', queryParameters: {'days': days});
    return (resp.data['data'] as Map<String, dynamic>)['daily'] as List<dynamic>;
  }

  Future<List<dynamic>> getManagerPitchBreakdown({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/pitch-breakdown', queryParameters: {'period': period});
    return resp.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getManagerBookings({int page = 1, int limit = 20, String? status, String? source}) async {
    final resp = await _dio.get('/manager/bookings', queryParameters: {
      'page': page, 'limit': limit,
      if (status != null && status.isNotEmpty) 'status': status,
      if (source != null && source.isNotEmpty) 'source': source,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> createWalkInBooking(Map<String, dynamic> data) async {
    await _dio.post('/manager/bookings', data: data);
  }

  Future<void> updateManagerBookingStatus(String bookingId, String status) async {
    await _dio.put('/manager/bookings/$bookingId/status', data: {'status': status});
  }

  Future<Map<String, dynamic>> getManagerFinancials({String? from, String? to}) async {
    final resp = await _dio.get('/manager/financials', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as Map<String, dynamic>;
  }

  // ── Enhanced Analytics ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getManagerHeatmap({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/heatmap', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getManagerPeakHours({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/peak-hours', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getManagerCustomerInsights({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/customers', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  // ── Enhanced Financials ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getManagerDailyLedger({String? from, String? to}) async {
    final resp = await _dio.get('/manager/financials/ledger', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getManagerPitchPnL({String? from, String? to}) async {
    final resp = await _dio.get('/manager/financials/pitch-pnl', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as List<dynamic>;
  }

  // ── Manager Campaigns (Promo Codes) ─────────────────────────────────
  Future<List<dynamic>> listManagerPromos() async {
    final resp = await _dio.get('/manager/promos');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createManagerPromo(Map<String, dynamic> data) async {
    await _dio.post('/manager/promos', data: data);
  }

  Future<void> deactivateManagerPromo(String id) async {
    await _dio.put('/manager/promos/$id/deactivate');
  }

  // ── Smart Pricing ─────────────────────────────────────────────────────
  Future<List<dynamic>> listPricingRules() async {
    final resp = await _dio.get('/manage/pricing-rules');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createPricingRule(Map<String, dynamic> data) async {
    await _dio.post('/manage/pricing-rules', data: data);
  }

  Future<void> deletePricingRule(String id) async {
    await _dio.delete('/manage/pricing-rules/$id');
  }

  Future<void> togglePricingRule(String id) async {
    await _dio.put('/manage/pricing-rules/$id/toggle');
  }

  // ── Auth (OTP) ───────────────────────────────────────────────────────────
  Future<String?> sendOtp(String phone) async {
    final resp = await _dio.post('/auth/send-otp', data: {'phone': phone});
    return resp.data['data']['otp_dev'] as String?;
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    final resp = await _dio.post('/auth/verify-otp', data: {'phone': phone, 'otp': otp});
    return resp.data['data'] as Map<String, dynamic>;
  }

  // ── KYC ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getMyKyc() async {
    try {
      final resp = await _dio.get('/manage/kyc/me');
      return resp.data['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> submitKyc(Map<String, dynamic> data) async {
    await _dio.post('/manage/kyc', data: data);
  }

  // ── File upload ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> presignUpload(String bucket, String filename) async {
    final resp = await _dio.post('/upload/presign', data: {
      'bucket': bucket,
      'filename': filename,
    });
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<void> uploadToPresignUrl(String presignUrl, List<int> bytes, String contentType) async {
    final uploadDio = Dio();
    await uploadDio.put(
      presignUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
    );
  }

  /// Cancellations of matches at any pitch the manager owns. Returns the
  /// audit roll-up shape (joiner_count, refunds_requested, refunds_completed,
  /// refunds_failed) so the manager can flag stuck refunds upstream.
  Future<Map<String, dynamic>> listMatchCancellations({
    int page = 1,
    int limit = 25,
  }) async {
    final resp = await _dio.get('/manager/match-cancellations',
        queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  /// Mark cash as physically collected at the venue for a partial-payment
  /// booking. Idempotent on the backend side.
  Future<void> markCashCollected(String bookingId) async {
    await _dio.post('/manager/bookings/$bookingId/mark-cash-collected');
  }

  // ── Billing (Aviv plan + Premium ERP) ────────────────────────────────────
  Future<Map<String, dynamic>> getMyBilling() async {
    final resp = await _dio.get('/manage/billing');
    return resp.data['data'] as Map<String, dynamic>;
  }
}
