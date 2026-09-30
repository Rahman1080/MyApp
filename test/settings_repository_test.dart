import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/features/settings/data/settings_repository.dart';

void main() {
  late KeepItDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = openInMemoryDatabase();
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  group('theme mode', () {
    test('defaults to system', () async {
      expect(await repo.getThemeMode(), ThemeMode.system);
    });

    test('round-trips light and dark', () async {
      await repo.setThemeMode(ThemeMode.dark);
      expect(await repo.getThemeMode(), ThemeMode.dark);
      await repo.setThemeMode(ThemeMode.light);
      expect(await repo.getThemeMode(), ThemeMode.light);
    });
  });

  group('new v2 flags', () {
    test('reminders are enabled by default', () async {
      expect(await repo.getRemindersEnabled(), isTrue);
    });

    test('reminders toggle persists', () async {
      await repo.setRemindersEnabled(false);
      expect(await repo.getRemindersEnabled(), isFalse);
      await repo.setRemindersEnabled(true);
      expect(await repo.getRemindersEnabled(), isTrue);
    });

    test('privacy policy is not accepted by default', () async {
      expect(await repo.getPrivacyPolicyAccepted(), isFalse);
    });

    test('privacy acceptance persists', () async {
      await repo.setPrivacyPolicyAccepted(true);
      expect(await repo.getPrivacyPolicyAccepted(), isTrue);
    });
  });

  group('app lock flags', () {
    test('app lock and biometrics default to off', () async {
      expect(await repo.getAppLockEnabled(), isFalse);
      expect(await repo.getBiometricUnlockEnabled(), isFalse);
    });

    test('app lock flag persists', () async {
      await repo.setAppLockEnabled(true);
      expect(await repo.getAppLockEnabled(), isTrue);
    });

    test('biometric flag persists', () async {
      await repo.setBiometricUnlockEnabled(true);
      expect(await repo.getBiometricUnlockEnabled(), isTrue);
    });
  });

  group('onboarding', () {
    test('defaults to incomplete and persists', () async {
      expect(await repo.getOnboardingComplete(), isFalse);
      await repo.setOnboardingComplete(true);
      expect(await repo.getOnboardingComplete(), isTrue);
    });
  });
}
