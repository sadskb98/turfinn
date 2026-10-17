import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/gamification_models.dart';
import '../../data/sources/remote/gamification_remote_source.dart';

part 'gamification_provider.g.dart';

@riverpod
Future<PlayerProfile> playerProfile(PlayerProfileRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getProfile();
}

@riverpod
Future<int> walletBalance(WalletBalanceRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getWalletBalance();
}

@riverpod
Future<CheckinStatus> checkinStatus(CheckinStatusRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getCheckinStatus();
}

@riverpod
Future<List<Challenge>> weeklyChallenges(WeeklyChallengesRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getChallenges();
}

@riverpod
Future<LeaderboardResult> leaderboard(LeaderboardRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getLeaderboard();
}

@riverpod
Future<ReferralInfo> referralInfo(ReferralInfoRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getReferralInfo();
}

@riverpod
class CheckinNotifier extends _$CheckinNotifier {
  @override
  AsyncValue<CheckinResult?> build() => const AsyncData(null);

  Future<void> checkin() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(gamificationRemoteSourceProvider).checkin();
      state = AsyncData(result);
      ref.invalidate(checkinStatusProvider);
      ref.invalidate(playerProfileProvider);
      ref.invalidate(walletBalanceProvider);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }
}
