import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/keepit_database.dart';
import '../../../../core/database/repositories/belonging_photo_repository.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../../../shared/services/file_storage.dart';

/// "Photos" section for the item detail screen: a horizontal gallery of the
/// item's extra photos (the cover photo lives on the belonging itself).
/// Only rendered when there is at least one photo or when [alwaysShow] is
/// set — the detail screen decides visibility.
class BelongingPhotosSection extends StatefulWidget {
  const BelongingPhotosSection({
    super.key,
    required this.belongingId,
    required this.photoRepository,
    this.permissionService = const PermissionService(),
    this.fileStorage,
    this.imagePicker,
  });

  final String belongingId;
  final BelongingPhotoRepository photoRepository;
  final PermissionService permissionService;
  final FileStorage? fileStorage;
  final ImagePicker? imagePicker;

  @override
  State<BelongingPhotosSection> createState() =>
      _BelongingPhotosSectionState();
}

class _BelongingPhotosSectionState extends State<BelongingPhotosSection> {
  bool _working = false;

  FileStorage get _fileStorage => widget.fileStorage ?? FileStorage();
  ImagePicker get _imagePicker => widget.imagePicker ?? ImagePicker();

  Future<void> _addPhoto(ImageSource source) async {
    if (_working) return;
    final granted = source == ImageSource.camera
        // ignore: use_build_context_synchronously
        ? await widget.permissionService.ensureCamera(context)
        // ignore: use_build_context_synchronously
        : await widget.permissionService.ensurePhotos(context);
    if (!granted || !mounted) return;
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _working = true);
    try {
      final stored =
          await _fileStorage.saveBelongingPhoto(File(picked.path));
      await widget.photoRepository.add(
        belongingId: widget.belongingId,
        filePath: stored.path,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePhoto(BelongingPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('The photo file will be removed.'),
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
    await _fileStorage.deleteFile(photo.filePath);
    await widget.photoRepository.delete(photo.id);
  }

  void _viewPhoto(BelongingPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Photos', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: _working
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              tooltip: 'Add a photo',
              onPressed: _working ? null : _showAddSheet,
            ),
          ],
        ),
        StreamBuilder<List<BelongingPhoto>>(
          stream: widget.photoRepository.watchFor(widget.belongingId),
          builder: (context, snapshot) {
            final photos = snapshot.data ?? const <BelongingPhoto>[];
            if (photos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No extra photos yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return GestureDetector(
                    onTap: () => _viewPhoto(photo),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(photo.filePath),
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 96,
                              height: 96,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(
                                  Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () => _deletePhoto(photo),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.scrim
                                    .withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
