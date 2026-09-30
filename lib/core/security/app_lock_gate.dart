import 'package:flutter/material.dart';

import '../app/keepit_app.dart';
import '../theme/app_theme.dart';
import '../../core/database/keepit_database.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_coordinator.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/lock_screen.dart';
import '../../shared/services/backup_service.dart';
import 'pin_lock_service.dart';

/// Decides whether the app opens locked, and re-locks it after it has been
/// in the background for a while.
///
/// - On launch: locked when the user enabled app lock *and* a PIN exists.
/// - On resume: re-locks when the app was hidden for more than
///   [_backgroundLockAfter] and a PIN is still set.
/// - A notification tap that arrives while locked is buffered by
///   [NotificationService] and delivered after unlock, so nothing crashes.
///
/// Locking rebuilds [KeepItApp], which drops in-memory UI state — a
/// deliberate privacy property, not a bug.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.database,
    required this.settingsRepository,
    required this.pinLock,
    required this.backupService,
    required this.initialThemeMode,
    required this.notificationService,
    required this.reminderCoordinator,
  });

  final KeepItDatabase database;
  final SettingsRepository settingsRepository;
  final PinLockService pinLock;
  final BackupService backupService;
  final ThemeMode initialThemeMode;
  final NotificationService notificationService;
  final ReminderCoordinator reminderCoordinator;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

enum _GatePhase { loading, locked, unlocked }

class _AppLockGateState extends State<AppLockGate> {
  static const _backgroundLockAfter = Duration(minutes: 5);

  _GatePhase _phase = _GatePhase.loading;
  DateTime? _backgroundedAt;
  late final ValueNotifier<ThemeMode> _themeMode =
      ValueNotifier(widget.initialThemeMode);
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onHide: () => _backgroundedAt = DateTime.now(),
      onResume: _maybeRelock,
    );
    _checkLock();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  Future<void> _checkLock() async {
    var locked = false;
    try {
      locked = await widget.settingsRepository.getAppLockEnabled() &&
          await widget.pinLock.hasPin();
    } catch (_) {
      locked = false;
    }
    if (!mounted) return;
    setState(() {
      _phase = locked ? _GatePhase.locked : _GatePhase.unlocked;
    });
  }

  void _maybeRelock() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null || _phase != _GatePhase.unlocked) return;
    if (DateTime.now().difference(backgroundedAt) < _backgroundLockAfter) {
      return;
    }
    () async {
      final enabled = await widget.settingsRepository
          .getAppLockEnabled()
          .catchError((_) => false);
      final hasPin = await widget.pinLock.hasPin().catchError((_) => false);
      if (enabled && hasPin && mounted) {
        setState(() => _phase = _GatePhase.locked);
      }
    }();
  }

  void _unlock() {
    setState(() => _phase = _GatePhase.unlocked);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.loading:
        return MaterialApp(
          title: 'KeepIt',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        );
      case _GatePhase.locked:
        return MaterialApp(
          title: 'KeepIt',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _themeMode.value,
          home: LockScreen(
            pinLock: widget.pinLock,
            settingsRepository: widget.settingsRepository,
            onUnlock: _unlock,
          ),
        );
      case _GatePhase.unlocked:
        return KeepItApp(
          database: widget.database,
          settingsRepository: widget.settingsRepository,
          pinLock: widget.pinLock,
          backupService: widget.backupService,
          themeModeListenable: _themeMode,
          notificationService: widget.notificationService,
          reminderCoordinator: widget.reminderCoordinator,
        );
    }
  }
}
