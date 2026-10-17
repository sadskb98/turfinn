import 'package:freezed_annotation/freezed_annotation.dart';

part 'standings_model.freezed.dart';
part 'standings_model.g.dart';

/// API-Football standings JSON shape (subset we care about).
@freezed
class StandingsResponse with _$StandingsResponse {
  const factory StandingsResponse({
    @JsonKey(name: 'league_id') required int leagueId,
    required int season,
    @JsonKey(name: 'league_name') required String leagueName,
    @JsonKey(name: 'league_logo') @Default('') String leagueLogo,
    @JsonKey(name: 'fetched_at') @Default('') String fetchedAt,
    /// Each top-level entry is a "group" (most leagues have one). Each group
    /// is a list of [StandingRow]. Decoded lazily by the screen.
    @Default(<dynamic>[]) List<dynamic> standings,
  }) = _StandingsResponse;

  factory StandingsResponse.fromJson(Map<String, dynamic> json) =>
      _$StandingsResponseFromJson(json);
}

/// One row in the league table — parsed from the raw API-Football payload.
class StandingRow {
  StandingRow({
    required this.rank,
    required this.teamName,
    required this.teamLogo,
    required this.played,
    required this.win,
    required this.draw,
    required this.lose,
    required this.goalsDiff,
    required this.points,
    this.form,
  });

  final int rank;
  final String teamName;
  final String teamLogo;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsDiff;
  final int points;
  final String? form;

  factory StandingRow.fromMap(Map<String, dynamic> m) {
    final team = (m['team'] as Map?) ?? {};
    final all = (m['all'] as Map?) ?? {};
    return StandingRow(
      rank: (m['rank'] as num?)?.toInt() ?? 0,
      teamName: team['name']?.toString() ?? '',
      teamLogo: team['logo']?.toString() ?? '',
      played: (all['played'] as num?)?.toInt() ?? 0,
      win: (all['win'] as num?)?.toInt() ?? 0,
      draw: (all['draw'] as num?)?.toInt() ?? 0,
      lose: (all['lose'] as num?)?.toInt() ?? 0,
      goalsDiff: (m['goalsDiff'] as num?)?.toInt() ?? 0,
      points: (m['points'] as num?)?.toInt() ?? 0,
      form: m['form']?.toString(),
    );
  }
}
