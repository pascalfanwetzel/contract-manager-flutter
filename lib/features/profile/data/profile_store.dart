import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'user_profile.dart';

class ProfileStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/profile.json');
    if (!await f.exists()) {
      await f.writeAsString(jsonEncode({}), flush: true);
    }
    return f;
  }

  Future<UserProfile?> load() async {
    try {
      final f = await _file();
      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return null;
      final j = jsonDecode(txt) as Map<String, dynamic>;
      if (j.isEmpty) return null;
      return UserProfile.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }

  Future<String> saveAvatarFromPath(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) throw Exception('Avatar source missing');
    final dir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.toLowerCase().split('.').last;
    final dest = File('${dir.path}/profile_avatar.$ext');
    await src.copy(dest.path);
    return dest.path;
  }
}

