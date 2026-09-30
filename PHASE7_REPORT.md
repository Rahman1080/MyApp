# Phase 7 Report — Backup/export/import, settings, app lock, privacy policy

Date: 2026-09-30
Status: **Complete**

## What was built

### Backup & restore (`lib/shared/services/backup_service.dart`)
- Versioned ZIP backups: `keepit-backup-YYYYMMDD-HHMMSS.zip` containing
  `manifest.json` (formatVersion 1, appName, appVersion, schemaVersion,
  createdAt, per-table counts, file count), one JSON file per Drift table
  (`tables/*.json`, 15 tables, parents-first for FK safety), and the
  app-private files under `files/` (`receipts/`, `documents/`, `belongings/`).
- `validateBackup()` dry-runs a file without touching data: corrupt ZIPs,
  missing manifests, unknown format versions, and non-KeepIt ZIPs are rejected
  with user-safe messages. Unknown versions are never silently applied.
- `restoreBackup()` parses every table into memory first (format errors abort
  before anything is touched), swaps file dirs aside with a `.bak` fallback,
  wipes/re-inserts rows in one transaction, verifies `PRAGMA foreign_key_check`,
  and rolls both DB and files back on any failure. Zip-slip paths are rejected.
- `wipeAllData()` removes all rows and files, then recreates the default
  settings row. The SQLite file itself is never deleted.
- Export uses the `file_picker` save dialog (`share_plus` was rejected: it
  requires AGP ≥ 8.12.1, KEEPIT uses 8.11.1).

### Settings (`/settings`, entry point: gear icon on Home)
- Appearance: live system/light/dark theme, persisted.
- Reminders master toggle: disabling cancels all OS notifications via the new
  `NotificationService.cancelAllNotifications()` (reminder rows are kept, so
  re-enabling re-syncs); startup sync in `main.dart` now respects the flag.
- App lock: PIN setup/change/remove flows; optional biometric unlock gated
  behind a live biometric prompt; forgot-PIN path explains reinstall+restore
  (no auto-wipe, no silent deletion).
- Backup now / restore from backup (with preview counts and an explicit
  "Replace everything" double-warning) / delete-all with two confirmations.
- About: app version (package_info_plus), offline note, privacy policy link.

### App lock gate (`lib/core/security/app_lock_gate.dart`)
- Locked on launch when app lock is enabled and a PIN exists; re-locks after
  5 minutes in background. Notification taps while locked are buffered by
  `NotificationService` and delivered after unlock (verified in code).
- PIN: 4–8 digits, salted SHA-256 in Keystore/Keychain via
  `flutter_secure_storage` v10, constant-time verify, lockout after 5 failed
  attempts (30 s), no plaintext storage/logging.

### Privacy
- `/settings/privacy`: plain-language policy (on-device storage, no accounts/
  analytics/ads, on-device OCR, user-initiated backups only, salted PIN hash).
- First-launch "Your data stays yours" notice; acceptance persisted in the new
  `user_settings.privacy_policy_accepted` v2 column.

### Schema migration v1 → v2 (real, tested)
- Adds `user_settings.reminders_enabled` (default true) and
  `privacy_policy_accepted` (default false) via `m.addColumn`.
- New test builds a hand-crafted v1 database file, opens it with the current
  schema, and proves existing rows survive with the new defaults applied.

### Platform configuration
- Android: `USE_BIOMETRIC` permission; `MainActivity` now extends
  `FlutterFragmentActivity` (local_auth requirement); `LaunchTheme` parents
  changed to AppCompat (prevents crashes on Android ≤ 8); `allowBackup="false"`.
- iOS: `NSFaceIDUsageDescription` added; deployment target stays 15.5
  (satisfies local_auth's iOS 13+ and ML Kit's 15.5).

## Bugs found and fixed during this phase
1. `pin_lock_service.dart` imported `package:local_auth/error_codes.dart`,
   which does not exist in local_auth 3.0.2 — removed; `LocalAuthException`
   comes from `local_auth.dart`.
2. `SettingsRepository` setters did blind `UPDATE`s: on a fresh database they
   silently affected zero rows (getters worked because they create the row).
   Setters now ensure the row exists first.
3. Old `main.dart` called `createNotificationBackend()`, which existed nowhere
   — replaced with direct `FlutterNotificationBackend()` construction.
4. file_picker 13 API: no `.platform` accessor; `saveFile` takes bytes and
   returns `Uri?`; `pickFiles` returns `List<PlatformFile>`. Settings screen
   updated.
5. Test/code API mismatches corrected (`PinLockService(secureStore:)`,
   `PinException`, `authenticateWithBiometrics(reason:)`).

## Test & build results
- `flutter analyze lib test`: **no issues**.
- `flutter test`: **213/213 passed** (180 pre-existing + 33 new: 11 backup,
  12 PIN lock, 10 settings repository; migration suite updated to v2 with a
  real v1→v2 test).
- `flutter build apk --debug`: **success**
  (`build/app/outputs/flutter-apk/app-debug.apk`, 2026-09-30 ~04:57 UTC).
  Known caveat unchanged: stub NDK → ~1.6 GB APK; real NDK required in Phase 8.
- iOS: static compatibility review passed (deployment target 15.5,
  NSFaceIDUsageDescription present, flutter_secure_storage/file_picker need no
  extra entitlements; on-device compile still requires macOS/Xcode).
- UI review: Material 3, light/dark aware, ≥48 dp targets, ListView-based
  screens adapt to small phones/tablets; destructive actions double-confirmed.
- Regression: no schema changes beyond v1→v2; all 180 pre-existing tests pass
  unchanged in behavior.

## Notes for Phase 8
- Nothing from KEEPIT has been pushed to GitHub (connector still lacks repo
  selection for `Rahman1080/MyApp`).
- Real NDK still required before any production release build.
- `keepit_database.g.dart` still contains the hand-applied v2 edits from the
  build_runner failure (`dart compile does not support build hooks`); the
  migration is covered by a real test, but regenerating with `dart build`
  should be attempted in Phase 8.
- Backup/restore and lock flows are unit-tested but have not been exercised on
  a physical device (no device attached in this environment).
