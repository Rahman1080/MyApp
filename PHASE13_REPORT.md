# Phase 13 Report — Item Lifecycle

**Date:** 2026-09-30
**Status:** ✅ Complete
**Tests:** 320/320 passing (10 new Phase 13 tests + 1 new migration test)
**Analyzer:** Clean (no issues)

## What was built

Phase 13 adds rich item lifecycle tracking on top of Phase 9's archive states: how items enter the user's life, how they leave, and computed lifecycle summaries.

### Schema (v6 → v7)

**New columns on `belongings`** (all nullable, existing rows untouched):
- `acquisition_type` — how acquired (purchased/gifted/inherited/handmade/found/other)
- `acquisition_date` — when acquired
- `disposition_date` — when sold/donated/disposed
- `disposition_price_cents` + `disposition_currency_code` — sale proceeds
- `disposition_recipient` — buyer, charity, recipient name
- `disposition_method` — sold/donated/given_away/recycled/trashed/lost/other
- `disposition_notes` — freeform notes

**Migration:** v6→v7 adds the 8 columns. Made idempotent (skips columns that already exist) to handle partial upgrades.

### Domain

**`BelongingAcquisitionType`** — constants and labels for acquisition types.

**`BelongingDispositionMethod`** — constants and labels for disposition methods.

**`LifecycleService`** provides:
- `recordAcquisition()` — records how/when item entered user's life + history entry
- `markSold()` — marks sold with price, recipient, notes + history entry
- `markDonated()` — marks donated with recipient + history entry
- `markDisposed()` — marks disposed with method + history entry
- `summarize()` — computes `LifecycleSummary`

**`LifecycleSummary`**:
- Ownership duration as human-readable label ("2 years, 3 months")
- Value retention percentage (sale price vs original value)
- Retirement status, disposition details

### UI

**`BelongingLifecycleSection`** widget on the item detail screen:
- Acquired: type + date
- Owned for: duration
- If retired: disposition method/date, recipient, sale price, value retained
- Edit button opens acquisition dialog (type dropdown + date picker)

**Integration:**
- Added `lifecycleService` to `BelongingDetailScreen` constructor
- Wired in `app_router.dart`
- Section appears above the History section

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze --no-pub` | ✅ No issues found |
| `flutter test --no-pub` (full suite) | ✅ 320/320 passing |
| Migration v6→v7 | ✅ Tested (columns added, data preserved) |
| Migration v5→v6 | ✅ Still passes (idempotent v7 handles chain) |

### Test breakdown (10 new in `test/phase13_lifecycle_test.dart`)
1. Schema is v7 with lifecycle columns
2. recordAcquisition stores type and date
3. markSold records sale details and history
4. markDonated records recipient
5. markDisposed records method
6. summarize computes ownership duration
7. summarize computes value retention for sold items
8. value retention is null when values missing
9. acquisition type labels resolve
10. disposition method labels resolve

### Migration test (1 new in `test/migration_test.dart`)
- v6→v7 migration adds lifecycle columns without touching data

## Design decisions

- **Nullable columns:** Existing items get null lifecycle data; no forced backfill
- **Idempotent migration:** Checks `pragma_table_info` before adding columns
- **History integration:** All lifecycle events log to the existing history timeline
- **Value retention:** Computed on-demand, not stored (avoids stale data)
- **Separate from archive state:** Disposition details complement, don't replace, the archive state flow

## Known limitations

- **Android build:** Cannot validate in sandbox (Gradle issues). Phase 13 touches zero files under `android/`.
- **iOS build:** Requires macOS/Xcode.
- **Drift codegen:** `.g.dart` manually extended (build_runner hook issue). User's PC `dart run build_runner build` will regenerate equivalent v7 code.

## Files changed

**New:**
- `lib/features/belongings/domain/lifecycle_service.dart`
- `lib/features/belongings/presentation/widgets/belonging_lifecycle_section.dart`
- `test/phase13_lifecycle_test.dart`
- `PHASE13_REPORT.md`

**Modified:**
- `lib/core/database/tables.dart` (8 new columns)
- `lib/core/database/keepit_database.dart` (schema v7, v6→v7 migration)
- `lib/core/database/keepit_database.g.dart` (manually extended)
- `lib/core/database/belonging_meta.dart` (acquisition/disposition constants)
- `lib/core/navigation/app_router.dart` (lifecycleService wiring)
- `lib/features/belongings/presentation/belonging_detail_screen.dart` (lifecycle section)
- `test/migration_test.dart` (v7 expectations, v6→v7 test)
- `test/phase12_moves_test.dart` (v7 schema expectation)

## Constraints honored

- ✅ Existing features preserved (all 310 prior tests still pass)
- ✅ No user data altered (migration only adds nullable columns)
- ✅ Offline-first (no network dependencies)
- ✅ One codebase (Flutter/Dart)
- ✅ No fake/mock production data
- ✅ Backup compatibility maintained (full-row serialization includes new columns)
