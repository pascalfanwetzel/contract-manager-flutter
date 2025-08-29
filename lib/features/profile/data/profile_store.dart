import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../../core/crypto/app_crypto.dart';
import 'user_profile.dart';

class ProfileStore {
  Future<File> _plainFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/profile.json');
  }

  Future<File> _encFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/profile.enc');
  }

  Future<UserProfile?> load() async {
    try {
      final ef = await _encFile();
      if (await ef.exists()) {
        final sealed = await ef.readAsBytes();
        final data = await AppCrypto.decryptBytes(Uint8List.fromList(sealed), domain: 'profile');
        final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        if (j.isEmpty) return null;
        return UserProfile.fromJson(j);
      }
    } catch (_) {}
    try {
      final pf = await _plainFile();
      if (!await pf.exists()) return null;
      final txt = await pf.readAsString();
      if (txt.trim().isEmpty) return null;
      final j = jsonDecode(txt) as Map<String, dynamic>;
      if (j.isEmpty) return null;
      await save(UserProfile.fromJson(j));
      try { await pf.delete(); } catch (_) {}
      return UserProfile.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    final ef = await _encFile();
    final bytes = utf8.encode(jsonEncode(profile.toJson()));
    final sealed = await AppCrypto.encryptBytes(Uint8List.fromList(bytes), domain: 'profile');
    await ef.writeAsBytes(sealed, flush: true);
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
