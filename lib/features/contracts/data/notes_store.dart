import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../../core/crypto/app_crypto.dart';

class NotesStore {
  Future<File> _plainFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/notes.json');
  }

  Future<File> _encFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/notes.enc');
  }

  Future<Map<String, dynamic>> _readAll() async {
    // Prefer encrypted file; fall back to plaintext for migration
    try {
      final ef = await _encFile();
      if (await ef.exists()) {
        final sealed = await ef.readAsBytes();
        final data = await AppCrypto.decryptBytes(Uint8List.fromList(sealed), domain: 'notes');
        final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        return j['notes'] as Map<String, dynamic>? ?? <String, dynamic>{};
      }
    } catch (_) {}
    try {
      final pf = await _plainFile();
      if (!await pf.exists()) return <String, dynamic>{};
      final txt = await pf.readAsString();
      final j = jsonDecode(txt) as Map<String, dynamic>;
      // Migrate
      await _writeAll(j['notes'] as Map<String, dynamic>? ?? <String, dynamic>{});
      try { await pf.delete(); } catch (_) {}
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
    final root = await _readAll();
    root[contractId] = {
      'text': text,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
    await _writeAll(root);
  }

  Future<void> deleteNote(String contractId) async {
    final root = await _readAll();
    root.remove(contractId);
    await _writeAll(root);
  }

  Future<void> _writeAll(Map<String, dynamic> notes) async {
    final ef = await _encFile();
    final jsonRoot = {'notes': notes};
    final bytes = utf8.encode(jsonEncode(jsonRoot));
    final sealed = await AppCrypto.encryptBytes(Uint8List.fromList(bytes), domain: 'notes');
    await ef.writeAsBytes(sealed, flush: true);
  }
}

class NoteEntry {
  final String text;
  final DateTime updatedAt;
  const NoteEntry({required this.text, required this.updatedAt});
}
