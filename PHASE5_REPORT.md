# KEEPIT — Phase 5 Report: Deadlines, Warranties, Returns & Local Notifications

**Date:** 2026-09-30
**Scope:** Phase 5 only (deadlines UI, warranties UI, return/refund flows, on-device local notifications).
**Toolchain:** Flutter 3.38.7 · Dart 3.10.7 · JDK 17 · compileSdk 36 · AGP 8.11.1 · minSdk 24

## What was built

### 1. Deadlines tab (real, replaces placeholder)
- `lib/features/deadlines/presentation/deadlines_screen.dart` — Overdue / Upcoming / Later / Done segments over a live `watchUpcoming(includeDone: true)` stream. Overdue rows show days-overdue in red; done rows are struck through. Tiles show due date/time, repeat label, and linked purchase name. FAB → `/deadlines/new`.
- `deadline_form_screen.dart` — add/edit: title (validated), due date (required), optional time, repeat rule (none/daily/weekly/monthly/yearly), optional category, optional linked purchase, notes, and three reminder switches (a week before / a day before / on the day). Editing pre-fills the switches from the deadline's existing reminder offsets.
- `deadline_detail_screen.dart` — detail with mark-done/reopen/edit/delete. Completing a **repeating** deadline rolls it to the next occurrence via `ReminderScheduler.nextOccurrence` and keeps the existing reminder offsets (re-planned against the new date); a non-repeating deadline is marked done and its reminders cleared.
- Routes: `/deadlines`, `/deadlines/new`, `/deadlines/:id`, `/deadlines/:id/edit`.

### 2. Warranties UI
- `lib/features/warranties/presentation/warranties_screen.dart` — list at `/purchases/warranties` with purchase name, provider, status badge (Active / Expiring soon / Expired, using the existing `warrantyStatus`/`warrantyDaysRemaining` helpers), and days-left.
- `warranty_form_screen.dart` — add/edit: purchase picker (locked when editing), provider, warranty number, start date, expiry as **duration (years/months/days)** or **exact date**, notes, and the purchase's document section (reused `DocumentsSection`, `documentType: 'warranty'` attachments land on the purchase like other documents).
  - Schema note: only `durationMonths` exists for durations. Whole-month durations are stored in `durationMonths`; anything with days (or an explicit date) is stored as an explicit `expirationDate`. No information is lost, no migration needed.
  - Expiry reminders (30 days + 1 day before) are scheduled when the expiry is in the future, through the permission-gated flow.
- Routes: `/purchases/warranties`, `/purchases/warranties/new?purchaseId=…`, `/purchases/warranties/:warrantyId/edit`. The purchase detail warranty card now has a **Manage** button; purchases without a warranty show **Add warranty**.

### 3. Return windows & refunds (purchase detail)
- `return_window_dialog.dart` — set/edit the return window: 14/30/60/90-day chips from the purchase date (or today when the purchase has no date), or a custom date; optional notes. Saves the `ReturnDeadline` row and schedules 7-day + 1-day reminders.
- **Mark returned**: confirmation → purchase status `returned`, return-deadline row and its reminders/notifications removed.
- `refund_dialog.dart` — amount (defaults to purchase price), date, status (Pending → `pending`, Received → `received`), notes. Saving creates/updates the `Refund` row and moves the purchase to `refunded`. Refund status mapping documented: schema text column is unrestricted; the app uses `pending`/`received` (both already supported by `StatusBadge`).
- Purchase detail now shows **Set return window** / **Mark refunded** actions when none exist, and Edit actions on existing cards.

### 4. Local notifications (on-device only)
- New `lib/core/notifications/` layer:
  - `notification_backend.dart` — `NotificationBackend` interface (init, requestPermissions, schedule, cancel, pendingIds, launchPayload) so all coordination logic is unit-testable.
  - `flutter_notification_backend.dart` — real implementation on `flutter_local_notifications 22.3.1` (22.x named-parameter APIs: `initialize(settings:)`, `cancel(id:)`, `zonedSchedule(id:title:body:scheduledDate:notificationDetails:androidScheduleMode:payload:)`). Timezone via `timezone` + `flutter_timezone` with UTC fallback. Creates the `keepit_reminders` channel (Importance.high).
  - `notification_service.dart` — owns the backend; `ensureInitialized()` (tap-callback with pre-handler tap buffering), `requestPermissions(context)` (rationale-first via `PermissionService`), and `syncReminders()` reconciliation: schedules future pending reminders, marks past-due ones done, cancels orphaned OS notifications. Idempotent — safe on every start.
  - `reminder_coordinator.dart` — single glue point for entity CRUD: `resyncEntity` (delete old reminders + cancel their notifications, create fresh rows from offsets, re-sync) and `clearEntity`. Used by deadline/warranty/return-deadline saves and deletes.
  - `notification_id.dart` — stable int ids from UUID hex (Dart `hashCode` is not stable across runs).
  - `payload_routing.dart` — `'<entityType>:<entityId>'` → `/deadlines/:id`, `/purchases/:id` (warranty/return via owning purchase, with list fallbacks). Pure and unit-tested.
