import 'package:uuid/uuid.dart';
import 'package:pdfx/pdfx.dart';
import '../../../core/db/db_service.dart';
import '../../../core/cloud/sync_registry.dart';
import '../domain/attachments.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';

class AttachmentRepository {
  static final _uuid = const Uuid();

  Future<Uint8List?> loadCachedThumb(String contractId, String attachmentId, int width) async {
    final db = await DbService.instance.db;
    final rows = await db.query('thumbs', where: 'attachment_id = ? AND width = ?', whereArgs: [attachmentId, width]);
    if (rows.isEmpty) return null;
    return rows.first['data'] as Uint8List;
  }

  Future<Uint8List> buildAndCachePdfThumb(String contractId, Attachment a, Uint8List pdfBytes, int width) async {
    final doc = await PdfDocument.openData(pdfBytes);
    final page = await doc.getPage(1);
    final rendered = await page.render(width: width * 2, height: 0);
    await page.close();
    await doc.close();
    final pngBytes = Uint8List.fromList(rendered!.bytes);
    final db = await DbService.instance.db;
    await db.insert(
      'thumbs',
      {'attachment_id': a.id, 'width': width, 'data': pngBytes},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return pngBytes;
  }

  Future<Uint8List> getOrCreatePdfThumb(String contractId, Attachment a, Uint8List pdfBytes, int width) async {
    final cached = await loadCachedThumb(contractId, a.id, width);
    if (cached != null) return cached;
    return buildAndCachePdfThumb(contractId, a, pdfBytes, width);
  }

  Future<List<Attachment>> list(String contractId) async {
    final db = await DbService.instance.db;
    final rows = await db.query('attachments', where: 'contract_id = ? AND deleted = 0', whereArgs: [contractId]);
    return rows
        .map((r) => Attachment(
              id: r['id'] as String,
              name: r['name'] as String,
              path: 'db://${r['id']}',
              type: _typeFromString(r['type'] as String),
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
  }

  Future<Attachment> importFromPath(String contractId, String sourcePath, {String? overrideName}) async {
    final file = File(sourcePath);
    final bytes = await file.readAsBytes();
    final name = overrideName ?? file.uri.pathSegments.last;
    final ext = name.contains('.') ? name.split('.').last : '';
    return saveBytes(contractId, bytes, extension: ext, overrideName: name);
  }

  Future<Attachment> saveBytes(String contractId, List<int> bytes, {required String extension, String? overrideName}) async {
    final db = await DbService.instance.db;
    final id = _uuid.v4();
    final name = overrideName ?? '$id.$extension';
    final type = detectAttachmentType(name);
    final now = DateTime.now();
    // Compute content hash (SHA-256)
    final hash = await Sha256().hash(bytes);
    final hex = _toHex(hash.bytes);
    final ts = await DbService.instance.nextLamportTs();
    await db.transaction((txn) async {
      // Upsert blob and bump refcount
      final blob = await txn.query('blobs', where: 'hash = ?', whereArgs: [hex], limit: 1);
      if (blob.isEmpty) {
        await txn.insert('blobs', {'hash': hex, 'data': Uint8List.fromList(bytes), 'refcount': 1});
      } else {
        final rc = ((blob.first['refcount'] as int?) ?? 0) + 1;
        await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [hex]);
      }
      await txn.insert(
        'attachments',
        {
          'id': id,
          'contract_id': contractId,
          'name': name,
          'type': type.name,
          'created_at': now.millisecondsSinceEpoch,
          'data': Uint8List(0),
          'blob_hash': hex,
          'rev': 1,
          'updated_at': ts,
          'deleted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await DbService.instance.logOp(
      entity: 'attachment',
      entityId: id,
      op: 'put',
      rev: 1,
      ts: (await DbService.instance.nextLamportTs()),
      // Include created_at so receivers can satisfy NOT NULL constraint
      fields: SyncRegistry.instance.toFields('attachment', {'contract_id': contractId, 'name': name, 'type': type.name, 'blob_hash': hex, 'created_at': now.millisecondsSinceEpoch}),
    );
    return Attachment(id: id, name: name, path: 'db://$id', type: type, createdAt: now);
  }

  Future<void> delete(String contractId, Attachment a) async {
    final db = await DbService.instance.db;
    final ts = await DbService.instance.nextLamportTs();
    await db.transaction((txn) async {
      final rows = await txn.query('attachments', where: 'id = ?', whereArgs: [a.id], limit: 1);
      if (rows.isNotEmpty) {
        final prev = rows.first;
        final rev = ((prev['rev'] as int?) ?? 0) + 1;
        final blobHash = prev['blob_hash'] as String?;
        await txn.update('attachments', {'deleted': 1, 'rev': rev, 'updated_at': ts}, where: 'id = ?', whereArgs: [a.id]);
        await txn.delete('thumbs', where: 'attachment_id = ?', whereArgs: [a.id]);
        if (blobHash != null && blobHash.isNotEmpty) {
          final b = await txn.query('blobs', where: 'hash = ?', whereArgs: [blobHash], limit: 1);
          if (b.isNotEmpty) {
            final rc = ((b.first['refcount'] as int?) ?? 1) - 1;
            if (rc <= 0) {
              await txn.delete('blobs', where: 'hash = ?', whereArgs: [blobHash]);
            } else {
              await txn.update('blobs', {'refcount': rc}, where: 'hash = ?', whereArgs: [blobHash]);
            }
          }
        }
        await DbService.instance.logOpTx(txn, entity: 'attachment', entityId: a.id, op: 'delete', rev: (prev['rev'] as int? ?? 0) + 1, ts: ts, fields: SyncRegistry.instance.toFields('attachment', {'blob_hash': blobHash}));
      }
    });
  }

  Future<Attachment> rename(String contractId, Attachment a, String newName) async {
    final db = await DbService.instance.db;
    final sanitized = newName.trim().replaceAll(RegExp(r'[/\\:]'), '_');
    final ts = await DbService.instance.nextLamportTs();
    final rows = await db.query('attachments', where: 'id = ?', whereArgs: [a.id], limit: 1);
    int rev = 0;
    if (rows.isNotEmpty) { rev = ((rows.first['rev'] as int?) ?? 0) + 1; }
    await db.update('attachments', {'name': sanitized, 'rev': rev, 'updated_at': ts}, where: 'id = ?', whereArgs: [a.id]);
    await DbService.instance.logOp(entity: 'attachment', entityId: a.id, op: 'put', rev: rev, ts: ts, fields: SyncRegistry.instance.toFields('attachment', {'name': sanitized}));
    return a.copyWith(name: sanitized);
  }

  Future<Uint8List> readDecrypted(String contractId, Attachment a) async {
    final db = await DbService.instance.db;
    final rows = await db.query('attachments', columns: ['data','blob_hash'], where: 'id = ?', whereArgs: [a.id], limit: 1);
    if (rows.isEmpty) throw Exception('Attachment not found');
    final bh = rows.first['blob_hash'] as String?;
    if (bh != null && bh.isNotEmpty) {
      final b = await db.query('blobs', columns: ['data'], where: 'hash = ?', whereArgs: [bh], limit: 1);
      if (b.isNotEmpty) return b.first['data'] as Uint8List;
    }
    return rows.first['data'] as Uint8List;
  }
}

AttachmentType _typeFromString(String s) {
  switch (s) {
    case 'image':
      return AttachmentType.image;
    case 'pdf':
      return AttachmentType.pdf;
    default:
      return AttachmentType.other;
  }
}

String _toHex(List<int> bytes) {
  const hex = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(hex[(b >> 4) & 0xF]);
    out.write(hex[b & 0xF]);
  }
  return out.toString();
}

