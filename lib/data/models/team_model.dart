class TeamModel {
  final String id;
  final String name;
  final String code;
  final String format;
  final String formation;
  final String captainId;
  final int maxPlayers;
  final String status;
  final List<TeamMemberModel> members;
  final String createdAt;

  TeamModel({
    required this.id,
    required this.name,
    required this.code,
    required this.format,
    required this.formation,
    required this.captainId,
    required this.maxPlayers,
    required this.status,
    required this.members,
    required this.createdAt,
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) {
    return TeamModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      format: json['format'] as String? ?? '',
      formation: json['formation'] as String? ?? '2-3-1',
      captainId: json['captain_id'] as String? ?? '',
      maxPlayers: json['max_players'] as int? ?? 7,
      status: json['status'] as String? ?? 'forming',
      members: (json['members'] as List<dynamic>?)
              ?.map((m) =>
                  TeamMemberModel.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  int get playerCount => members.where((m) => m.role != 'sub').length;
  bool get isFull => playerCount >= maxPlayers;
  bool get isReady => status == 'ready';
}

class TeamMemberModel {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String position;
  final int number;
  final String role;

  TeamMemberModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    required this.position,
    required this.number,
    required this.role,
  });

  factory TeamMemberModel.fromJson(Map<String, dynamic> json) {
    return TeamMemberModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      position: json['position'] as String? ?? '',
      number: json['number'] as int? ?? 0,
      role: json['role'] as String? ?? 'player',
    );
  }

  String get displayName => name.isNotEmpty ? name : 'Player ${number}';
  bool get isCaptain => role == 'captain';
}

class MatchModel {
  final String id;
  final TeamModel? homeTeam;
  final TeamModel? awayTeam;
  final String format;
  final String status;
  final String? pitchId;
  final String? scheduledAt;
  final String createdAt;

  MatchModel({
    required this.id,
    this.homeTeam,
    this.awayTeam,
    required this.format,
    required this.status,
    this.pitchId,
    this.scheduledAt,
    required this.createdAt,
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    return MatchModel(
      id: json['id'] as String? ?? '',
      homeTeam: json['home_team'] != null
          ? TeamModel.fromJson(json['home_team'] as Map<String, dynamic>)
          : null,
      awayTeam: json['away_team'] != null
          ? TeamModel.fromJson(json['away_team'] as Map<String, dynamic>)
          : null,
      format: json['format'] as String? ?? '',
      status: json['status'] as String? ?? '',
      pitchId: json['pitch_id'] as String?,
      scheduledAt: json['scheduled_at'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  bool get isSearching => status == 'searching';
  bool get isMatched => status == 'matched';
  bool get isConfirmed => status == 'confirmed';
}
