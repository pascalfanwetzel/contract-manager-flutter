import 'dart:convert';
import '../../../core/db/db_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SettingsStore {
  Future<Map<String, dynamic>> load() async {
    final db = await DbService.instance.db;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['settings']);
    if (rows.isEmpty) return {};
    try {
      return jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    final db = await DbService.instance.db;
    await db.insert(
      'settings',
      {'key': 'settings', 'value': jsonEncode(data)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
