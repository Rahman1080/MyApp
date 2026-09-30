import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../../core/database/keepit_database.dart';

/// Reads and writes [UserSettings]. The table holds a single row
/// (id = 'default'); it is created on first access.
class SettingsRepository {
  SettingsRepository(this._db);

  final KeepItDatabase _db;

  static const String _defaultRowId = 'default';

  Future<UserSetting> _loadOrCreate() async {
    final existing = await (_db.select(_db.userSettings)
          ..where((t) => t.id.equals(_defaultRowId)))
        .getSingleOrNull();
    if (existing != null) return existing;

    await _db.into(_db.userSettings).insert(
          UserSettingsCompanion.insert(id: _defaultRowId),
        );
    return (_db.select(_db.userSettings)
          ..where((t) => t.id.equals(_defaultRowId)))
        .getSingle();
  }

  Future<ThemeMode> getThemeMode() async {
    final settings = await _loadOrCreate();
    return switch (settings.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    // Ensure the row exists: on a fresh database the setters may run before
    // any getter, and an UPDATE against zero rows would silently do nothing.
    await _loadOrCreate();
    await (_db.update(_db.userSettings)
          ..where((t) => t.id.equals(_defaultRowId)))
        .write(
      UserSettingsCompanion(
        themeMode: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _setBool(
    UserSettingsCompanion Function(DateTime now) companion,
  ) async {
    // Same as above: make sure there is a row to update.
    await _loadOrCreate();
    await (_db.update(_db.userSettings)
          ..where((t) => t.id.equals(_defaultRowId)))
        .write(companion(DateTime.now()));
  }

  Future<bool> getAppLockEnabled() async =>
      (await _loadOrCreate()).appLockEnabled;

  Future<void> setAppLockEnabled(bool enabled) => _setBool(
        (now) => UserSettingsCompanion(
          appLockEnabled: Value(enabled),
          updatedAt: Value(now),
        ),
      );

  Future<bool> getBiometricUnlockEnabled() async =>
      (await _loadOrCreate()).biometricUnlockEnabled;

  Future<void> setBiometricUnlockEnabled(bool enabled) => _setBool(
        (now) => UserSettingsCompanion(
          biometricUnlockEnabled: Value(enabled),
          updatedAt: Value(now),
        ),
      );

  Future<bool> getRemindersEnabled() async =>
      (await _loadOrCreate()).remindersEnabled;

  Future<void> setRemindersEnabled(bool enabled) => _setBool(
        (now) => UserSettingsCompanion(
          remindersEnabled: Value(enabled),
          updatedAt: Value(now),
        ),
      );

  Future<bool> getPrivacyPolicyAccepted() async =>
      (await _loadOrCreate()).privacyPolicyAccepted;

  Future<void> setPrivacyPolicyAccepted(bool accepted) => _setBool(
        (now) => UserSettingsCompanion(
          privacyPolicyAccepted: Value(accepted),
          updatedAt: Value(now),
        ),
      );

  Future<bool> getOnboardingComplete() async =>
      (await _loadOrCreate()).onboardingComplete;

  Future<void> setOnboardingComplete(bool complete) => _setBool(
        (now) => UserSettingsCompanion(
          onboardingComplete: Value(complete),
          updatedAt: Value(now),
        ),
      );
}
