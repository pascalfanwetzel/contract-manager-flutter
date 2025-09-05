import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show getDatabasesPath;

import '../../../../core/crypto/crypto_config.dart';
import '../../../../core/crypto/key_service.dart';
import '../../../../core/db/db_service.dart';
import '../../../../core/fs/app_dirs.dart';
import '../../data/profile_store.dart';

class StorageInfoView extends StatefulWidget {
  const StorageInfoView({super.key});

  @override
  State<StorageInfoView> createState() => _StorageInfoViewState();
}

class _StorageInfoViewState extends State<StorageInfoView> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final support = await AppDirs.supportDir();
      String dbPathInUse = '';
      try {
        final db = await DbService.instance.db;
        // sqflite exposes database path via getter
        final dynamic dynDb = db;
        dbPathInUse = dynDb.path ?? '';
      } catch (_) {}

      final databasesBase = await getDatabasesPath();
      final encEnabled = !CryptoConfig.disableEncryption;

      final candidates = <String>[
        // Desktop build writes here (unencrypted)
        Platform.isWindows || Platform.isLinux ? '${support.path}/app.db' : '',
        // Mobile/macOS plain/encrypted database paths
        '$databasesBase/app_plain.db',
        '$databasesBase/app_enc.db',
      ].where((p) => p.isNotEmpty).toList();

      final files = <Map<String, dynamic>>[];
      for (final p in candidates) {
        final f = File(p);
        files.add({
          'path': p,
          'exists': await f.exists(),
          'size': await f.exists() ? await f.length() : 0,
        });
      }

      // Master key locations
      final mkSupport = File('${support.path}/mk.bin');
      final mkDbDir = File('$databasesBase/mk.bin');
      final mkInfo = <String, dynamic>{
        'secure_storage': await KeyService.instance.hasMasterKey(),
        'support_file_path': mkSupport.path,
        'support_file_exists': await mkSupport.exists(),
        'dbdir_file_path': mkDbDir.path,
        'dbdir_file_exists': await mkDbDir.exists(),
      };

      // Profile avatar (if any)
      String? avatarPath;
      bool avatarExists = false;
      try {
        final profile = await ProfileStore().load();
        avatarPath = profile?.photoPath;
        if (avatarPath != null && avatarPath.isNotEmpty) {
          avatarExists = await File(avatarPath).exists();
        }
      } catch (_) {}

      setState(() {
        _data = {
          'platform': Platform.operatingSystem,
          'encryption_enabled': encEnabled,
          'support_dir': support.path,
          'databases_dir': databasesBase,
          'db_path_in_use': dbPathInUse,
          'db_candidates': files,
          'mk': mkInfo,
          'avatar_path': avatarPath,
          'avatar_exists': avatarExists,
        };
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Storage Info')),
      body: _error != null
          ? Center(child: Text('Error: $_error'))
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _kv('Platform', '${data['platform']}'),
                    _kv('Encryption enabled', '${data['encryption_enabled']}'),
                    const SizedBox(height: 8),
                    _kv('Support dir', '${data['support_dir']}'),
                    _kv('Databases dir', '${data['databases_dir']}'),
                    _kv('DB path (in use)', (data['db_path_in_use'] as String).isEmpty ? '(unknown/unopened)' : '${data['db_path_in_use']}'),
                    const Divider(height: 24),
                    Text('Database candidates', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...((data['db_candidates'] as List)
                        .cast<Map<String, dynamic>>()
                        .map((m) => _kv(
                              m['path'] as String,
                              'exists=${m['exists']} size=${m['size']}',
                            ))),
                    const Divider(height: 24),
                    Text('Master Key', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _kv('Secure storage available', '${data['mk']['secure_storage']}'),
                    _kv('MK support file', '${data['mk']['support_file_path']} (exists=${data['mk']['support_file_exists']})'),
                    _kv('MK dbdir file', '${data['mk']['dbdir_file_path']} (exists=${data['mk']['dbdir_file_exists']})'),
                    const Divider(height: 24),
                    Text('Avatar', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _kv('Avatar path', (data['avatar_path'] as String?) ?? '(none)'),
                    _kv('Avatar exists', '${data['avatar_exists']}'),
                  ],
                ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: SelectableText(v)),
        ],
      ),
    );
  }
}
