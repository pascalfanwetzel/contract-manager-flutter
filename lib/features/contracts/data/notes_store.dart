import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class NotesStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/notes.json');
    if (!await f.exists()) {
      await f.writeAsString(jsonEncode({'notes': {}}), flush: true);
    }
    return f;
  }

  Future<Map<String, dynamic>> _readAll() async {
    final f = await _file();
    try {
      final txt = await f.readAsString();
      final j = jsonDecode(txt) as Map<String, dynamic>;
      return j['notes'] as Map<String, dynamic>? ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, NoteEntry>> loadAll() async {
    final raw = await _readAll();
    final out = <String, NoteEntry>{};
    raw.forEach((k, v) {
      try {
        final m = v as Map<String, dynamic>;
        out[k] = NoteEntry(
          text: (m['text'] as String?) ?? '',
          updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as int?) ?? 0),
        );
      } catch (_) {}
    });
    return out;
  }

  Future<void> saveNote(String contractId, String text, DateTime updatedAt) async {
    final f = await _file();
    final root = await _readAll();
    root[contractId] = {
      'text': text,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
    final jsonRoot = {'notes': root};
    await f.writeAsString(jsonEncode(jsonRoot), flush: true);
  }

  Future<void> deleteNote(String contractId) async {
    final f = await _file();
    final root = await _readAll();
    root.remove(contractId);
    final jsonRoot = {'notes': root};
    await f.writeAsString(jsonEncode(jsonRoot), flush: true);
  }
}

class NoteEntry {
  final String text;
  final DateTime updatedAt;
  const NoteEntry({required this.text, required this.updatedAt});
}

