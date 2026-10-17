import 'package:dio/dio.dart';

const _maptilerKey = '5pNDbr41bwoiIH1bFQro';

class GeocodingService {
  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://api.maptiler.com',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  /// Autocomplete: partial query → up to 5 labelled results (fast, Bangladesh-scoped)
  static Future<List<({String name, double lat, double lng})>> suggest(
      String query) async {
    try {
      final resp = await _dio.get(
        '/geocoding/${Uri.encodeComponent(query)}.json',
        queryParameters: {
          'key': _maptilerKey,
          'language': 'en',
          'country': 'bd',
          'limit': 5,
          'types': 'place,address,poi,neighbourhood',
        },
      );
      final features = resp.data['features'] as List? ?? [];
      return features.map((f) {
        final center = f['center'] as List; // GeoJSON: [lng, lat]
        final name =
            (f['place_name'] as String?) ?? (f['text'] as String? ?? '');
        return (
          name: name,
          lat: (center[1] as num).toDouble(),
          lng: (center[0] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Forward geocode: address string → (lat, lng)
  static Future<({double lat, double lng})?> forward(String address) async {
    final results = await suggest(address);
    if (results.isEmpty) return null;
    final r = results.first;
    return (lat: r.lat, lng: r.lng);
  }

  /// Reverse geocode: (lat, lng) → address components
  static Future<({String address, String city})?> reverse(
      double lat, double lng) async {
    try {
      final resp = await _dio.get(
        '/geocoding/$lng,$lat.json',
        queryParameters: {'key': _maptilerKey, 'language': 'en'},
      );
      final features = resp.data['features'] as List? ?? [];
      if (features.isEmpty) return null;
      final f = features.first;
      final text = (f['text'] as String?) ?? '';
      final context = f['context'] as List? ?? [];
      final city = context
          .where((c) =>
              (c['id'] as String? ?? '').startsWith('place') ||
              (c['id'] as String? ?? '').startsWith('district'))
          .map((c) => c['text'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .firstOrNull ?? '';
      return (address: text, city: city);
    } catch (_) {
      return null;
    }
  }
}
