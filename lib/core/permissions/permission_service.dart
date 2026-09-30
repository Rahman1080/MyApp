import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Central place for runtime permission requests.
///
/// Permissions are requested ONLY at the moment the user taps an action that
/// needs them (scan / attach), never at app start. A short rationale is shown
/// first so the request is never a surprise. Denied states are handled
/// gracefully: the user gets an explanation and a shortcut to system settings
/// instead of a dead end or a crash.
class PermissionService {
  const PermissionService();

  /// Ensures camera access for receipt scanning.
  ///
  /// Shows a rationale dialog first, then requests the permission.
  /// Returns true when the camera can be used.
  Future<bool> ensureCamera(BuildContext context) {
    return _ensure(
      context,
      permission: Permission.camera,
      title: 'Camera access',
      rationale: 'KeepIt needs camera access to scan your receipt. '
          'The photo stays on this device and is never uploaded.',
    );
  }

  /// Ensures photo-library access for picking an existing receipt photo.
  Future<bool> ensurePhotos(BuildContext context) {
    return _ensure(
      context,
      permission: Permission.photos,
      title: 'Photo library access',
      rationale: 'KeepIt needs access to your photos so you can pick a '
          'receipt image. Nothing is uploaded; images stay on this device.',
    );
  }

  Future<bool> _ensure(
    BuildContext context, {
    required Permission permission,
    required String title,
    required String rationale,
  }) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) return true;

    if (!context.mounted) return false;
    final proceed = await _showRationale(context, title, rationale);
    if (!proceed || !context.mounted) return false;

    status = await permission.request();
    if (status.isGranted || status.isLimited) return true;

    if (!context.mounted) return false;
    if (status.isPermanentlyDenied) {
      _showPermanentlyDenied(context, title);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title was denied, so this action was skipped.')),
      );
    }
    return false;
  }

  /// Notifications gate: shows KeepIt's own rationale first, then delegates
  /// to [request] for the OS prompt (or returns the stored grants). The user
  /// taps "Allow" here before ever seeing the system dialog.
  Future<bool> ensureNotifications(
    BuildContext context, {
    required Future<bool> Function() request,
  }) async {
    final proceed = await _showRationale(
      context,
      'Enable reminders?',
      'KeepIt can remind you before deadlines, return windows and warranties '
      'expire. Reminders are scheduled on this device only — nothing leaves '
      'your phone.',
    );
    if (!proceed) return false;
    final granted = await request();
    if (!granted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications were denied, so this was saved without reminders.',
          ),
        ),
      );
    }
    return granted;
  }

  Future<bool> _showRationale(
    BuildContext context,
    String title,
    String rationale,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(rationale),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showPermanentlyDenied(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title is turned off. You can enable it in system settings.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }
}
