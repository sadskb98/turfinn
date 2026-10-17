import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/pitch_model.dart';
import '../../models/slot_model.dart';
import 'dio_client.dart';

part 'pitch_remote_source.g.dart';

@riverpod
PitchRemoteSource pitchRemoteSource(PitchRemoteSourceRef ref) =>
    PitchRemoteSource(ref.watch(dioProvider));

class PitchRemoteSource {
  PitchRemoteSource(this._dio);
  final Dio _dio;

  Future<List<PitchModel>> listPitches({
    String? city,
    String? search,
    double? lat,
    double? lng,
    double? radius,
    int page = 1,
    int limit = 20,
  }) async {
    const cacheKey = 'cache_pitches';
    const tsKey = 'cache_pitches_ts';
    try {
      final resp = await _dio.get('/pitches', queryParameters: {
        if (city != null && city.isNotEmpty) 'city': city,
        if (search != null && search.isNotEmpty) 'search': search,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (radius != null && radius > 0) 'radius': radius,
        'page': page,
        'limit': limit,
      });
      final data = resp.data['data'] as List;
      final list = data.map((e) => PitchModel.fromJson(e as Map<String, dynamic>)).toList();
      // Persist to cache (only cache first page with no filters for reliability)
      if (page == 1 && city == null && search == null && lat == null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, jsonEncode(data));
        await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
      }
      return list;
    } catch (_) {
      // Fall back to cached data if < 15 minutes old
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      final ts = prefs.getInt(tsKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (cached != null && age < 15 * 60 * 1000) {
        return (jsonDecode(cached) as List)
            .map((e) => PitchModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      rethrow;
    }
  }

  Future<PitchModel> getPitch(String id) async {
    final resp = await _dio.get('/pitches/$id');
    return PitchModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<List<SlotModel>> getSlots(String pitchId, DateTime date) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final resp = await _dio.get('/pitches/$pitchId/slots', queryParameters: {'date': dateStr});
    final data = resp.data['data'] as List;
    return data.map((e) => SlotModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
