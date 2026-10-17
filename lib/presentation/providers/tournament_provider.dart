import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/tournament_model.dart';
import '../../data/sources/remote/tournament_remote_source.dart';

part 'tournament_provider.g.dart';

@riverpod
class TournamentList extends _$TournamentList {
  int _page = 1;
  bool _hasMore = true;

  @override
  Future<List<TournamentModel>> build() async {
    _page = 1;
    _hasMore = true;
    final items = await ref.watch(tournamentRemoteSourceProvider).list(page: 1);
    _hasMore = items.length >= 20;
    return items;
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    final current = state.valueOrNull;
    if (current == null) return;
    _page++;
    final next =
        await ref.read(tournamentRemoteSourceProvider).list(page: _page);
    _hasMore = next.length >= 20;
    state = AsyncData([...current, ...next]);
  }

  bool get hasMore => _hasMore;
}

@riverpod
Future<TournamentDetail> tournamentDetail(
    TournamentDetailRef ref, String id) async {
  return ref.watch(tournamentRemoteSourceProvider).get(id);
}

@riverpod
class TournamentNotifier extends _$TournamentNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<TournamentModel?> create({
    required String name,
    required String format,
    required int maxTeams,
    String description = '',
    int entryFee = 0,
    int minCoins = 0,
    String visibility = 'public',
    String? startsAt,
  }) async {
    state = const AsyncLoading();
    try {
      final t = await ref.read(tournamentRemoteSourceProvider).create(
            name: name,
            format: format,
            maxTeams: maxTeams,
            description: description,
            entryFee: entryFee,
            minCoins: minCoins,
            visibility: visibility,
            startsAt: startsAt,
          );
      state = const AsyncData(null);
      ref.invalidate(tournamentListProvider);
      return t;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return null;
    }
  }

  Future<bool> join(String tournamentId, String teamId,
      {String? inviteCode}) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(tournamentRemoteSourceProvider)
          .join(tournamentId, teamId, inviteCode: inviteCode);
      state = const AsyncData(null);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<String?> start(String tournamentId) async {
    state = const AsyncLoading();
    try {
      await ref.read(tournamentRemoteSourceProvider).start(tournamentId);
      state = const AsyncData(null);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return null;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      if (e is DioException && e.response?.data is Map) {
        final msg = (e.response!.data as Map)['error'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
      return 'Failed to start tournament';
    }
  }

  Future<bool> cancel(String tournamentId) async {
    state = const AsyncLoading();
    try {
      await ref.read(tournamentRemoteSourceProvider).cancel(tournamentId);
      state = const AsyncData(null);
      ref.invalidate(tournamentListProvider);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> leave(String tournamentId, String teamId) async {
    state = const AsyncLoading();
    try {
      await ref.read(tournamentRemoteSourceProvider).leave(tournamentId, teamId);
      state = const AsyncData(null);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> reportScore(
      String tournamentId, String matchId, int homeScore, int awayScore) async {
    try {
      await ref
          .read(tournamentRemoteSourceProvider)
          .reportScore(tournamentId, matchId, homeScore, awayScore);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> confirmScore(String tournamentId, String matchId) async {
    try {
      await ref
          .read(tournamentRemoteSourceProvider)
          .confirmScore(tournamentId, matchId);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> disputeScore(
      String tournamentId, String matchId, String reason) async {
    try {
      await ref
          .read(tournamentRemoteSourceProvider)
          .disputeScore(tournamentId, matchId, reason);
      ref.invalidate(tournamentDetailProvider(tournamentId));
      return true;
    } catch (e) {
      return false;
    }
  }
}
