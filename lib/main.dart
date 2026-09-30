import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/app/keepit_app.dart';
import 'core/database/database_provider.dart';
import 'core/database/keepit_database.dart';
import 'core/database/repositories/reminder_repository.dart';
import 'core/notifications/flutter_notification_backend.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/reminder_coordinator.dart';
import 'core/security/app_lock_gate.dart';
import 'core/security/pin_lock_service.dart';
import 'core/security/secure_store.dart';
import 'features/settings/data/settings_repository.dart';
import 'shared/services/backup_service.dart';

/// Bootstraps the database, notification plumbing, and app-wide services,
/// then hands control to [AppLockGate], which decides whether the app opens
/// locked. A database failure shows an explanatory screen instead of
/// crashing.
Future<void> bootstrapAndRun() async {
  WidgetsFlutterBinding.ensureInitialized();

  KeepItDatabase? database;
  ThemeMode themeMode = ThemeMode.system;
  Object? initError;

  try {
    database = KeepItDatabase(openKeepItDatabase());
    // Force the connection open now so a failure surfaces here, not on the
    // first user interaction.
    themeMode = await SettingsRepository(database).getThemeMode();
  } catch (error) {
    initError = error;
    await database?.close().catchError((_) {});
    database = null;
  }

  if (initError != null || database == null) {
    runApp(DatabaseErrorApp(error: initError));
    return;
  }

  // Notification plumbing is assembled here so it survives for the app's
  // lifetime. Initialization and the startup sync are wrapped in try/catch:
  // reminders are a convenience layer over the database, which is the
  // source of truth.
  final settingsRepository = SettingsRepository(database);
  final reminderRepository = ReminderRepository(database);
  final notificationService = NotificationService(
    backend: FlutterNotificationBackend(),
    reminders: reminderRepository,
  );
  final reminderCoordinator = ReminderCoordinator(
    reminders: reminderRepository,
    notifications: notificationService,
  );
  try {
    await notificationService.ensureInitialized();
    if (await settingsRepository.getRemindersEnabled()) {
      await notificationService.syncReminders();
    }
  } catch (_) {
    // Best-effort: the app works fully without scheduled notifications.
    // Deliberately no details logged — errors here could otherwise echo
    // user content into logs.
    if (kDebugMode) debugPrint('KeepIt: notification setup skipped.');
  }

  final Directory filesRoot = await getApplicationDocumentsDirectory();
  final backupService = BackupService(db: database, filesRoot: filesRoot);
  final pinLock = PinLockService(secureStore: PlatformSecureStore());

  runApp(
    AppLockGate(
      database: database,
      settingsRepository: settingsRepository,
      pinLock: pinLock,
      backupService: backupService,
      initialThemeMode: themeMode,
      notificationService: notificationService,
      reminderCoordinator: reminderCoordinator,
    ),
  );
}

void main() {
  bootstrapAndRun();
}
