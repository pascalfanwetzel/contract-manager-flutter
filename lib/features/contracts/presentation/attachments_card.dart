import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
// pdfx not used here; thumbnails come from cached PNG bytes
import '../data/app_state.dart';
import '../domain/attachments.dart';
import 'attachment_viewer_page.dart';

class AttachmentsCard extends StatefulWidget {
  final AppState state;
  final String contractId;
  const AttachmentsCard({super.key, required this.state, required this.contractId});

  @override
  State<AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends State<AttachmentsCard> {
  bool _expanded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.state.loadAttachments(widget.contractId);
  }

  Future<void> _addAttachment(BuildContext context) async {
    // Capture devicePixelRatio before async gaps to avoid context-after-await lint
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Import PDF'),
            onTap: () => Navigator.pop(ctx, _AddChoice.pickPdf),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Import Image'),
            onTap: () => Navigator.pop(ctx, _AddChoice.pickImage),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(ctx, _AddChoice.camera),
          ),
        ]),
      ),
    );
    if (choice == null) return;

    setState(() => _loading = true);
    try {
      switch (choice) {
        case _AddChoice.pickPdf:
          final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
          final path = res?.files.single.path;
          if (path != null) {
            await widget.state.addAttachmentFromPath(widget.contractId, path);
            // Warm thumbnails in background
            widget.state.warmThumbnails(widget.contractId, devicePixelRatio: dpr);
          }
          break;
        case _AddChoice.pickImage:
          final res = await FilePicker.platform.pickFiles(type: FileType.image);
          final path = res?.files.single.path;
          if (path != null) {
            await widget.state.addAttachmentFromPath(widget.contractId, path);
            widget.state.warmThumbnails(widget.contractId, devicePixelRatio: dpr);
          }
          break;
        case _AddChoice.camera:
          final picker = ImagePicker();
          final shot = await picker.pickImage(source: ImageSource.camera);
          if (shot != null) {
            final bytes = await shot.readAsBytes();
            await widget.state.addAttachmentFromBytes(widget.contractId, bytes, extension: 'jpg');
            widget.state.warmThumbnails(widget.contractId, devicePixelRatio: dpr);
          }
          break;
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.state.attachmentsFor(widget.contractId);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.attach_file_outlined),
            title: const Text('Attachments'),
            subtitle: Text(items.isEmpty ? 'No attachments' : '${items.length} attached'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _loading ? null : () => _addAttachment(context),
                ),
                if (items.isNotEmpty)
                  IconButton(
                    tooltip: widget.state.attachmentsGridPreferred ? 'List view' : 'Grid view',
                    icon: Icon(widget.state.attachmentsGridPreferred ? Icons.view_list_outlined : Icons.grid_view),
                    onPressed: () => widget.state
                        .setAttachmentsGridPreferred(!widget.state.attachmentsGridPreferred),
                  ),
                if (items.isNotEmpty)
                  IconButton(
                    tooltip: _expanded ? 'Collapse' : 'Expand',
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
            onTap: items.isEmpty ? null : () => setState(() => _expanded = !_expanded),
          ),
          // Smooth height-only transition to avoid width compression glitches
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1.0,
                child: child,
              ),
              child: (!_expanded || items.isEmpty)
                  ? const SizedBox.shrink(key: ValueKey('att_collapsed'))
                  : Column(
                      key: const ValueKey('att_expanded'),
                      children: [
                        const Divider(height: 1),
                        widget.state.attachmentsGridPreferred
                            ? GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                                itemCount: items.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                ),
                                itemBuilder: (context, i) {
                                  final a = items[i];
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      Navigator.of(context, rootNavigator: true).push(
                                        MaterialPageRoute(
                                          builder: (_) => AttachmentViewerPage(
                                            attachment: a,
                                            contractId: widget.contractId,
                                            state: widget.state,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: _AttachmentThumb(
                                              attachment: a,
                                              size: double.infinity,
                                              state: widget.state,
                                              contractId: widget.contractId,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          a.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount: items.length,
                                separatorBuilder: (context, _) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final a = items[i];
                                  return ListTile(
                                    leading: _AttachmentThumb(
                                      attachment: a,
                                      size: 40,
                                      state: widget.state,
                                      contractId: widget.contractId,
                                    ),
                                    title: Text(a.name),
                                    onTap: () {
                                      Navigator.of(context, rootNavigator: true).push(
                                        MaterialPageRoute(
                                          builder: (_) => AttachmentViewerPage(
                                            attachment: a,
                                            contractId: widget.contractId,
                                            state: widget.state,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AddChoice { pickPdf, pickImage, camera }

class _AttachmentThumb extends StatelessWidget {
  final Attachment attachment;
  final double? size; // if null in grid, we expand to fill
  final AppState state;
  final String contractId;
  const _AttachmentThumb({required this.attachment, this.size, required this.state, required this.contractId});

  @override
  Widget build(BuildContext context) {
    final s = size ?? 40.0;
    switch (attachment.type) {
      case AttachmentType.image:
        // For encrypted images, read bytes via state and display memory image.
        return FutureBuilder<Uint8List>(
          future: state.readAttachmentBytes(contractId, attachment),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done || !snap.hasData) {
              return Container(
                width: size == double.infinity ? null : s,
                height: size == double.infinity ? null : s,
                color: Colors.black12,
              );
            }
            return Image.memory(
              snap.data!,
              width: size == double.infinity ? null : s,
              height: size == double.infinity ? null : s,
              fit: BoxFit.cover,
            );
          },
        );
      case AttachmentType.pdf:
        return _PdfThumb(
          attachment: attachment,
          contractId: contractId,
          state: state,
          size: s == double.infinity ? null : s,
        );
      case AttachmentType.other:
        return Container(
          width: size == double.infinity ? null : s,
          height: size == double.infinity ? null : s,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.insert_drive_file_outlined),
        );
    }
  }
}

class _PdfThumb extends StatefulWidget {
  final Attachment attachment;
  final String contractId;
  final AppState state;
  final double? size; // thumbnail square size; null means expand
  const _PdfThumb({required this.attachment, required this.contractId, required this.state, this.size});

  @override
  State<_PdfThumb> createState() => _PdfThumbState();
}

class _PdfThumbState extends State<_PdfThumb> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadOrBuildThumb(widget.attachment, widget.contractId, widget.state, widget.size);
  }

  @override
  void didUpdateWidget(covariant _PdfThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.path != widget.attachment.path || oldWidget.size != widget.size) {
      _future = _loadOrBuildThumb(widget.attachment, widget.contractId, widget.state, widget.size);
    }
  }

  Future<Uint8List?> _loadOrBuildThumb(Attachment a, String contractId, AppState state, double? size) async {
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final target = ((size ?? 120) * dpr).round();
      final png = await state.getOrCreatePdfThumb(contractId, a, width: target);
      return png;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final placeholder = Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
    );
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.data == null) {
          return placeholder;
        }
        return Image.memory(
          snap.data!,
          width: s,
          height: s,
          fit: BoxFit.cover,
        );
      },
    );
  }
}
