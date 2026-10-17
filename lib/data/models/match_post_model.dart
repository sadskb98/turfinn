import 'package:freezed_annotation/freezed_annotation.dart';

part 'match_post_model.freezed.dart';
part 'match_post_model.g.dart';

@freezed
class MatchPost with _$MatchPost {
  const factory MatchPost({
    required String id,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'author_name') @Default('') String authorName,
    @JsonKey(name: 'pitch_id') String? pitchId,
    @JsonKey(name: 'pitch_name') String? pitchName,
    @JsonKey(name: 'venue_kind') @Default('turfinn') String venueKind,
    required String title,
    @Default('') String description,
    @JsonKey(name: 'match_date') required DateTime matchDate,
    @JsonKey(name: 'duration_minutes') @Default(90) int durationMinutes,
    @Default('') String format,
    @JsonKey(name: 'spots_total') @Default(10) int spotsTotal,
    @JsonKey(name: 'spots_filled') @Default(1) int spotsFilled,
    @JsonKey(name: 'join_fee_bdt') @Default(20) int joinFeeBDT,
    @JsonKey(name: 'per_head_cost_bdt') int? perHeadCostBDT,
    @Default('open') String status,
    @JsonKey(name: 'post_type') @Default('open_match') String postType,
    @Default(0.0) double latitude,
    @Default(0.0) double longitude,
    @JsonKey(name: 'distance_km') double? distanceKm,
    @JsonKey(name: 'is_host') @Default(false) bool isHost,
    @JsonKey(name: 'is_joined') @Default(false) bool isJoined,
    /// Caller's payment row for this match (only populated on /feed/mine
    /// and /feed/:id when the caller has paid). Empty when no payment.
    @JsonKey(name: 'my_payment_status') @Default('') String myPaymentStatus,
    @JsonKey(name: 'my_refund_status') String? myRefundStatus,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _MatchPost;

  factory MatchPost.fromJson(Map<String, dynamic> json) =>
      _$MatchPostFromJson(json);
}
