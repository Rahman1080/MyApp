import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/document_repository.dart';
import '../../../shared/services/file_storage.dart';

/// Attaches user-chosen files to purchases as [Document] rows.
///
/// Files are copied into app-private storage; the original path is never
/// stored. Contents are never logged or uploaded.
class DocumentService {
  DocumentService({
    required DocumentRepository documentRepository,
    FileStorage? fileStorage,
  })  : _documents = documentRepository,
        _fileStorage = fileStorage ?? FileStorage();

  final DocumentRepository _documents;
  final FileStorage _fileStorage;

  /// Opens the system file picker and attaches the chosen file to [purchaseId].
  /// Returns the created document, or null when the user cancels.
  Future<Document?> pickAndAttach({
    required String purchaseId,
    required String documentType,
  }) async {
    final pickedFiles = await FilePicker.pickFiles();
    final picked = pickedFiles.singleOrNull;
    final path = picked?.path;
    if (picked == null || path == null) return null;

    final stored = await _fileStorage.saveDocument(File(path), picked.name);
    final companion = DocumentsCompanion(
      title: Value(picked.name),
      filePath: Value(stored.path),
      mimeType: Value(_guessMimeType(picked.name, picked.extension)),
      documentType: Value(documentType),
      fileSizeBytes: Value(await stored.length()),
      purchaseId: Value(purchaseId),
    );
    await _documents.create(companion);
    final created = await _documents.searchByTitle(picked.name);
    return created
        .where((doc) => doc.purchaseId == purchaseId)
        .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  }

  /// Deletes the document row and its stored file (best-effort file removal).
  Future<void> deleteDocument(String documentId) async {
    final document = await _documents.requireById(documentId);
    await _documents.delete(documentId);
    await _fileStorage.deleteFile(document.filePath);
  }

  /// Opens the system file picker and attaches the chosen file to
  /// [belongingId]. Returns the created document, or null on cancel.
  Future<Document?> pickAndAttachBelonging({
    required String belongingId,
    required String documentType,
  }) async {
    final pickedFiles = await FilePicker.pickFiles();
    final picked = pickedFiles.singleOrNull;
    final path = picked?.path;
    if (picked == null || path == null) return null;

    final stored = await _fileStorage.saveDocument(File(path), picked.name);
    final companion = DocumentsCompanion(
      title: Value(picked.name),
      filePath: Value(stored.path),
      mimeType: Value(_guessMimeType(picked.name, picked.extension)),
      documentType: Value(documentType),
      fileSizeBytes: Value(await stored.length()),
      belongingId: Value(belongingId),
    );
    await _documents.create(companion);
    final created = await _documents.searchByTitle(picked.name);
    return created
        .where((doc) => doc.belongingId == belongingId)
        .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  }

  Future<List<Document>> documentsForBelonging(String belongingId) {
    // One-shot read (widget-test safe); watch streams live in the repository.
    return _documents.getByBelonging(belongingId);
  }

  Future<List<Document>> documentsForPurchase(String purchaseId) {
    // One-shot read (widget-test safe); watch streams live in the repository.
    return _documents.getByPurchase(purchaseId);
  }

  String? _guessMimeType(String name, String? extension) {
    final ext = (extension ?? '').toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      'txt' => 'text/plain',
      _ => null,
    };
  }
}
