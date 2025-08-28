import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../domain/attachments.dart';

class AttachmentViewerPage extends StatefulWidget {
  final Attachment attachment;
  final String contractId;
  final AppState state;
  const AttachmentViewerPage({super.key, required this.attachment, required this.contractId, required this.state});

  @override
  State<AttachmentViewerPage> createState() => _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends State<AttachmentViewerPage> {
  bool _busy = false;
  late Attachment _attachment;
  Uint8List? _data; // decrypted bytes

  @override
  void initState() {
    super.initState();
    _attachment = widget.attachment;
    _load();
    _secureOn();
  }

  static const MethodChannel _secureChannel = MethodChannel('screen_secure');
  Future<void> _secureOn() async {
    try { await _secureChannel.invokeMethod('enable'); } catch (_) {}
  }
  Future<void> _secureOff() async {
    try { await _secureChannel.invokeMethod('disable'); } catch (_) {}
  }

  Future<void> _load() async {
    final b = await widget.state.readAttachmentBytes(widget.contractId, _attachment);
    if (!mounted) return;
    setState(() => _data = b);
  }

  Future<void> _share() async {
    final data = _data ?? await widget.state.readAttachmentBytes(widget.contractId, _attachment);
    await Share.shareXFiles([XFile.fromData(data, name: _attachment.name)]);
  }

  Future<void> _download(BuildContext context) async {
    setState(() => _busy = true);
    try {
      // Attempt to copy to a visible Downloads-like directory.
      // On desktop, getDownloadsDirectory is available. On mobile, fall back to app documents.
      final downloads = await getDownloadsDirectory();
      final targetDir = downloads ?? await getApplicationDocumentsDirectory();
      final dest = File('${targetDir.path}/${_attachment.name}');
      final data = _data ?? await widget.state.readAttachmentBytes(widget.contractId, _attachment);
      await dest.writeAsBytes(data, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${targetDir.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete attachment?'),
        content: Text('Remove ${_attachment.name} permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.deleteAttachment(widget.contractId, _attachment);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: _attachment.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename attachment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name (with extension)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _attachment.name) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.state.renameAttachment(widget.contractId, _attachment, name);
      setState(() {
        _attachment = updated; // refresh local reference so title/path update
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renamed')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _secureOff();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _attachment;
    final actions = <Widget>[
      IconButton(
        tooltip: 'Share',
        icon: const Icon(Icons.ios_share_outlined),
        onPressed: _busy ? null : _share,
      ),
      IconButton(
        tooltip: 'Download',
        icon: const Icon(Icons.file_download_outlined),
        onPressed: _busy ? null : () => _download(context),
      ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => _delete(context),
      ),
      PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'rename') _rename(context);
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(a.name),
      ),
      body: switch (a.type) {
        AttachmentType.image => _data == null
            ? const Center(child: CircularProgressIndicator())
            : PhotoView(imageProvider: MemoryImage(_data!)),
        AttachmentType.pdf => _data == null
            ? const Center(child: CircularProgressIndicator())
            : _PdfViewerData(bytes: _data!),
        AttachmentType.other => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Unsupported file type for in-app preview. File: ${a.name}'),
            ),
          ),
      },
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: actions,
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String path;
  const _ImageViewer({required this.path});
  @override
  Widget build(BuildContext context) {
    return PhotoView(imageProvider: FileImage(File(path)));
  }
}

class _PdfViewerData extends StatefulWidget {
  final Uint8List bytes;
  const _PdfViewerData({required this.bytes});
  @override
  State<_PdfViewerData> createState() => _PdfViewerDataState();
}

class _PdfViewerDataState extends State<_PdfViewerData> {
  late PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(document: PdfDocument.openData(widget.bytes));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewPinch(controller: _controller);
  }
}
