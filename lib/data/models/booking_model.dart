class BookingModel {
  final String id;
  final String pitchId;
  final String pitchName;
  final DateTime startsAt;
  final DateTime endsAt;
  final double totalCost;
  final String status;
  final String notes;
  final String paymentMode; // 'full_online' | 'partial_online'
  final int cashDuePaisa;
  final int cashCollectedPaisa;

  const BookingModel({
    required this.id,
    required this.pitchId,
    required this.pitchName,
    required this.startsAt,
    required this.endsAt,
    required this.totalCost,
    required this.status,
    required this.notes,
    this.paymentMode = 'full_online',
    this.cashDuePaisa = 0,
    this.cashCollectedPaisa = 0,
  });

  /// Online portion in BDT (what SSL charges).
  double get onlineBDT =>
      paymentMode == 'partial_online'
          ? totalCost - cashDuePaisa / 100.0
          : totalCost;

  /// Cash portion in BDT (paid at the venue).
  double get cashBDT => cashDuePaisa / 100.0;

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    final pitch = json['pitch'] as Map<String, dynamic>?;
    return BookingModel(
      id: json['id'] as String,
      pitchId: json['pitch_id'] as String,
      pitchName: (json['pitch_name'] as String?) ?? pitch?['name'] as String? ?? '',
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      totalCost: (json['total_cost'] as num).toDouble(),
      status: json['status'] as String,
      notes: (json['notes'] as String?) ?? '',
      paymentMode: (json['payment_mode'] as String?) ?? 'full_online',
      cashDuePaisa: (json['cash_due_paisa'] as num?)?.toInt() ?? 0,
      cashCollectedPaisa: (json['cash_collected_paisa'] as num?)?.toInt() ?? 0,
    );
  }
}
