import 'package:freezed_annotation/freezed_annotation.dart';

part 'tournament_model.freezed.dart';
part 'tournament_model.g.dart';

@freezed
class TournamentModel with _$TournamentModel {
  const factory TournamentModel({
    required String id,
    @Default('') @JsonKey(name: 'creator_id') String creatorId,
    @Default('') @JsonKey(name: 'creator_name') String creatorName,
    required String name,
    @Default('') String description,
    required String format,
    @Default(8) @JsonKey(name: 'max_teams') int maxTeams,
    @Default(0) @JsonKey(name: 'entry_fee') int entryFee,
    @Default(0) @JsonKey(name: 'min_coins') int minCoins,
    @Default(0) @JsonKey(name: 'prize_pool') int prizePool,
    @Default('public') String visibility,
    @JsonKey(name: 'invite_code') String? inviteCode,
    @Default('draft') String status,
    @Default(0) @JsonKey(name: 'team_count') int teamCount,
    @JsonKey(name: 'starts_at') String? startsAt,
    @Default('') @JsonKey(name: 'created_at') String createdAt,
  }) = _TournamentModel;

  factory TournamentModel.fromJson(Map<String, dynamic> json) =>
      _$TournamentModelFromJson(json);
}

@freezed
class TournamentDetail with _$TournamentDetail {
  const factory TournamentDetail({
    required String id,
    @Default('') @JsonKey(name: 'creator_id') String creatorId,
    @Default('') @JsonKey(name: 'creator_name') String creatorName,
    required String name,
    @Default('') String description,
    required String format,
    @Default(8) @JsonKey(name: 'max_teams') int maxTeams,
    @Default(0) @JsonKey(name: 'entry_fee') int entryFee,
    @Default(0) @JsonKey(name: 'min_coins') int minCoins,
    @Default(0) @JsonKey(name: 'prize_pool') int prizePool,
    @Default('public') String visibility,
    @JsonKey(name: 'invite_code') String? inviteCode,
    @Default('draft') String status,
    @Default(0) @JsonKey(name: 'team_count') int teamCount,
    @JsonKey(name: 'starts_at') String? startsAt,
    @Default('') @JsonKey(name: 'created_at') String createdAt,
    @Default([]) List<TournamentTeam> teams,
    @Default([]) List<TournamentMatch> matches,
  }) = _TournamentDetail;

  factory TournamentDetail.fromJson(Map<String, dynamic> json) =>
      _$TournamentDetailFromJson(json);
}

@freezed
class TournamentTeam with _$TournamentTeam {
  const factory TournamentTeam({
    required String id,
    @Default('') @JsonKey(name: 'team_id') String teamId,
    @Default('') @JsonKey(name: 'team_name') String teamName,
    @Default('') @JsonKey(name: 'team_format') String teamFormat,
    @Default('') @JsonKey(name: 'captain_id') String captainId,
    int? seed,
    @Default(false) bool eliminated,
    @Default('') @JsonKey(name: 'registered_at') String registeredAt,
  }) = _TournamentTeam;

  factory TournamentTeam.fromJson(Map<String, dynamic> json) =>
      _$TournamentTeamFromJson(json);
}

@freezed
class TournamentMatch with _$TournamentMatch {
  const factory TournamentMatch({
    required String id,
    required int round,
    @Default(0) @JsonKey(name: 'match_order') int matchOrder,
    @JsonKey(name: 'home_team_id') String? homeTeamId,
    @JsonKey(name: 'home_team_name') String? homeTeamName,
    @JsonKey(name: 'away_team_id') String? awayTeamId,
    @JsonKey(name: 'away_team_name') String? awayTeamName,
    @JsonKey(name: 'home_score') int? homeScore,
    @JsonKey(name: 'away_score') int? awayScore,
    @JsonKey(name: 'winner_id') String? winnerId,
    @JsonKey(name: 'winner_name') String? winnerName,
    @Default('pending') String status,
    @JsonKey(name: 'scheduled_at') String? scheduledAt,
  }) = _TournamentMatch;

  factory TournamentMatch.fromJson(Map<String, dynamic> json) =>
      _$TournamentMatchFromJson(json);
}
