import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/gamification_models.dart';
import 'dio_client.dart';

part 'gamification_remote_source.g.dart';

@riverpod
GamificationRemoteSource gamificationRemoteSource(GamificationRemoteSourceRef ref) =>
    GamificationRemoteSource(ref.watch(dioProvider));

class GamificationRemoteSource {
  GamificationRemoteSource(this._dio);
  final Dio _dio;

  Future<PlayerProfile> getProfile() async {
    final resp = await _dio.get('/profile');
    return PlayerProfile.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<int> getWalletBalance() async {
    final resp = await _dio.get('/wallet');
    return (resp.data['data']['balance'] as num).toInt();
  }

  /// Dev/test top-up — credits the wallet directly without going through a
  /// payment gateway. Real money path will replace this with an SSLCommerz
  /// session in a follow-up.
  Future<void> topUpWallet(int amount) async {
    await _dio.post('/wallet/topup', data: {'amount': amount});
  }

  Future<CheckinStatus> getCheckinStatus() async {
    final resp = await _dio.get('/checkin/status');
    return CheckinStatus.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<CheckinResult> checkin() async {
    final resp = await _dio.post('/checkin');
    return CheckinResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<List<Challenge>> getChallenges() async {
    final resp = await _dio.get('/challenges');
    final data = resp.data['data'] as List;
    return data.map((e) => Challenge.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LeaderboardResult> getLeaderboard() async {
    final resp = await _dio.get('/leaderboard');
    return LeaderboardResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<LeaderboardResult> getPreviousLeaderboard() async {
    final resp = await _dio.get('/leaderboard/previous');
    return LeaderboardResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<ReferralInfo> getReferralInfo() async {
    final resp = await _dio.get('/referral');
    return ReferralInfo.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<void> applyReferralCode(String code) async {
    await _dio.post('/referral/apply', data: {'code': code});
  }

  Future<void> buyStreakFreeze() async {
    await _dio.post('/store/streak-freeze');
  }
}
