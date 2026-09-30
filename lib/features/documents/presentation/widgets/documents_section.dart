import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/database/keepit_database.dart';
import '../../domain/document_service.dart';

/// Document attachments on the purchase detail screen or a belonging detail
/// screen.
///
/// Lists attached files (name, size, type), lets the user attach more via
/// the system file picker, preview images inline, and delete with
/// confirmation (removes the row and the stored file).
///
/// Scope note: only image previews are inlined. Other file types show an
/// info dialog instead of launching an external viewer, keeping this phase
/// dependency-light and fully offline.
class DocumentsSection extends StatefulWidget {
  const DocumentsSection({
    super.key,
    this.purchaseId,
    this.belongingId,
    required this.documentService,
  }) : assert(purchaseId != null || belongingId != null,
            'One of purchaseId or belongingId is required.'),
       assert(purchaseId == null || belongingId == null,
            'Only one of purchaseId or belongingId may be set.');

  final String? purchaseId;
  final String? belongingId;
  final DocumentService documentService;

  @override
  State<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<DocumentsSection> {
  List<Document> _documents = [];
  bool _loading = true;
  bool _attaching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final documents = widget.purchaseId != null
        ? await widget.documentService.documentsForPurchase(widget.purchaseId!)
        : await widget.documentService
            .documentsForBelonging(widget.belongingId!);
    if (mounted) {
      setState(() {
        _documents = documents;
        _loading = false;
      });
    }
  }

  Future<void> _attach() async {
    setState(() => _attaching = true);
    try {
      final created = widget.purchaseId != null
          ? await widget.documentService.pickAndAttach(
              purchaseId: widget.purchaseId!,
              documentType: 'other',
            )
          : await widget.documentService.pickAndAttachBelonging(
              belongingId: widget.belongingId!,
              documentType: 'other',
            );
      if (created != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document attached.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t attach that file. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _attaching = false);
        await _load();
      }
    }
  }

  Future<void> _delete(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          '“${document.title}” will be removed. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.documentService.deleteDocument(document.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document deleted.')),
      );
    }
  }

  void _open(Document document) {
    if (_isImage(document)) {
      _previewImage(document);
    } else {
      _showFileInfo(document);
    }
  }

  bool _isImage(Document document) {
    final mime = document.mimeType ?? '';
    return mime.startsWith('image/') ||
        RegExp(r'\.(jpg|jpeg|png|heic|webp)$', caseSensitive: false)
            .hasMatch(document.filePath);
  }

  void _previewImage(Document document) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(
                document.title,
                overflow: TextOverflow.ellipsis,
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  File(document.filePath),
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('The file is missing from storage.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFileInfo(Document document) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(document.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${document.documentType}'),
            const SizedBox(height: 4),
            Text('Size: ${_formatBytes(document.fileSizeBytes)}'),
            const SizedBox(height: 12),
            const Text(
              'In-app preview isn\'t available for this file type yet. '
              'The file is stored privately on this device.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Documents', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  key: const Key('attachDocumentButton'),
                  onPressed: _attaching ? null : _attach,
                  icon: _attaching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                  label: const Text('Attach'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_documents.isEmpty)
              Text(
                'No documents yet. Attach manuals, invoices, or warranty cards.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final document in _documents)
                ListTile(
                  key: Key('document-${document.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _isImage(document)
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                  ),
                  title: Text(
                    document.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${document.documentType} · ${_formatBytes(document.fileSizeBytes)}',
                  ),
                  onTap: () => _open(document),
                  trailing: IconButton(
                    tooltip: 'Delete document',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(document),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
