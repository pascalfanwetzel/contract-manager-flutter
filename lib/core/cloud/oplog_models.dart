import 'dart:convert';

class SyncOp {
  final String opId;
  final String entity; // 'category' | 'contract' | 'attachment' | 'note'
  final String entityId;
  final String op; // 'put' | 'delete'
  final int rev;
  final int ts; // lamport timestamp (ms)
  final String deviceId;
  final Map<String, dynamic>? fields;

  const SyncOp({
    required this.opId,
    required this.entity,
    required this.entityId,
    required this.op,
    required this.rev,
    required this.ts,
    required this.deviceId,
    this.fields,
  });

  factory SyncOp.fromRow(Map<String, Object?> row) {
    return SyncOp(
      opId: row['op_id'] as String,
      entity: row['entity'] as String,
      entityId: row['entity_id'] as String,
      op: row['op'] as String,
      rev: (row['rev'] as int?) ?? 0,
      ts: (row['ts'] as int?) ?? 0,
      deviceId: row['device_id'] as String,
      fields: row['fields'] == null ? null : Map<String, dynamic>.from(_tryDecodeJson(row['fields'] as String)),
    );
  }
}

dynamic _tryDecodeJson(String s) {
  try {
    return s.isEmpty ? {} : (jsonDecode(s) as Map<String, dynamic>);
  } catch (_) {
    return {};
  }
}
