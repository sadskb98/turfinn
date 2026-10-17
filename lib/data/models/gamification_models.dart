import 'package:freezed_annotation/freezed_annotation.dart';

part 'gamification_models.freezed.dart';
part 'gamification_models.g.dart';

@freezed
class PlayerProfile with _$PlayerProfile {
  const factory PlayerProfile({
    required String id,
    @Default('') String name,
    @Default('') String phone,
    @Default('') String role,
    @Default('') @JsonKey(name: 'avatar_url') String avatarUrl,
    @Default(0) int xp,
    @Default(1) int level,
    @Default('Rookie') @JsonKey(name: 'level_title') String levelTitle,
    @Default(0) @JsonKey(name: 'xp_to_next_level') int xpToNextLevel,
    @Default(0) @JsonKey(name: 'coins_balance') int coinsBalance,
    @Default(0) @JsonKey(name: 'total_bookings') int totalBookings,
    @Default(0) @JsonKey(name: 'current_streak') int currentStreak,
    @Default(0) @JsonKey(name: 'longest_streak') int longestStreak,
    @Default(0) @JsonKey(name: 'streak_freezes') int streakFreezes,
    @Default('') @JsonKey(name: 'referral_code') String referralCode,
    @Default([]) List<PlayerBadge> badges,
  }) = _PlayerProfile;

  factory PlayerProfile.fromJson(Map<String, dynamic> json) =>
      _$PlayerProfileFromJson(json);
}

@freezed
class PlayerBadge with _$PlayerBadge {
  const factory PlayerBadge({
    required String key,
    required String name,
    @Default('') String description,
    @JsonKey(name: 'earned_at') String? earnedAt,
  }) = _PlayerBadge;

  factory PlayerBadge.fromJson(Map<String, dynamic> json) =>
      _$PlayerBadgeFromJson(json);
}

@freezed
class CheckinStatus with _$CheckinStatus {
  const factory CheckinStatus({
    @Default(false) @JsonKey(name: 'checked_in_today') bool checkedInToday,
    @Default(0) @JsonKey(name: 'current_day') int currentDay,
    @Default([]) List<bool> cycle,
  }) = _CheckinStatus;

  factory CheckinStatus.fromJson(Map<String, dynamic> json) =>
      _$CheckinStatusFromJson(json);
}

@freezed
class CheckinResult with _$CheckinResult {
  const factory CheckinResult({
    @Default(0) int day,
    @Default(0) @JsonKey(name: 'coins_earned') int coinsEarned,
    @Default([]) List<bool> cycle,
  }) = _CheckinResult;

  factory CheckinResult.fromJson(Map<String, dynamic> json) =>
      _$CheckinResultFromJson(json);
}

@freezed
class Challenge with _$Challenge {
  const factory Challenge({
    required String id,
    required String slug,
    required String title,
    @Default('') String description,
    required String type,
    required int target,
    required String difficulty,
    @Default(0) @JsonKey(name: 'coin_reward') int coinReward,
    @Default(0) @JsonKey(name: 'xp_reward') int xpReward,
    @Default(0) int progress,
    @Default(false) bool completed,
  }) = _Challenge;

  factory Challenge.fromJson(Map<String, dynamic> json) =>
      _$ChallengeFromJson(json);
}

@freezed
class LeaderboardResult with _$LeaderboardResult {
  const factory LeaderboardResult({
    @Default('bronze') String tier,
    @Default('') @JsonKey(name: 'week_start') String weekStart,
    @Default([]) List<LeaderboardEntry> top,
    @Default(0) @JsonKey(name: 'your_rank') int yourRank,
    @Default(0) @JsonKey(name: 'your_xp') int yourXP,
    @Default(0) @JsonKey(name: 'your_reward') int yourReward,
  }) = _LeaderboardResult;

  factory LeaderboardResult.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardResultFromJson(json);
}

@freezed
class LeaderboardEntry with _$LeaderboardEntry {
  const factory LeaderboardEntry({
    @Default(0) int rank,
    @Default('') @JsonKey(name: 'user_id') String userId,
    @Default('') String name,
    @Default('') @JsonKey(name: 'avatar_url') String avatarUrl,
    @Default(0) @JsonKey(name: 'xp_earned') int xpEarned,
    @Default(0) @JsonKey(name: 'reward_coins') int rewardCoins,
  }) = _LeaderboardEntry;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardEntryFromJson(json);
}

@freezed
class ReferralInfo with _$ReferralInfo {
  const factory ReferralInfo({
    @Default('') String code,
    @Default(0) @JsonKey(name: 'total_referrals') int totalReferrals,
    @Default(0) @JsonKey(name: 'total_coins_earned') int totalCoinsEarned,
  }) = _ReferralInfo;

  factory ReferralInfo.fromJson(Map<String, dynamic> json) =>
      _$ReferralInfoFromJson(json);
}
