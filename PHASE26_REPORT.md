# Phase 26 Report — Missing UI Completion (Phases 16, 17, 18, 21, 22)

**Date:** 2026-09-30
**Status:** COMPLETE and verified in sandbox.

## What this phase did

The Phase 25 audit noted that five phases had working domain logic but no
user-facing screens, making those features unreachable from the app. This
phase built the missing UI for all five, wired them into navigation, and
added widget tests.

## New screens

| Phase | Screen | Route | Entry point |
|-------|--------|-------|-------------|
| 16 | `AskScreen` — conversational grounded search with example prompts, chat history, tappable result links | `/ask` | Settings → Ask KEEPIT |
| 17 | `SyncScreen` — device ID (copy), export sync file (share), import sync file (pick), conflict resolution UI (keep mine / keep theirs / keep newest) | `/sync` | Settings → Sync with another device |
| 18 | `OrganizeScreen` — suggestion cards with type icons, affected-item chips, Review & apply (with location/category pickers) and Dismiss; re-scan; all-good empty state | `/organize` | Settings → Smart Organization |
| 21 | `HouseholdDashboardScreen` — totals card, privacy breakdown bar, per-member cards, per-location list; pull-to-refresh | `/household-dashboard` | Settings → Household Command Center |
| 22 | `LifetimeRecordScreen` — details, acquisition/disposition, history timeline, warranties, service & claims, purchase, documents; JSON export via share | `/belongings/:id/lifetime` | Item detail → Lifetime Record card |

## Supporting changes

- `SyncService`: added public `importData()` (file-based import) and a
  `deviceId` getter; previously `_importRemote` was private and the device
  ID was inaccessible to UI.
- New `DeviceIdProvider`: stable per-device sync ID, generated once
  (128-bit random) and persisted in the app documents directory. Shown to
  the user only; never transmitted automatically.
- `SyncScreen` resolves the device ID lazily with a loading state, and
  accepts an injectable `SyncService` for tests.
- `app_router.dart`: 4 new top-level routes + nested `lifetime` route under
  belonging detail; 4 new service instantiations.
- `settings_screen.dart`: 4 new entries (Ask, Organize, Dashboard, Sync).
- `belonging_detail_screen.dart`: Lifetime Record card linking to the new
  route.

## Design decisions

- Sync stays **manual peer-to-peer** (export/import JSON files the user
  moves themselves). No auto-upload, matching Phase 17's offline-first
  contract. A cloud `SyncProvider` can be plugged in later without UI
  changes.
- Smart Organization never applies anything without explicit review:
  location/category suggestions open a picker on accept; value/tag/
  duplicate suggestions are marked reviewed (no safe automatic fix).
- Dashboard is read-only aggregation; lifetime record is read-only with
  JSON export.

## Verification

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub`: **443/443 passing** (437 existing + 6 new
  widget tests in `test/phase26_ui_test.dart`).
- New tests cover: ask → grounded answer; suggestions list + dismiss +
  all-good state; dashboard totals/members/privacy; lifetime record all
  sections + export button; sync device ID + export/import actions.
- Fixed during testing: drift field-name mismatches in the lifetime
  screen (history `title`/`occurredAt`, service `serviceType`/
  `serviceDate`, claim `claimDate`, purchase `store`/`purchaseDate`/
  `priceCents`/`currencyCode`, document `title`), deprecated
  `share_plus`/`file_picker` APIs aligned with existing app usage.

## Not done here (unchanged, still valid)

- Nothing pushed — user pushes from his PC with normal git.
- Release APK/AAB must be built on the user's PC (real NDK, signing
  keys); iOS needs macOS/Xcode.
- `keepit_database.g.dart` was not regenerated in the sandbox
  (build_runner hook limitation); regenerate on the newer Flutter.
