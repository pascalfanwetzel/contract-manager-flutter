import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppDirs {
  static Future<Directory> supportDir() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

