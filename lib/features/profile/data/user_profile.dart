import 'dart:typed_data';

class UserProfile {
  final String name;
  final String email;
  final String? phone;
  final String locale; // e.g., en-US
  final String timezone; // IANA id or display string
  final String currency; // e.g., EUR
  final String country; // ISO 2-letter
  final String? photoPath; // deprecated: local path to avatar image
  final Uint8List? photoBytes; // avatar stored in DB

  const UserProfile({
    required this.name,
    required this.email,
    this.phone,
    required this.locale,
    required this.timezone,
    required this.currency,
    required this.country,
    this.photoPath,
    this.photoBytes,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? locale,
    String? timezone,
    String? currency,
    String? country,
    String? photoPath,
    Uint8List? photoBytes,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      locale: locale ?? this.locale,
      timezone: timezone ?? this.timezone,
      currency: currency ?? this.currency,
      country: country ?? this.country,
      photoPath: photoPath ?? this.photoPath,
      photoBytes: photoBytes ?? this.photoBytes,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'locale': locale,
        'timezone': timezone,
        'currency': currency,
        'country': country,
        'photoPath': photoPath,
        'photoBytes': photoBytes,
      };

  static UserProfile fromJson(Map<String, dynamic> j) => UserProfile(
        name: (j['name'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        phone: j['phone'] as String?,
        locale: (j['locale'] as String?) ?? 'en-US',
        timezone: (j['timezone'] as String?) ?? 'UTC',
        currency: (j['currency'] as String?) ?? 'EUR',
        country: (j['country'] as String?) ?? 'US',
        photoPath: j['photoPath'] as String?,
        photoBytes: j['photoBytes'] as Uint8List?,
      );
}
