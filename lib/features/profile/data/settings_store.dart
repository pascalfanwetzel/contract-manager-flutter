import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SettingsStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/settings.json');
    if (!await f.exists()) {
      await f.writeAsString(jsonEncode({}), flush: true);
    }
    return f;
  }

  Future<Map<String, dynamic>> load() async {
    try {
      final f = await _file();
      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return {};
      final j = jsonDecode(txt) as Map<String, dynamic>;
      return j;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(data), flush: true);
  }
}

