import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/team_model.dart';
import '../../data/sources/remote/team_remote_source.dart';

part 'team_provider.g.dart';

@riverpod
Future<List<TeamModel>> myTeams(MyTeamsRef ref) async {
  return ref.watch(teamRemoteSourceProvider).listMyTeams();
}

@riverpod
Future<TeamModel> teamDetail(TeamDetailRef ref, String teamId) async {
  return ref.watch(teamRemoteSourceProvider).getTeam(teamId);
}
