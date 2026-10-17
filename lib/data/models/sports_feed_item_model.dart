import 'package:freezed_annotation/freezed_annotation.dart';

import 'match_event_model.dart';
import 'news_item_model.dart';

part 'sports_feed_item_model.freezed.dart';
part 'sports_feed_item_model.g.dart';

/// Polymorphic envelope for the merged /sports/feed response.
/// `kind` is 'news' or 'match'; exactly one of [news] / [match] is populated.
@freezed
class SportsFeedItem with _$SportsFeedItem {
  const factory SportsFeedItem({
    required String kind,
    NewsItem? news,
    MatchEvent? match,
  }) = _SportsFeedItem;

  factory SportsFeedItem.fromJson(Map<String, dynamic> json) =>
      _$SportsFeedItemFromJson(json);
}
