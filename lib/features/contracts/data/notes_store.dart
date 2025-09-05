import '../../../core/db/db_service.dart';
import '../../../core/cloud/sync_registry.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter/foundation.dart';

class NotesStore {
  Future<Map<String, NoteEntry>> loadAll() async {
    final db = await DbService.instance.db;
    final rows = await db.query('notes');
    debugPrint('[DB] loadAll(notes) count=${rows.length}');
    final out = <String, NoteEntry>{};
    for (final r in rows) {
      out[r['contract_id'] as String] = NoteEntry(
        text: r['text'] as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch((r['updated_at'] as int?) ?? 0),
      );
    }
    return out;
  }

  Future<void> saveNote(String contractId, String text, DateTime updatedAt) async {
    final db = await DbService.instance.db;
    final ts = await DbService.instance.nextLamportTs(updatedAt.millisecondsSinceEpoch);
    await db.insert(
      'notes',
      {
        'contract_id': contractId,
        'text': text,
        'updated_at': ts,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await DbService.instance.logOp(entity: 'note', entityId: contractId, op: 'put', rev: 0, ts: ts, fields: SyncRegistry.instance.toFields('note', {'text': text}));
    debugPrint('[DB] saveNote(contract=$contractId) len=${text.length}');
  }

  Future<void> deleteNote(String contractId) async {
    final db = await DbService.instance.db;
    await db.delete('notes', where: 'contract_id = ?', whereArgs: [contractId]);
    final ts = await DbService.instance.nextLamportTs();
    await DbService.instance.logOp(entity: 'note', entityId: contractId, op: 'delete', rev: 0, ts: ts, fields: null);
    debugPrint('[DB] deleteNote(contract=$contractId)');
  }
}

class NoteEntry {
  final String text;
  final DateTime updatedAt;
  const NoteEntry({required this.text, required this.updatedAt});
}

