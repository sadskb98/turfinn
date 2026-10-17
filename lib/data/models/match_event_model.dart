import 'package:freezed_annotation/freezed_annotation.dart';

part 'match_event_model.freezed.dart';
part 'match_event_model.g.dart';

@freezed
class MatchEvent with _$MatchEvent {
  const factory MatchEvent({
    required String id,
    required String source,
    @Default('') String league,
    @JsonKey(name: 'league_logo') @Default('') String leagueLogo,
    @JsonKey(name: 'home_team') required String homeTeam,
    @JsonKey(name: 'home_logo') @Default('') String homeLogo,
    @JsonKey(name: 'away_team') required String awayTeam,
    @JsonKey(name: 'away_logo') @Default('') String awayLogo,
    @JsonKey(name: 'home_score') int? homeScore,
    @JsonKey(name: 'away_score') int? awayScore,
    @JsonKey(name: 'kickoff_at') required DateTime kickoffAt,
    required String status, // 'live'|'scheduled'|'finished'
    @JsonKey(name: 'minute_played') int? minutePlayed,
  }) = _MatchEvent;

  factory MatchEvent.fromJson(Map<String, dynamic> json) =>
      _$MatchEventFromJson(json);
}
