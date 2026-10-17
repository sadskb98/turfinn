import 'package:freezed_annotation/freezed_annotation.dart';

part 'league_model.freezed.dart';
part 'league_model.g.dart';

@freezed
class League with _$League {
  const factory League({
    required int id,
    required String name,
    @JsonKey(name: 'short_name') required String shortName,
  }) = _League;

  factory League.fromJson(Map<String, dynamic> json) =>
      _$LeagueFromJson(json);
}
