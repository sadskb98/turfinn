import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/user_model.dart';
import '../../data/sources/remote/user_remote_source.dart';

part 'profile_provider.g.dart';

@riverpod
class ProfileNotifier extends _$ProfileNotifier {
  @override
  Future<UserModel?> build() async {
    try {
      return await ref.watch(userRemoteSourceProvider).getMe();
    } catch (_) {
      return null;
    }
  }

  Future<void> updateProfile({
    String? name,
    String? avatarUrl,
    String? position,
    String? skillLevel,
  }) async {
    final updated = await ref.read(userRemoteSourceProvider).updateMe(
          name: name,
          avatarUrl: avatarUrl,
          position: position,
          skillLevel: skillLevel,
        );
    state = AsyncData(updated);
  }

  void refresh() => ref.invalidateSelf();
}
