class SlotModel {
  final DateTime startsAt;
  final DateTime endsAt;
  final bool available;

  const SlotModel({
    required this.startsAt,
    required this.endsAt,
    required this.available,
  });

  factory SlotModel.fromJson(Map<String, dynamic> json) => SlotModel(
        startsAt: DateTime.parse((json['start'] ?? json['starts_at']) as String),
        endsAt: DateTime.parse((json['end'] ?? json['ends_at']) as String),
        available: json['available'] as bool,
      );
}
