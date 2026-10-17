import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dio_client.dart';

part 'superadmin_remote_source.g.dart';

@riverpod
SuperAdminRemoteSource superAdminRemoteSource(SuperAdminRemoteSourceRef ref) =>
    SuperAdminRemoteSource(ref.watch(dioProvider));

class SuperAdminRemoteSource {
  SuperAdminRemoteSource(this._dio);
  final Dio _dio;

  // ── Business Intelligence ────────────────────────────────────────────────
  Future<Map<String, dynamic>> getNorthStar() async {
    final resp = await _dio.get('/super-admin/north-star');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getCohortRetention({int months = 6}) async {
    final resp = await _dio.get('/super-admin/cohort-retention',
        queryParameters: {'months': months});
    return resp.data['data'] as List<dynamic>;
  }

  Future<List<dynamic>> getFunnel({String? from, String? to}) async {
    final resp = await _dio.get('/super-admin/funnel', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as List<dynamic>;
  }

  Future<List<dynamic>> getRevenueTimeSeries(
      {String period = 'day', String? from, String? to}) async {
    final resp = await _dio.get('/super-admin/revenue', queryParameters: {
      'period': period,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as List<dynamic>;
  }

  // ── Audit Log ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listAuditLog(
      {int page = 1, int limit = 20, String? entityType, String? action}) async {
    final resp = await _dio.get('/super-admin/audit-log', queryParameters: {
      'page': page,
      'limit': limit,
      if (entityType != null) 'entity_type': entityType,
      if (action != null) 'action': action,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Finance ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listLedger(
      {int page = 1, int limit = 20, String? entryType}) async {
    final resp = await _dio.get('/super-admin/ledger', queryParameters: {
      'page': page,
      'limit': limit,
      if (entryType != null) 'entry_type': entryType,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTrialBalance() async {
    final resp = await _dio.get('/super-admin/trial-balance');
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getIncomeStatement(
      {required String from, required String to}) async {
    final resp = await _dio.get('/super-admin/income-statement',
        queryParameters: {'from': from, 'to': to});
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getVATReport({int? year}) async {
    final resp = await _dio.get('/super-admin/vat-report',
        queryParameters: {if (year != null) 'year': year});
    return resp.data['data'] as List<dynamic>;
  }

  // ── Fraud ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listFraudFlags(
      {int page = 1, int limit = 20, String? status}) async {
    final resp = await _dio.get('/super-admin/fraud-flags', queryParameters: {
      'page': page,
      'limit': limit,
      if (status != null) 'status': status,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> updateFraudFlag(String id, String status) async {
    await _dio.put('/super-admin/fraud-flags/$id', data: {'status': status});
  }

  // ── System Control ───────────────────────────────────────────────────────
  Future<List<dynamic>> listRateLimits() async {
    final resp = await _dio.get('/super-admin/rate-limits');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> updateRateLimit(
      String group, int requestsPerMinute, int burst) async {
    await _dio.put('/super-admin/rate-limits/$group',
        data: {'requests_per_minute': requestsPerMinute, 'burst': burst});
  }

  Future<Map<String, dynamic>> listAPIKeys(
      {int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/super-admin/api-keys',
        queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createAPIKey(
      {required String name, String? ownerOrg, String? scopes}) async {
    final resp = await _dio.post('/super-admin/api-keys', data: {
      'name': name,
      if (ownerOrg != null) 'owner_org': ownerOrg,
      if (scopes != null) 'scopes': scopes,
    });
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<void> revokeAPIKey(String id) async {
    await _dio.delete('/super-admin/api-keys/$id');
  }

  // ── Zones & Partners ─────────────────────────────────────────────────────
  Future<List<dynamic>> listZones() async {
    final resp = await _dio.get('/super-admin/zones');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createZone(Map<String, dynamic> data) async {
    await _dio.post('/super-admin/zones', data: data);
  }

  Future<Map<String, dynamic>> listOrganizations(
      {int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/super-admin/organizations',
        queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> createOrganization(Map<String, dynamic> data) async {
    await _dio.post('/super-admin/organizations', data: data);
  }

  Future<void> addOrgCredit(String id, int amountPaisa) async {
    await _dio.post('/super-admin/organizations/$id/credit',
        data: {'amount_paisa': amountPaisa});
  }

  Future<Map<String, dynamic>> listResellers(
      {int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/super-admin/resellers',
        queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> createReseller(Map<String, dynamic> data) async {
    await _dio.post('/super-admin/resellers', data: data);
  }

  // ── Match payments / refunds ──────────────────────────────────────────────

  /// Filter-able refund queue. `refundStatus` accepts `'requested'`,
  /// `'refunded'`, `'refund_failed'`, or `'any'` (= has any refund row).
  Future<Map<String, dynamic>> listMatchPayments({
    String? status,
    String? refundStatus,
    String? q,
    int page = 1,
    int limit = 25,
  }) async {
    final resp = await _dio.get('/super-admin/match-payments', queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
      if (refundStatus != null && refundStatus.isNotEmpty)
        'refund_status': refundStatus,
      if (q != null && q.isNotEmpty) 'q': q,
      'page': page,
      'limit': limit,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// Operator override: re-queue a refund that previously failed. Resets the
  /// attempts counter so the cron will pick it up on the next tick.
  Future<void> retryMatchRefund(String paymentId) async {
    await _dio.post('/super-admin/match-payments/$paymentId/retry-refund');
  }

  /// Operator override: mark refund as completed manually (e.g. settled out
  /// of band via the SSL portal). `note` is appended to refund_ref_id with
  /// a `manual:` prefix for audit.
  Future<void> markMatchRefunded(String paymentId, {String note = ''}) async {
    await _dio.post('/super-admin/match-payments/$paymentId/mark-refunded',
        data: {'note': note});
  }

  /// Cancellation audit log: every cancelled match with refund roll-ups.
  Future<Map<String, dynamic>> listMatchCancellations({
    int page = 1,
    int limit = 25,
  }) async {
    final resp = await _dio.get('/super-admin/match-cancellations',
        queryParameters: {'page': page, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  // ── Turf admin registration ───────────────────────────────────────────

  /// Every user with role=manager. Returns the raw map list — the panel
  /// view renders `name`, `phone`, `created_at` directly.
  Future<List<dynamic>> listManagers() async {
    final resp = await _dio.get('/super-admin/managers');
    return (resp.data['data'] as List<dynamic>?) ?? [];
  }

  /// Create a manager record (or promote an existing player). The newly
  /// created manager logs in via OTP at the manager panel — no password
  /// or invitation flow needed from us.
  Future<Map<String, dynamic>> createManager(
      {required String name, required String phone}) async {
    final resp = await _dio.post('/super-admin/managers',
        data: {'name': name, 'phone': phone});
    return resp.data['data'] as Map<String, dynamic>;
  }

  // ── Pitch pricing (Aviv plan + Premium ERP) ─────────────────────────────

  /// Update the per-pitch pricing surface. Any field can be left null to
  /// preserve current values; pass empty/zero strings to clear overrides.
  Future<void> setPitchPricing(
    String pitchId, {
    String? plan, // marketplace | erp_only
    int? marketplaceFeeBpsOverride, // -1 to clear
    int? walkinFeeBpsOverride, // -1 to clear
    int? trialExtensionDays,
  }) async {
    await _dio.put('/super-admin/pitches/$pitchId/pricing', data: {
      if (plan != null) 'plan': plan,
      if (marketplaceFeeBpsOverride != null)
        'marketplace_fee_bps_override': marketplaceFeeBpsOverride,
      if (walkinFeeBpsOverride != null)
        'walkin_fee_bps_override': walkinFeeBpsOverride,
      if (trialExtensionDays != null) 'trial_extension_days': trialExtensionDays,
    });
  }

  /// Grant or revoke premium ERP access. Pass null to revoke.
  Future<void> setPitchPremium(String pitchId, {DateTime? until}) async {
    await _dio.put('/super-admin/pitches/$pitchId/premium', data: {
      'until': until?.toUtc().toIso8601String(),
    });
  }

  /// Toggle an add-on subscription for a pitch.
  /// `kind` ∈ {marketing_boost, match_guarantee_insurance, bulk_sms}
  /// `action` ∈ {enable, disable}
  Future<void> togglePitchAddon(
      String pitchId, String kind, String action) async {
    await _dio.post('/super-admin/pitches/$pitchId/addons/$kind/$action');
  }
}
