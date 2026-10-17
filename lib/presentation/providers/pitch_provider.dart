import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/pitch_model.dart';
import '../../data/models/slot_model.dart';
import '../../data/sources/remote/pitch_remote_source.dart';

part 'pitch_provider.g.dart';

@Riverpod(keepAlive: true)
Future<List<PitchModel>> pitchList(
  PitchListRef ref, {
  String? city,
  String? search,
  double? lat,
  double? lng,
  double? radius,
}) async {
  return ref.watch(pitchRemoteSourceProvider).listPitches(
    city: city,
    search: search,
    lat: lat,
    lng: lng,
    radius: radius,
  );
}

@riverpod
Future<PitchModel> pitchDetail(PitchDetailRef ref, String id) async {
  return ref.watch(pitchRemoteSourceProvider).getPitch(id);
}

@riverpod
Future<List<SlotModel>> pitchSlots(PitchSlotsRef ref, String pitchId, DateTime date) async {
  return ref.watch(pitchRemoteSourceProvider).getSlots(pitchId, date);
}
