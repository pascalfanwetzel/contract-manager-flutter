import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../../core/crypto/app_crypto.dart';

class SettingsStore {
  Future<File> _plainFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<File> _encFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/settings.enc');
  }

  Future<Map<String, dynamic>> load() async {
    try {
      final ef = await _encFile();
      if (await ef.exists()) {
        final sealed = await ef.readAsBytes();
        final data = await AppCrypto.decryptBytes(Uint8List.fromList(sealed), domain: 'settings');
        final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        return j;
      }
    } catch (_) {}
    try {
      final pf = await _plainFile();
      if (!await pf.exists()) return {};
      final txt = await pf.readAsString();
      if (txt.trim().isEmpty) return {};
      final j = jsonDecode(txt) as Map<String, dynamic>;
      await save(j);
      try { await pf.delete(); } catch (_) {}
      return j;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    final ef = await _encFile();
    final bytes = utf8.encode(jsonEncode(data));
    final sealed = await AppCrypto.encryptBytes(Uint8List.fromList(bytes), domain: 'settings');
    await ef.writeAsBytes(sealed, flush: true);
  }
}
