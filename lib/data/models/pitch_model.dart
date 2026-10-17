class PitchModel {
  final String id;
  final String name;
  final String description;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final double pricePerHour;
  final String surface;
  final int capacity;
  final String imageUrls;
  final bool isActive;
  final double? serviceRadiusKm;
  final double? distanceKm;

  /// Pitch's payment-mode preferences. Drives the booking UI toggle —
  /// owners who don't take full online payment force partial_online here.
  final bool allowsPartialPayment;
  final bool allowsFullPayment;
  final String defaultPaymentMode;

  const PitchModel({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.pricePerHour,
    required this.surface,
    required this.capacity,
    required this.imageUrls,
    required this.isActive,
    this.serviceRadiusKm,
    this.distanceKm,
    this.allowsPartialPayment = true,
    this.allowsFullPayment = true,
    this.defaultPaymentMode = 'partial_online',
  });

  factory PitchModel.fromJson(Map<String, dynamic> json) => PitchModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        address: json['address'] as String,
        city: json['city'] as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        pricePerHour: (json['price_per_hour'] as num).toDouble(),
        surface: (json['surface'] as String?) ?? '',
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
        imageUrls: (json['image_urls'] as String?) ?? '',
        isActive: (json['is_active'] as bool?) ?? true,
        serviceRadiusKm: (json['service_radius_km'] as num?)?.toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        allowsPartialPayment:
            (json['allows_partial_payment'] as bool?) ?? true,
        allowsFullPayment: (json['allows_full_payment'] as bool?) ?? true,
        defaultPaymentMode:
            (json['default_payment_mode'] as String?) ?? 'partial_online',
      );

  String get primaryImage {
    if (imageUrls.isEmpty) return '';
    return imageUrls.split(',').first.trim();
  }

  String get distanceLabel {
    if (distanceKm == null) return '';
    if (distanceKm! < 1) return '${(distanceKm! * 1000).round()}m';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }
}
