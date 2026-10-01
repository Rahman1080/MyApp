import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/keepit_database.dart' show Reminder;

import '../../../core/notifications/notification_service.dart';
import '../../../core/security/pin_lock_service.dart';
import '../../settings/data/settings_repository.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../moves/presentation/moves_screen.dart';
import '../../ask/presentation/ask_screen.dart';
import '../../organize/presentation/organize_screen.dart';
import '../../household/presentation/household_dashboard_screen.dart';
import '../../sync/presentation/sync_screen.dart';
import 'privacy_policy_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/backup_service.dart';
import '../../../shared/widgets/keepit_card.dart';

/// Settings: appearance, reminders, app lock, backup/restore, about.
///
/// Every change here is persisted immediately and, where relevant, takes
/// effect immediately (theme, reminder scheduling, lock behavior).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsRepository,
    required this.pinLock,
    required this.backupService,
    required this.themeModeListenable,
    required this.notificationService,
  });

  static const routePath = '/settings';

  final SettingsRepository settingsRepository;
  final PinLockService pinLock;
  final BackupService backupService;
  final ValueNotifier<ThemeMode> themeModeListenable;
  final NotificationService notificationService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _remindersEnabled = true;
  bool _appLockEnabled = false;
  bool _biometricEnabled = false;
  bool _hasPin = false;
  bool _biometricAvailable = false;
  String? _appVersion;
  bool _busy = false;
  int? _pendingReminderCount;
  String? _nextReminderSummary;
  bool _testingNotification = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.settingsRepository;
    final results = await Future.wait([
      repo.getRemindersEnabled().catchError((_) => true),
      repo.getAppLockEnabled().catchError((_) => false),
      repo.getBiometricUnlockEnabled().catchError((_) => false),
      widget.pinLock.hasPin().catchError((_) => false),
      widget.pinLock.canUseBiometrics().catchError((_) => false),
      PackageInfo.fromPlatform().then((i) => i.version).catchError((_) => ''),
      widget.notificationService.pendingNotificationCount().catchError((_) => 0),
      widget.notificationService.getNextUpcomingReminder().catchError((_) => null),
    ]);
    if (!mounted) return;
    final nextReminder = results[7] as Reminder?;
    String? nextSummary;
    if (nextReminder != null) {
      final dateStr = DateFormat.MMMd().add_jm().format(nextReminder.remindAt);
      nextSummary = '${nextReminder.title} ($dateStr)';
    }
    setState(() {
      _remindersEnabled = results[0] as bool;
      _appLockEnabled = results[1] as bool;
      _biometricEnabled = results[2] as bool;
      _hasPin = results[3] as bool;
      _biometricAvailable = results[4] as bool;
      final version = results[5] as String;
      if (version.isNotEmpty) _appVersion = version;
      _pendingReminderCount = results[6] as int;
      _nextReminderSummary = nextSummary;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ theme

  Future<void> _setTheme(ThemeMode mode) async {
    await widget.settingsRepository.setThemeMode(mode);
    widget.themeModeListenable.value = mode;
  }

  // -------------------------------------------------------------- reminders

  Future<void> _setReminders(bool enabled) async {
    setState(() => _remindersEnabled = enabled);
    try {
      await widget.settingsRepository.setRemindersEnabled(enabled);
      if (enabled) {
        if (!mounted) return;
        await widget.notificationService.requestPermissions(context);
        await widget.notificationService.syncReminders();
      } else {
        await widget.notificationService.cancelAllNotifications();
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _remindersEnabled = !enabled);
        _snack('Could not update reminder settings.');
      }
    }
  }

  Future<void> _sendTestNotification() async {
    if (_testingNotification) return;
    setState(() => _testingNotification = true);
    try {
      if (!mounted) return;
      await widget.notificationService.requestPermissions(context);
      await widget.notificationService.showTestNotification();
      _snack('Test notification sent. Check your status bar!');
    } catch (e) {
      _snack('Failed to send test notification: $e');
    } finally {
      if (mounted) setState(() => _testingNotification = false);
    }
  }

  Future<void> _scheduleTestReminder() async {
    if (_testingNotification) return;
    setState(() => _testingNotification = true);
    try {
      if (!mounted) return;
      await widget.notificationService.requestPermissions(context);
      await widget.notificationService.scheduleTestReminder(secondsFromNow: 10);
      await _load();
      _snack('Reminder scheduled for 10s from now. Lock screen to test!');
    } catch (e) {
      _snack('Failed to schedule test reminder: $e');
    } finally {
      if (mounted) setState(() => _testingNotification = false);
    }
  }

  // --------------------------------------------------------------- app lock

  Future<void> _toggleAppLock(bool enable) async {
    if (enable == _appLockEnabled) return;
    if (enable) {
      final changed =
          await context.push<bool>('${SettingsScreen.routePath}/pin?mode=setup');
      if (changed == true) {
        await _load();
        _snack('App lock enabled.');
      }
    } else {
      final changed =
          await context.push<bool>('${SettingsScreen.routePath}/pin?mode=remove');
      if (changed == true) {
        await _load();
        _snack('App lock disabled.');
      }
    }
  }

  Future<void> _changePin() async {
    final changed =
        await context.push<bool>('${SettingsScreen.routePath}/pin?mode=change');
    if (changed == true) {
      await _load();
      _snack('PIN changed.');
    }
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      final ok = await widget.pinLock.authenticateWithBiometrics(
        reason: 'Confirm it is you to enable biometric unlock',
      );
      if (!mounted) return;
      if (!ok) {
        _snack('Biometric unlock was not confirmed.');
        return;
      }
    }
    await widget.settingsRepository.setBiometricUnlockEnabled(enable);
    if (mounted) setState(() => _biometricEnabled = enable);
  }

  // ----------------------------------------------------------------- backup

  Future<void> _createBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    final progress = ValueNotifier<double>(0);
    var dialogOpen = false;
    try {
      // The progress dialog is shown while the ZIP is assembled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        dialogOpen = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, value, _) => AlertDialog(
              title: const Text('Creating backup'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value),
                  const SizedBox(height: 12),
                  Text('${(value * 100).round()}%'),
                ],
              ),
            ),
          ),
        );
      });

      final zip = await widget.backupService.createBackup(
        appVersion: _appVersion ?? 'unknown',
        onProgress: (value) => progress.value = value,
      );
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      final bytes = await zip.readAsBytes();
      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Save backup',
        fileName: p.basename(zip.path),
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      await zip.delete().catchError((_) => zip);
      if (savedUri == null) {
        _snack('Backup cancelled.');
        return;
      }
      _snack('Backup saved.');
    } catch (_) {
      await _showError(
        'The backup could not be created. Please try again.',
      );
    } finally {
      progress.dispose();
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a KeepIt backup',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return; // user cancelled

    final file = File(path);
    BackupPreview preview;
    try {
      preview = await widget.backupService.validateBackup(file);
    } on BackupException catch (e) {
      await _showError(e.message);
      return;
    } catch (_) {
      await _showError('This file could not be read as a KeepIt backup.');
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RestoreConfirmDialog(preview: preview),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.backupService.restoreBackup(file);
      await _applyRestoredSettings();
      _snack('Backup restored.');
    } on BackupException catch (e) {
      await _showError(e.message);
    } catch (_) {
      await _showError(
        'The backup could not be restored. Your current data was left '
        'untouched.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Applies the restored settings row (theme, reminders) to the live app.
  Future<void> _applyRestoredSettings() async {
    final repo = widget.settingsRepository;
    widget.themeModeListenable.value = await repo.getThemeMode();
    if (await repo.getRemindersEnabled()) {
      await widget.notificationService.syncReminders();
    } else {
      await widget.notificationService.cancelAllNotifications();
    }
    await _load();
  }

  // -------------------------------------------------------------- delete all

  Future<void> _deleteAllData() async {
    if (_busy) return;
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This permanently removes every purchase, receipt, photo, '
          'document, deadline and reminder from this device. This cannot be '
          'undone.\n\nIf you want a copy first, create a backup before '
          'deleting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my data'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: const Text(
          'Everything will be deleted from this device right now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.notificationService.cancelAllNotifications();
      await widget.backupService.wipeAllData();
      await widget.pinLock.clearPin();
      // The wipe resets settings to defaults; mirror that in live state.
      widget.themeModeListenable.value = ThemeMode.system;
      await _load();
      _snack('All data deleted.');
    } catch (_) {
      await _showError('Some data could not be deleted. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const _SectionHeader('Appearance'),
          KeepitCard(
            padding: const EdgeInsets.all(12),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: widget.themeModeListenable,
              builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.settings_suggest_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selected) => _setTheme(selected.first),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const _SectionHeader('Notifications & Security'),
          KeepitCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Reminders'),
                  subtitle: const Text(
                    'Get notified about deadlines, warranties and returns.',
                  ),
                  value: _remindersEnabled,
                  onChanged: _setReminders,
                ),
                if (_remindersEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.notifications_active_outlined,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _pendingReminderCount != null
                                      ? '$_pendingReminderCount reminders active with system'
                                      : 'Reminders active with system',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_nextReminderSummary != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Next: $_nextReminderSummary',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _testingNotification ? null : _sendTestNotification,
                                icon: const Icon(Icons.send_outlined, size: 16),
                                label: const Text('Send Test Now'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _testingNotification ? null : _scheduleTestReminder,
                                icon: const Icon(Icons.timer_outlined, size: 16),
                                label: const Text('Schedule Test (10s)'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: const Text('Lock app with PIN'),
                  subtitle: const Text(
                    'Require your PIN every time KeepIt opens.',
                  ),
                  value: _appLockEnabled,
                  onChanged: _toggleAppLock,
                ),
                if (_hasPin) ...[
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('Change PIN'),
                    leading: const Icon(Icons.pin_outlined),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: _changePin,
                  ),
                  if (_biometricAvailable) ...[
                    const Divider(height: 1, indent: 16),
                    SwitchListTile(
                      title: const Text('Unlock with biometrics'),
                      subtitle: const Text(
                        'Use fingerprint or face unlock instead of typing your PIN.',
                      ),
                      value: _biometricEnabled,
                      onChanged: _toggleBiometric,
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          const _SectionHeader('Organization & Tools'),
          KeepitCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Inventory reports'),
                  subtitle: const Text(
                    'PDF reports and evidence exports of your belongings.',
                  ),
                  leading: const Icon(Icons.summarize_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(ReportsScreen.routePath),
                  enabled: !_busy,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  title: const Text('Moving Mode'),
                  subtitle: const Text(
                    'Track packing, transit, and unpacking for a move.',
                  ),
                  leading: const Icon(Icons.local_shipping_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(MovesScreen.routePath),
                  enabled: !_busy,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  title: const Text('Smart Organization'),
                  subtitle: const Text(
                    'Review suggestions to tidy up your inventory.',
                  ),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(OrganizeScreen.routePath),
                  enabled: !_busy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const _SectionHeader('Intelligence'),
          KeepitCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: const Text('Ask KEEPIT'),
              subtitle: const Text(
                'Ask about your stuff in plain language.',
              ),
              leading: const Icon(Icons.chat_bubble_outline),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => context.push(AskScreen.routePath),
              enabled: !_busy,
            ),
          ),
          const SizedBox(height: 16),

          const _SectionHeader('Household & Sharing'),
          KeepitCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Household Command Center'),
                  subtitle: const Text(
                    'Dashboard of members, privacy, and locations.',
                  ),
                  leading: const Icon(Icons.dashboard_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () =>
                      context.push(HouseholdDashboardScreen.routePath),
                  enabled: !_busy,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  title: const Text('Sync with another device'),
                  subtitle: const Text(
                    'Export or import sync files manually.',
                  ),
                  leading: const Icon(Icons.sync_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(SyncScreen.routePath),
                  enabled: !_busy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const _SectionHeader('Data & Storage'),
          KeepitCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Back up now'),
                  subtitle: const Text(
                    'Save everything to a ZIP file you control.',
                  ),
                  leading: const Icon(Icons.backup_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: _createBackup,
                  enabled: !_busy,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  title: const Text('Restore from backup'),
                  subtitle: const Text(
                    'Replaces all current data with a backup file.',
                  ),
                  leading: const Icon(Icons.restore_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: _restoreBackup,
                  enabled: !_busy,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  title: Text(
                    'Delete all data',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Permanently remove everything from this device.',
                  ),
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  onTap: _deleteAllData,
                  enabled: !_busy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const _SectionHeader('About & Privacy'),
          KeepitCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Privacy policy'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push(PrivacyPolicyScreen.routePath),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  title: const Text('Version'),
                  subtitle: Text(_appVersion ?? '…'),
                  leading: const Icon(Icons.info_outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'KeepIt works fully offline. Your data never leaves this device unless you export a backup yourself.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.mintAccent,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Confirmation shown before a restore. Lists what the backup contains and
/// makes the destructive consequence explicit — twice, in plain language.
class _RestoreConfirmDialog extends StatelessWidget {
  const _RestoreConfirmDialog({required this.preview});

  final BackupPreview preview;

  static const _labels = {
    'user_settings': 'Settings',
    'categories': 'Categories',
    'tags': 'Tags',
    'locations': 'Locations',
    'purchases': 'Purchases',
    'products': 'Products',
    'receipts': 'Receipts',
    'warranties': 'Warranties',
    'return_deadlines': 'Return deadlines',
    'refunds': 'Refunds',
    'deadlines': 'Deadlines',
    'belongings': 'Belongings',
    'documents': 'Documents',
    'reminders': 'Reminders',
    'tag_links': 'Tag links',
  };

  @override
  Widget build(BuildContext context) {
    final rows = _labels.entries
        .where((e) => (preview.counts[e.key] ?? 0) > 0)
        .map((e) => '${e.value}: ${preview.counts[e.key]}')
        .toList();
    return AlertDialog(
      title: const Text('Restore this backup?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Created ${_formatDate(preview.createdAt)} · '
              'KeepIt ${preview.appVersion}',
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('This backup contains no records.')
            else
              ...rows.map((r) => Text('• $r')),
            if (preview.fileCount > 0)
              Text('• Files: ${preview.fileCount}'),
            const SizedBox(height: 12),
            Text(
              'Restoring REPLACES everything currently in KeepIt. Your '
              'current data will be permanently deleted.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Replace everything'),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return 'an unknown date';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
