import 'dart:io';

enum AttachmentType { image, pdf, other }

class Attachment {
  final String id;
  final String name; // user-facing name (filename without path)
  final String path; // absolute path on device
  final AttachmentType type;
  final DateTime createdAt;

  const Attachment({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.createdAt,
  });

  bool get exists => File(path).existsSync();

  Attachment copyWith({
    String? name,
    String? path,
  }) => Attachment(
        id: id,
        name: name ?? this.name,
        path: path ?? this.path,
        type: type,
        createdAt: createdAt,
      );
}

AttachmentType detectAttachmentType(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.pdf')) return AttachmentType.pdf;
  if (p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.heic') || p.endsWith('.webp')) {
    return AttachmentType.image;
  }
  return AttachmentType.other;
}

