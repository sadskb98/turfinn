class UserModel {
  final String id;
  final String phone;
  final String name;
  final String avatarUrl;
  final String position;
  final String skillLevel;
  final String role;

  const UserModel({
    required this.id,
    required this.phone,
    required this.name,
    required this.avatarUrl,
    required this.position,
    required this.skillLevel,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        phone: json['phone'] as String,
        name: (json['name'] as String?) ?? '',
        avatarUrl: (json['avatar_url'] as String?) ?? '',
        position: (json['position'] as String?) ?? '',
        skillLevel: (json['skill_level'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'player',
      );

  UserModel copyWith({
    String? name,
    String? avatarUrl,
    String? position,
    String? skillLevel,
  }) =>
      UserModel(
        id: id,
        phone: phone,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        position: position ?? this.position,
        skillLevel: skillLevel ?? this.skillLevel,
        role: role,
      );
}
