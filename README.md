# KeepIt

**Keep track of what you own, what you bought, and what you need to do.**

KeepIt is an offline-first, privacy-respecting Flutter app for Android and iOS
built from one shared Dart codebase. There are no accounts, no servers, no
analytics, and no ads — everything stays on your device.

## Features

- **Home** — dashboard with counts, "needs attention" items (expiring
  warranties, upcoming deadlines), recent purchases, and quick actions.
- **Purchases** — full CRUD with statuses (active / returned / refunded /
  exchanged), duplicate warnings (never auto-merge), warranty and return
  summaries, and refund tracking.
- **Receipt scanning** — camera or photo library → on-device OCR (Google ML
  Kit, Latin script) → an editable confirm/discard form. Store, date, and
  total are pre-filled; nothing is ever saved silently. Receipt images are
  stored in app-private storage.
- **Deadlines** — generic deadlines with optional time, recurrence
  (daily/weekly/monthly/yearly), categories, linked purchases, notes, and
  multiple reminders per deadline.
- **Warranties** — status badges (active / expiring soon / expired), duration
  or exact-date expiry entry, automatic 30-day and 1-day expiry reminders.
- **Returns & refunds** — return windows (14/30/60/90-day shortcuts or a
  custom date) with 7-day and 1-day warnings; mark-returned and refund flows
  (amount, date, pending/received).
- **Local notifications** — scheduled entirely on-device. A rationale dialog
  explains why *before* the system prompt, asked only when you enable
  reminders — never at startup. Tapping a notification deep-links to the
  relevant deadline or purchase.
- **My Stuff** — belongings with photos, optional estimated value, brand,
  category, notes, and quantity.
- **Locations** — a hierarchical browser (Home → Bedroom → Drawer → Folder)
  with drill-down, breadcrumbs, rename/move/delete, and cycle-proof parent
  picking.
- **Global search** — one field across purchases, receipts, belongings,
  locations, deadlines, and documents, with inline location breadcrumbs.
- **Documents** — attach files to purchases or belongings; images preview
  inline; confirmed deletes clean up stored files.
- **Backup & restore** — versioned ZIP backups (`keepit-backup-<ts>.zip`
  with `manifest.json`, one JSON per table, and your files), validated
  before restore, with transactional rollback on failure.
- **Settings** — live light/dark/system theme, reminders master toggle,
  app lock (PIN + optional biometric), backup/restore, delete-all with
  double confirmation, and an honest in-app privacy policy.
- **App lock** — optional 4–8 digit PIN (salted SHA-256 in the platform
  keystore/keychain, constant-time verify, lockout after 5 failed attempts),
  locks on launch and after 5 minutes in background.

## Privacy

- All data lives in a local SQLite database on your device.
- Receipt/document photos never leave the phone; OCR runs on-device.
- Backups are user-initiated ZIP files you control.
- Notifications are scheduled locally; no push servers.
- No accounts, no analytics, no ads, no tracking.

## Building

Requires Flutter 3.38+ and JDK 17.

```bash
# Debug
flutter build apk --debug

# Release (configure signing first — see below)
flutter build apk --release
flutter build appbundle

# iOS (macOS + Xcode required)
flutter build ios
```

## Before a production release

1. **Real Android NDK** — development builds here used a stub NDK, so APKs
   are oversized (~1.6 GB debug). Install a real NDK for release builds.
2. **Release signing** — configure your keystore in
   `android/app/build.gradle.kts` / `key.properties`. Never commit the
   keystore or its passwords.
3. **iOS** — build and test on macOS with Xcode (deployment target 15.5).
4. **Device testing** — backup/restore, app lock, and notification flows are
   unit-tested but should be exercised on physical devices.
5. **GitHub** — push the repo to your private repository.

## Permissions (requested only when you use the feature)

| Permission | When asked | Why |
|---|---|---|
| Camera | Tapping "Scan receipt" / "Take photo" | Capture receipts and belonging photos |
| Photos / media | Choosing from gallery | Attach existing images |
| Files | Attaching documents / importing backups | Read files you explicitly pick |
| Notifications | Enabling reminders | Remind you before deadlines |
| Biometric | Enabling biometric unlock | Unlock the app without the PIN |

Android additionally declares `RECEIVE_BOOT_COMPLETED` so reminders survive
a reboot.

## Backup format

`keepit-backup-YYYYMMDD-HHMMSS.zip`:
- `manifest.json` — `formatVersion`, app/schema versions, creation time,
  per-table row counts, file count.
- `tables/*.json` — one JSON array per database table (parents before
  children for FK safety).
- `files/` — `receipts/`, `documents/`, `belongings/` as stored on-device.

Restore validates the manifest first (unknown format versions are rejected),
parses everything into memory before touching data, and rolls both the
database and files back if anything fails.

## Known limitations

- One receipt per purchase (schema constraint).
- OCR is Latin-script only.
- Document preview is images-only.
- Debug APKs are large in this environment due to the stub NDK.

## Project layout

```
lib/
  core/        database (Drift), navigation, theme, permissions,
               notifications, security, utilities
  features/    home, purchases, receipts, warranties, deadlines,
               belongings, locations, documents, search, settings
  shared/      widgets, models, services (backup, file storage, money…)
test/          unit + widget tests (see PHASE*_REPORT.md for counts)
```
