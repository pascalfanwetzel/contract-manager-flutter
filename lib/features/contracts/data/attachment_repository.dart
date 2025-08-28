import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfx/pdfx.dart';

import '../domain/attachments.dart';
import 'attachment_crypto.dart';

class AttachmentRepository {
  static final _uuid = const Uuid();
  final AttachmentCryptoService _crypto = AttachmentCryptoService();

  Future<Directory> _contractDir(String contractId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/attachments/$contractId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Ensure a .nomedia to avoid scanning by media indexers on Android.
    final noMedia = File('${dir.path}/.nomedia');
    if (!await noMedia.exists()) {
      try {
        await noMedia.writeAsString('', flush: true);
      } catch (_) {}
    }
    return dir;
  }

  Future<Directory> _thumbsDir(String contractId) async {
    final dir = await _contractDir(contractId);
    final thumbs = Directory('${dir.path}/.thumbs');
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
    return thumbs;
  }

  Future<File> _thumbFile(String contractId, String attachmentId, int width) async {
    final thumbs = await _thumbsDir(contractId);
    final safeId = attachmentId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${thumbs.path}/$safeId-w$width.png');
  }

  Future<Uint8List?> loadCachedThumb(String contractId, String attachmentId, int width) async {
    final f = await _thumbFile(contractId, attachmentId, width);
    if (await f.exists()) {
      return Uint8List.fromList(await f.readAsBytes());
    }
    return null;
  }

  Future<Uint8List> buildAndCachePdfThumb(String contractId, Attachment a, Uint8List pdfBytes, int width) async {
    // Render first page at higher resolution for clarity
    final doc = await PdfDocument.openData(pdfBytes);
    final page = await doc.getPage(1);
    final rendered = await page.render(width: width * 2, height: 0);
    await page.close();
    await doc.close();
    final pngBytes = Uint8List.fromList(rendered!.bytes);
    final out = await _thumbFile(contractId, a.id, width);
    await out.writeAsBytes(pngBytes, flush: true);
    await _evictOldThumbnails(contractId);
    return pngBytes;
  }

  Future<Uint8List> getOrCreatePdfThumb(String contractId, Attachment a, Uint8List pdfBytes, int width) async {
    final cached = await loadCachedThumb(contractId, a.id, width);
    if (cached != null) return cached;
    return buildAndCachePdfThumb(contractId, a, pdfBytes, width);
  }

