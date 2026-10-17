import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/match_post_model.dart';
import 'dio_client.dart';

part 'feed_remote_source.g.dart';

/// Pulls the human-readable error string out of a Dio exception. Backend
/// shape is `{"error": "...", "success": false}` for 4xx responses; we use
/// that when present, fall back to status-based defaults otherwise.
String friendlyDioError(Object e, {String fallback = 'Something went wrong'}) {
  if (e is! DioException) return fallback;
  final data = e.response?.data;
  if (data is Map && data['error'] is String) {
    return data['error'] as String;
  }
  switch (e.response?.statusCode) {
    case 401:
      return 'Please sign in again';
    case 403:
      return 'Not allowed';
    case 404:
      return 'Not found';
    case 409:
      return 'Conflict — try again in a moment';
    case 500:
    case 502:
    case 503:
      return 'Server hiccup — try again';
    default:
      return e.message ?? fallback;
  }
}

@riverpod
FeedRemoteSource feedRemoteSource(Ref ref) =>
    FeedRemoteSource(ref.watch(dioProvider));

class FeedRemoteSource {
  FeedRemoteSource(this._dio);
  final Dio _dio;

  Future<({List<MatchPost> posts, int total})> listFeed({
    int page = 1,
    int limit = 20,
    double? lat,
    double? lng,
    double radius = 10,
    String? postType,
  }) async {
    final resp = await _dio.get('/feed', queryParameters: {
      'page': page,
      'limit': limit,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (lat != null) 'radius': radius,
      if (postType != null && postType.isNotEmpty) 'post_type': postType,
    });
    final data = resp.data?['data'] as List? ?? [];
    final meta = resp.data?['meta'] as Map<String, dynamic>? ?? {};
    return (
      posts: data
          .map((e) => MatchPost.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (meta['total'] as int?) ?? 0,
    );
  }

  /// Create a match post anchored to a Turfinn pitch + slot.
  /// Server validates pitch + slot availability and computes per-head cost.
  Future<String> createPost({
    required String pitchId,
    required String title,
    required DateTime matchDate,
    required int spotsTotal,
    String description = '',
    String postType = 'open_match',
    int? durationMinutes,
    String? format,
  }) async {
    final resp = await _dio.post('/feed', data: {
      'pitch_id': pitchId,
      'title': title,
      'description': description,
      'match_date': matchDate.toUtc().toIso8601String(),
      'spots_total': spotsTotal,
      'post_type': postType,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (format != null && format.isNotEmpty) 'format': format,
    });
    return resp.data['data']['id'] as String;
  }

  Future<MatchPost> getPost(String id) async {
    final resp = await _dio.get('/feed/$id');
    return MatchPost.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  /// `scope`: "all" | "hosted" | "joined" | "upcoming" | "past".
  Future<({List<MatchPost> posts, int total})> listMine({
    String scope = 'upcoming',
    int page = 1,
    int limit = 20,
  }) async {
    final resp = await _dio.get('/feed/mine', queryParameters: {
      'scope': scope,
      'page': page,
      'limit': limit,
    });
    final data = resp.data?['data'] as List? ?? [];
    final meta = resp.data?['meta'] as Map<String, dynamic>? ?? {};
    return (
      posts: data
          .map((e) => MatchPost.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (meta['total'] as int?) ?? 0,
    );
  }

  Future<void> joinPost(String id) async {
    await _dio.post('/feed/$id/join');
  }

  /// Opens an SSL gateway session and returns the redirect URL the client
  /// should navigate to. Backend creates a pending payment row and routes
  /// to /api/v1/payment/match/{success,fail,cancel,ipn} on completion.
  Future<({String redirectUrl, String transactionId})> initiateJoinPayment(
      String id) async {
    final resp = await _dio.post('/feed/$id/initiate-payment');
    final data = resp.data['data'] as Map<String, dynamic>;
    return (
      redirectUrl: data['redirect_url'] as String,
      transactionId: data['transaction_id'] as String,
    );
  }

  /// Host-cancel: refunds every paid joiner via SSL automatically.
  /// Returns the count of refunds queued.
  Future<int> cancelMatch(String id, {String reason = 'host_cancelled'}) async {
    final resp = await _dio.post('/feed/$id/cancel', data: {'reason': reason});
    return (resp.data['data']['refunds_requested'] as num?)?.toInt() ?? 0;
  }

  /// Joiner-cancel: pulls the user out of a match. Backend queues an SSL
  /// refund automatically if the cancellation falls outside the cutoff
  /// window. Returns ({refundQueued, cutoffMinutes}) so the UI can explain
  /// the outcome.
  Future<({bool refundQueued, int cutoffMinutes})> leaveMatch(String id) async {
    final resp = await _dio.post('/feed/$id/leave');
    final data = (resp.data['data'] as Map?) ?? const {};
    return (
      refundQueued: data['refund_queued'] == true,
      cutoffMinutes: (data['cutoff_minutes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> reportPost(
    String id, {
    required String reason,
    String targetKind = 'post',
    String? note,
  }) async {
    await _dio.post('/feed/$id/report', data: {
      'target_kind': targetKind,
      'reason': reason,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }
}
