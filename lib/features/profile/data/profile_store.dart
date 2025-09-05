import '../../../core/db/db_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'user_profile.dart';
import 'dart:typed_data';

class ProfileStore {
  Future<UserProfile?> load() async {
    final db = await DbService.instance.db;
    final rows = await db.query('profile', where: 'id = ?', whereArgs: ['me']);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return UserProfile(
      name: (r['name'] as String?) ?? '',
      email: (r['email'] as String?) ?? '',
      phone: r['phone'] as String?,
      locale: (r['locale'] as String?) ?? 'en-US',
      timezone: (r['timezone'] as String?) ?? 'UTC',
      currency: (r['currency'] as String?) ?? 'EUR',
      country: (r['country'] as String?) ?? 'US',
      photoPath: r['photo_path'] as String?,
      photoBytes: r['photo'] as Uint8List?,
    );
  }

  Future<void> save(UserProfile profile) async {
    final db = await DbService.instance.db;
    await db.insert(
      'profile',
      {
        'id': 'me',
        'name': profile.name,
        'email': profile.email,
        'phone': profile.phone,
        'locale': profile.locale,
        'timezone': profile.timezone,
        'currency': profile.currency,
        'country': profile.country,
        'photo_path': profile.photoPath,
        'photo': profile.photoBytes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