  Future<List<Attachment>> list(String contractId) async {
    final dir = await _contractDir(contractId);
    if (!await dir.exists()) return const [];
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) => !f.path.split(Platform.pathSeparator).last.startsWith('.')).toList();

    // Encrypted attachments use .json metadata alongside .enc payloads
    final metas = files.where((f) => f.path.endsWith('.json')).toList();
    final encrypted = <Attachment>[];
    for (final meta in metas) {
      try {
        final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        final id = j['id'] as String;
        final name = j['name'] as String;
        final encFile = j['enc'] as String; // relative
        final createdMs = j['createdAt'] as int?;
        final encPath = File('${dir.path}/$encFile');
        final type = detectAttachmentType(name);
        encrypted.add(Attachment(
          id: id,
          name: name,
          path: encPath.path,
          type: type,
          createdAt: createdMs != null ? DateTime.fromMillisecondsSinceEpoch(createdMs) : (await encPath.stat()).changed,
        ));
      } catch (_) {
        continue;
      }
    }

    // Legacy plaintext files migration: encrypt and replace with .enc + .json
    final legacyFiles = files.where((f) => !f.path.endsWith('.json') && !f.path.endsWith('.enc')).where((f) {
      final t = detectAttachmentType(f.path);
      return t != AttachmentType.other;
    }).toList();

    final migrated = <Attachment>[];
    for (final f in legacyFiles) {
      try {
        final name = f.uri.pathSegments.last;
        final ext = name.contains('.') ? name.split('.').last : '';
        final bytes = await f.readAsBytes();
        final a = await saveBytes(contractId, bytes, extension: ext, overrideName: name);
        try {
          await f.delete();
        } catch (_) {}
        migrated.add(a);
      } catch (_) {
        // If migration fails, keep legacy reference to avoid data loss
        final name = f.uri.pathSegments.last;
        migrated.add(Attachment(
          id: name,
          name: name,
          path: f.path,
          type: detectAttachmentType(f.path),
          createdAt: FileStat.statSync(f.path).changed,
        ));
      }
    }

    return [...encrypted, ...migrated];
  }

  Future<Attachment> importFromPath(String contractId, String sourcePath, {String? overrideName}) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('Source file does not exist');
    }
    final bytes = await src.readAsBytes();
    final origName = overrideName ?? src.uri.pathSegments.last;
    return saveBytes(contractId, bytes, extension: origName.split('.').last, overrideName: origName);
  }

  Future<Attachment> saveBytes(String contractId, List<int> bytes, {required String extension, String? overrideName}) async {
    final dir = await _contractDir(contractId);
    final id = _uuid.v4();
    final name = overrideName ?? '$id.$extension';
    final encFile = File('${dir.path}/$id.enc');
    final sealed = await _crypto.encrypt(Uint8List.fromList(bytes));
    await encFile.writeAsBytes(sealed, flush: true);
    final meta = File('${dir.path}/$id.json');
    await meta.writeAsString(jsonEncode({
      'id': id,
      'name': name,
      'enc': '$id.enc',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    }), flush: true);
    return Attachment(
      id: id,
      name: name,
      path: encFile.path,
      type: detectAttachmentType(name),
      createdAt: DateTime.now(),
    );
  }

  Future<void> delete(String contractId, Attachment a) async {
    final dir = await _contractDir(contractId);
    final f = File(a.path);
    if (await f.exists()) {
      await f.delete();
    }
    // delete metadata if exists
    final id = _idFromPathOrAttachment(dir, a);
    final meta = File('${dir.path}/$id.json');
    if (await meta.exists()) await meta.delete();
    // delete cached thumbnails
    final thumbs = await _thumbsDir(contractId);
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (await thumbs.exists()) {
      await for (final e in thumbs.list()) {
        if (e is File) {
          final name = e.uri.pathSegments.last;
          if (name.startsWith('$safeId-w') && name.endsWith('.png')) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    }
  }

  Future<Attachment> rename(String contractId, Attachment a, String newName) async {
    final dir = await _contractDir(contractId);
    final sanitized = newName.trim().replaceAll(RegExp(r'[/\\:]'), '_');
    // Update metadata name only; keep encrypted file name stable
    final id = _idFromPathOrAttachment(dir, a);
    final meta = File('${dir.path}/$id.json');
    if (await meta.exists()) {
      final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      j['name'] = sanitized;
      await meta.writeAsString(jsonEncode(j), flush: true);
    }
    return a.copyWith(name: sanitized);
  }

  String _idFromPathOrAttachment(Directory dir, Attachment a) {
    final file = File(a.path).uri.pathSegments.last;
    if (file.endsWith('.enc')) return file.replaceAll('.enc', '');
    // legacy path: try metadata by name/id
    final name = a.id;
    if (name.endsWith('.enc')) return name.replaceAll('.enc', '');
    return name;
  }

  Future<Uint8List> readDecrypted(String contractId, Attachment a) async {
    final f = File(a.path);
    final bytes = await f.readAsBytes();
    // If legacy plaintext (not .enc), return directly
    if (!f.path.endsWith('.enc')) return Uint8List.fromList(bytes);
    return _crypto.decrypt(Uint8List.fromList(bytes));
  }

  // Thumbnail cache eviction: keep per-contract cache under size cap
  static const int _thumbsMaxBytes = 8 * 1024 * 1024; // 8MB
  Future<void> _evictOldThumbnails(String contractId, {int maxBytes = _thumbsMaxBytes}) async {
    final dir = await _thumbsDir(contractId);
    if (!await dir.exists()) return;
    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    int total = 0;
    final entries = <_ThumbInfo>[];
    for (final f in files) {
      try {
        final st = await f.stat();
        total += st.size;
        entries.add(_ThumbInfo(file: f, modified: st.modified, size: st.size));
      } catch (_) {}
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified)); // oldest first
    for (final e in entries) {
      if (total <= maxBytes) break;
      try {
        await e.file.delete();
        total -= e.size;
      } catch (_) {}
    }
  }
}

class _ThumbInfo {
  final File file;
  final DateTime modified;
  final int size;
  _ThumbInfo({required this.file, required this.modified, required this.size});
}

