# KEEPIT — Phase 3 Report

**Date:** 2026-09-30 (UTC)
**Scope:** Real Home dashboard, Purchases list/search/filter/sort, Purchase detail,
Add/Edit/Delete purchase UI, duplicate-warning flow, widget tests, analyzer,
debug-APK gate, iOS static review.

## What was built

### Home dashboard
- `lib/features/home/presentation/home_view_model.dart` — loads a snapshot from
  the real repositories (no watch streams; one-shot `getAll()` /
  `getUpcoming()` to stay FakeAsync-safe in widget tests), exposes loading /
  totals / attention items / recent purchases.
- `lib/features/home/presentation/home_screen.dart` — greeting header, stat
  cards (Purchases, total value, expiring soon), "Needs attention" section
  (return overdue / warranty expiring), recent-purchases list, clearly labeled
  placeholders for later phases (camera, belongings, backup).

### Purchases
- `lib/features/purchases/presentation/purchases_screen.dart` — list with
  search field, status filter chips (All / Active / Returned / …), sort menu
  (date, name, price), status badges per row, empty-state.
- `lib/features/purchases/presentation/widgets/purchase_list_tile.dart` —
  shared row (name, store, date, price, status badge).
- `lib/features/purchases/presentation/purchase_detail_screen.dart` — full
  record with computed warranty/return summaries, Edit and Delete actions,
  delete confirmation (no auto-merge/delete anywhere).
- `lib/features/purchases/presentation/purchase_form_screen.dart` — add/edit
  form (name, brand, store, price, date, quantity, payment method, notes,
  status), validation, saving spinner, duplicate-warning integration.
- `lib/features/purchases/presentation/widgets/duplicate_dialog.dart` —
  "Possible duplicate" dialog with **View existing**, **Cancel**,
  **Create anyway**. Never merges or deletes automatically.

### Navigation (go_router shell, unchanged bottom tabs)
- `/purchases/new`, `/purchases/:id`, `/purchases/:id/edit`, `/coming-soon`.
- Router factory: `createAppRouter(database: …)` injects the shared database.

### Repository additions (supporting one-shot reads)
- `PurchaseRepository.getAll()` and `DeadlineRepository.getUpcoming()` added
  alongside existing watch streams. Pure additions; no behavior changes.

## Gates — all green

| Gate | Result |
|---|---|
| `flutter test` (full suite) | **112/112 passed** (107 Phase 2 + 5 new widget tests) |
| `flutter analyze` | **No issues found!** (14.4s) |
| Debug APK | ✓ Built `build/app/outputs/flutter-apk/app-debug.apk` |
| iOS static review | **Pass** — no new dependencies, no `dart:io`/platform-specific code in new UI; database via `NativeDatabase` + path_provider (iOS-compatible). Xcode compile still requires macOS. |

### Widget tests (5 new)
- `test/home_screen_test.dart` (2): empty state; counts + attention items +
  recent purchases (uses `dragUntilVisible` for lazy list items).
- `test/purchase_form_test.dart` (3): name required; duplicate dialog appears
  with View/Cancel/Create-anyway and `onSaved` not called; clean save when no
  duplicate; Cancel aborts the save.

## Bugs found and fixed during Phase 3

1. **Real app bug — lazy ListView form:** the save button lived below the fold
   of a lazy `ListView`, so off-screen fields were destroyed and
   `Form.validate()` silently skipped the required name field. Fixed by
   switching the form to `SingleChildScrollView` + eager `Column`, with a
   `Key('savePurchaseButton')` and `tester.ensureVisible(...)` in tests.
2. **Drift stream teardown under FakeAsync:** cancelling a watch stream leaves
   a `Timer.run` pending, hanging `db.close()` and poisoning later queries.
   `openInMemoryDatabase()` now wraps the connection with
   `closeStreamsSynchronously: true` (test-only, documented in
   `database_provider.dart`).
3. **`watch*().first` poisons `db.close()` in widget tests:** even with the
   above, a reentrant cancel from `.first` (during event dispatch) left
   `db.close()` hanging. Rule adopted: widget tests use one-shot
   `.get()`/`getAll()`/`getUpcoming()` — never `watch*().first`. Pure-Dart
   Phase 2 tests (real async) are unaffected.
4. **Lazy-list test assertions:** dashboard stats asserted after scrolling to
   the bottom had been destroyed by the lazy `ListView`. Assertions reordered
   (top-of-screen first, then scroll).

## Compromises / caveats

- **APK is 1.3 GB** (debug): the sandbox NDK r28c download is blocked, so a
  stub NDK is used and native libraries (`libflutter.so` × 3 ABIs, Vulkan
  validation layer) are unstripped. Functionally installable for device/
  emulator testing; a production build needs a genuine NDK (same caveat as
  Phase 1/2).
- Camera/OCR, real notifications, belongings CRUD, backup/restore, and app lock
  remain clearly labeled placeholders — no fake production behavior.
- `~/workspace/keepit` is not a git repo yet; GitHub `Rahman1080/MyApp` is
  still empty and the connector cannot access it until the repo is selected
  in GitHub App installation settings. Nothing pushed.

## Next (Phase 4, not started)

Camera/receipt capture, real notification scheduling, belongings CRUD —
per the phased plan, one phase at a time.
