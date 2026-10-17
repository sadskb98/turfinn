import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dio_client.dart';

part 'admin_remote_source.g.dart';

@riverpod
AdminRemoteSource adminRemoteSource(AdminRemoteSourceRef ref) =>
    AdminRemoteSource(ref.watch(dioProvider));

class AdminRemoteSource {
  AdminRemoteSource(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> getDashboard() async {
    final resp = await _dio.get('/admin/dashboard');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listUsers({int page = 1, int limit = 20, String? search, String? role}) async {
    final resp = await _dio.get('/admin/users', queryParameters: {
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (role != null && role.isNotEmpty) 'role': role,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> updateUserRole(String userId, String role) async {
    await _dio.put('/admin/users/$userId/role', data: {'role': role});
  }

  /// Activate / deactivate a user. Backend hard-blocks for super_admin
  /// targets and for self-deactivation.
  Future<void> setUserActive(String userId, bool active) async {
    await _dio.put('/admin/users/$userId/active', data: {'active': active});
  }

  Future<Map<String, dynamic>> listPitches({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/admin/pitches', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> togglePitch(String pitchId, bool isActive) async {
    await _dio.put('/admin/pitches/$pitchId/toggle', data: {'is_active': isActive});
  }

  Future<void> createPitch(Map<String, dynamic> data) async {
    await _dio.post('/admin/pitches', data: data);
  }

  Future<Map<String, dynamic>> listBookings({int page = 1, int limit = 20, String? status}) async {
    final resp = await _dio.get('/admin/bookings', queryParameters: {
      'page': page,
      'limit': limit,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    await _dio.put('/admin/bookings/$bookingId/status', data: {'status': status});
  }

  Future<Map<String, dynamic>> listTeams({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/admin/teams', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listMatches({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/admin/matches', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  // ── Platform Configuration ─────────────────────────────────────────────
  Future<List<dynamic>> getSettings() async {
    final resp = await _dio.get('/admin/platform/settings');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> updateSettings(List<Map<String, String>> settings) async {
    await _dio.put('/admin/platform/settings', data: {'settings': settings});
  }

  Future<List<dynamic>> getPricingRules() async {
    final resp = await _dio.get('/admin/platform/pricing-rules');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createPricingRule(Map<String, dynamic> data) async {
    await _dio.post('/admin/platform/pricing-rules', data: data);
  }

  Future<void> deletePricingRule(String id) async {
    await _dio.delete('/admin/platform/pricing-rules/$id');
  }

  Future<List<dynamic>> getFlags() async {
    final resp = await _dio.get('/admin/platform/flags');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> updateFlag(String key, bool enabled) async {
    await _dio.put('/admin/platform/flags/$key', data: {'enabled': enabled});
  }

  Future<List<dynamic>> getTemplates() async {
    final resp = await _dio.get('/admin/platform/templates');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createTemplate(Map<String, dynamic> data) async {
    await _dio.post('/admin/platform/templates', data: data);
  }

  Future<void> deleteTemplate(String id) async {
    await _dio.delete('/admin/platform/templates/$id');
  }

  // ── Marketing & Growth ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> listPromoCodes({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/admin/marketing/promo-codes', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> createPromoCode(Map<String, dynamic> data) async {
    await _dio.post('/admin/marketing/promo-codes', data: data);
  }

  Future<void> deactivatePromoCode(String id) async {
    await _dio.put('/admin/marketing/promo-codes/$id/deactivate');
  }

  Future<Map<String, dynamic>> listCampaigns({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/admin/marketing/campaigns', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> createCampaign(Map<String, dynamic> data) async {
    await _dio.post('/admin/marketing/campaigns', data: data);
  }

  Future<void> sendCampaign(String id) async {
    await _dio.post('/admin/marketing/campaigns/$id/send');
  }

  Future<List<dynamic>> listFeaturedPitches() async {
    final resp = await _dio.get('/admin/marketing/featured-pitches');
    return resp.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getReferralStats() async {
    final resp = await _dio.get('/admin/marketing/referral-stats');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> listBanners() async {
    final resp = await _dio.get('/admin/marketing/banners');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createBanner(Map<String, dynamic> data) async {
    await _dio.post('/admin/marketing/banners', data: data);
  }

  Future<void> deleteBanner(String id) async {
    await _dio.delete('/admin/marketing/banners/$id');
  }

  // ── Disputes & Support ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> listDisputes({int page = 1, int limit = 20, String? status}) async {
    final resp = await _dio.get('/admin/disputes', queryParameters: {
      'page': page, 'limit': limit,
      if (status != null) 'status': status,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> resolveDispute(String id, Map<String, dynamic> data) async {
    await _dio.put('/admin/disputes/$id/resolve', data: data);
  }

  Future<Map<String, dynamic>> listTickets({int page = 1, int limit = 20, String? status}) async {
    final resp = await _dio.get('/admin/tickets', queryParameters: {
      'page': page, 'limit': limit,
      if (status != null) 'status': status,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTicket(String id) async {
    final resp = await _dio.get('/admin/tickets/$id');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<void> replyTicket(String id, {required String body, bool isInternal = false}) async {
    await _dio.post('/admin/tickets/$id/reply', data: {'body': body, 'is_internal': isInternal});
  }

  Future<void> assignTicket(String id, String assignedTo) async {
    await _dio.put('/admin/tickets/$id/assign', data: {'assigned_to': assignedTo});
  }

  Future<Map<String, dynamic>> listFlaggedReviews({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/admin/reviews/flagged', queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> moderateReview(String id, {required String action, String? reason}) async {
    await _dio.put('/admin/reviews/$id/moderate', data: {
      'action': action,
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> warnUser(String userId, String reason) async {
    await _dio.post('/admin/user-actions/$userId/warn', data: {'reason': reason});
  }

  Future<void> banUser(String userId) async {
    await _dio.post('/admin/user-actions/$userId/ban');
  }

  Future<void> unbanUser(String userId) async {
    await _dio.post('/admin/user-actions/$userId/unban');
  }

  // ── KYC / Verification ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> listKYC({int page = 1, int limit = 20, String? status}) async {
    final resp = await _dio.get('/admin/kyc', queryParameters: {
      'page': page, 'limit': limit,
      if (status != null) 'status': status,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getKYC(String id) async {
    final resp = await _dio.get('/admin/kyc/$id');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<void> approveKYC(String id) async {
    await _dio.put('/admin/kyc/$id/approve');
  }

  Future<void> rejectKYC(String id, String reason) async {
    await _dio.put('/admin/kyc/$id/reject', data: {'reason': reason});
  }

  // ── Manager Dashboard ─────────────────────────────────────────────────
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
}