- `lib/shared/services/reminder_planner.dart` — pure planning: `planReminders` (offsets → future fire times via the shared `ReminderScheduler` day arithmetic) and `offsetsFromReminders` (keeps a repeating deadline's reminder choices when it rolls forward).
- `main.dart` — builds the backend/service/coordinator after the DB opens, runs `ensureInitialized()` + `syncReminders()` inside try/catch (notification failure never blocks startup; no user content logged), wires notification taps and cold-start launch payloads to `routeForPayload` → `router.go`.
- Permission behavior: **rationale dialog first** ("Enable reminders? … scheduled on this device only"), OS prompt only after the user taps Continue. Asked only when the user enables reminders (deadline form switches, warranty save with future expiry, return-window save) — never at app start.
- Android: `POST_NOTIFICATIONS` + `RECEIVE_BOOT_COMPLETED` in the manifest; the plugin's `ScheduledNotificationReceiver` / `ActionBroadcastReceiver` / `ScheduledNotificationBootReceiver` declared (restores schedules after reboot); core library desugaring enabled (`desugar_jdk_libs:2.1.4`) as the plugin requires. Scheduling uses `AndroidScheduleMode.inexactAllowWhileIdle` — **no exact-alarm permission requested**.
- No schema changes (still v1). New dependencies: `flutter_local_notifications ^22.3.1`, `timezone ^0.11.0`, `flutter_timezone ^5.1.0` — all verified compatible with Flutter 3.38.7 / Dart 3.10.7 / minSdk 24 / compileSdk 36 / AGP 8.11.1 / Java 17 before adding.

## Verification

- `flutter analyze` — **no issues**.
- `flutter test` — **170/170 passed** (133 pre-existing preserved + 37 new):
  - `notification_id_test.dart` (5): stability, hex parsing, range.
  - `reminder_planner_test.dart` (8): offset→fire-time planning, past-skip, offset derivation/clamping/dedup.
  - `payload_routing_test.dart` (9): all entity types, fallbacks, malformed payloads.
  - `notification_service_test.dart` (13): sync schedules future / marks past-due done / ignores done / cancels orphans / idempotent; coordinator resync replaces, empty offsets clear, clearEntity cancels; tap buffering.
  - `deadline_form_test.dart` (5, widget): title validation, due-date required, permission→schedule flow (rationale first, `requestPermissions` only after Continue), denied-permission saves without reminders + notice, no toggles → no permission prompt.
  - Shared `FakeNotificationBackend` in `test/fake_notification_backend.dart`.
- Android debug build: **BUILD SUCCESSFUL** (`flutter build apk --debug`). APK remains oversized due to the sandbox stub NDK (known limitation, unchanged from Phase 4).
- iOS static review: deployment target 15.5 exceeds plugin minimums (FLN 13.0, flutter_timezone 11.0). `DarwinInitializationSettings()` needs no entitlements or Info.plist usage strings for local notifications; `androidScheduleMode` is Android-only and ignored on iOS; permission requests go through the plugin's iOS implementation behind null-safe `resolvePlatformSpecificImplementation`. No macOS available here — real iOS compilation still requires Xcode.

## Decisions & notes for later phases

- One receipt per purchase (schema) — unchanged, still a known limitation.
- Refund statuses surfaced as Pending/Received → stored `pending`/`received`.
- Warranty durations with a day component (or explicit dates) use `expirationDate`; whole-month durations use `durationMonths`.
- Reminder rows are the source of truth; OS notifications are a best-effort mirror reconciled on every start and after every CRUD operation through `ReminderCoordinator`.
- Notification bodies never include receipt/document contents — titles/notes only.
