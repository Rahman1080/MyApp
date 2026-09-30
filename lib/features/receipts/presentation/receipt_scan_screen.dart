import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/receipt_repository.dart';
import '../../../core/permissions/permission_service.dart';
import '../domain/receipt_capture_service.dart';
import '../domain/receipt_text_parser.dart';
import 'widgets/receipt_confirm_form.dart';

/// Full receipt-capture flow for one purchase.
///
/// Steps: choose image source → on-device OCR with progress → user reviews
/// and edits the parsed fields → Confirm persists the image (app-private
/// storage) and creates the Receipt row, or Discard abandons everything.
/// Nothing is saved from OCR output without explicit user confirmation.
class ReceiptScanScreen extends StatefulWidget {
  const ReceiptScanScreen({
    super.key,
    required this.purchaseId,
    required this.database,
    this.captureService,
    this.permissionService = const PermissionService(),
  });

  static const String routePath = '/scan';

  final String purchaseId;
  final KeepItDatabase database;
  final ReceiptCaptureService? captureService;
  final PermissionService permissionService;

  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

enum _ScanStep { chooseSource, scanning, confirm }

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  _ScanStep _step = _ScanStep.chooseSource;
  File? _image;
  String _rawText = '';
  ParsedReceipt _parsed = const ParsedReceipt();
  String? _error;
  late final ReceiptCaptureService _capture =
      widget.captureService ?? ReceiptCaptureService();

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    // PermissionService guards `context.mounted` before every dialog or
    // snackbar, so passing context into the async request is safe.
    final granted = source == ImageSource.camera
        // ignore: use_build_context_synchronously
        ? await widget.permissionService.ensureCamera(context)
        // ignore: use_build_context_synchronously
        : await widget.permissionService.ensurePhotos(context);
    if (!granted || !mounted) return;

    final image = await _capture.pickImage(source: source);
    if (image == null || !mounted) return; // user cancelled the picker

    setState(() {
      _image = image;
      _step = _ScanStep.scanning;
      _error = null;
    });

    try {
      final result = await _capture.recognizeAndParse(image);
      if (!mounted) return;
      setState(() {
        _rawText = result.rawText;
        _parsed = result.parsed;
        _step = _ScanStep.confirm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t read any text from that image. '
            'Try a clearer photo with the receipt flat and well lit.';
        _step = _ScanStep.chooseSource;
        _image = null;
      });
    }
  }

  Future<void> _confirm({
    required String? store,
    required DateTime? date,
    required int? totalCents,
    required int? subtotalCents,
    required int? taxCents,
  }) async {
    final image = _image;
    if (image == null) return;
    try {
      final stored = await _capture.persistImage(image);
      final repository = ReceiptRepository(widget.database);
      await repository.create(ReceiptsCompanion(
        purchaseId: Value(widget.purchaseId),
        imagePath: Value(stored.path),
        store: Value(store),
        receiptDate: Value(date),
        totalCents: Value(totalCents),
        subtotalCents: Value(subtotalCents),
        taxCents: Value(taxCents),
        rawOcrText: Value(_rawText.isEmpty ? null : _rawText),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt saved.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t save the receipt. Please try again.'),
        ),
      );
      // Return to the confirm form so the user doesn't lose their edits.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: switch (_step) {
        _ScanStep.chooseSource => _sourceChooser(context),
        _ScanStep.scanning => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Reading receipt…'),
                SizedBox(height: 4),
                Text(
                  'On-device — nothing is uploaded.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        _ScanStep.confirm => ReceiptConfirmForm(
            image: _image!,
            rawText: _rawText,
            parsed: _parsed,
            onConfirm: _confirm,
            onDiscard: () => Navigator.of(context).pop(false),
          ),
      },
    );
  }

  Widget _sourceChooser(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'How would you like to add the receipt?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('scanCameraButton'),
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take a photo'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('scanGalleryButton'),
            onPressed: () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from photos'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
          ),
          const SizedBox(height: 24),
          Text(
            'Receipts are scanned on this device and stored privately. '
            'They are never uploaded automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
