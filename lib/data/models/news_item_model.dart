import 'package:freezed_annotation/freezed_annotation.dart';

part 'news_item_model.freezed.dart';
part 'news_item_model.g.dart';

@freezed
class NewsItem with _$NewsItem {
  const factory NewsItem({
    required String id,
    required String source,
    @Default('') String category,
    required String title,
    @Default('') String summary,
    required String url,
    @JsonKey(name: 'image_url') @Default('') String imageURL,
    @JsonKey(name: 'source_name') @Default('') String sourceName,
    @JsonKey(name: 'published_at') required DateTime publishedAt,
  }) = _NewsItem;

  factory NewsItem.fromJson(Map<String, dynamic> json) =>
      _$NewsItemFromJson(json);
}
