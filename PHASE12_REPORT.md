# Phase 12 Report — Moving Mode

**Date:** 2026-09-30
**Status:** ✅ Complete
**Tests:** 309/309 passing (14 new Phase 12 tests + 1 new migration test)
**Analyzer:** Clean (no issues)

## What was built

Phase 12 adds "Moving Mode" — a full move-tracking system for packing, transporting, and unpacking belongings when relocating.

### Schema (v5 → v6)

**New tables:**
- `moves` — a relocation event: name, status, source/destination places, move date, notes, completion timestamp
- `move_items` — belongings in a move: move FK, belonging FK, status, box label, notes, ordering

**New indexes:**
- `idx_moves_status`
- `idx_move_items_move`
- `idx_move_items_belonging`

**Migration:** v5→v6 creates both tables; no existing data touched. Tested with a dedicated migration test.

### Domain

**Move status flow:**
```
planning → packing → in_transit → unpacking → completed
```
Non-terminal moves can be cancelled.

**Move-item status flow:**
```
to_pack → packed → in_transit → delivered → unpacked
```
Forward-only transitions; illegal transitions rejected.

**MoveService** provides:
- Create/update/delete moves
- Add items (idempotent — adding the same belonging twice returns existing row)
- Bulk item status updates (skips illegal transitions)
- Box-level packing (`packBox`)
- Progress aggregation (counts, packed/unpacked percentages)
- Import owned contents from a source place or location subtree
- Import container and contents
- `completeMove` — walks move through remaining statuses; optionally re-homes delivered/unpacked belongings to a destination location

### UI

- **`/moves`** — Move list with status chips, progress bars, new-move dialog
- **`/moves/:id`** — Move detail: progress card, add items (selected inventory / all from source place), per-item and bulk status actions, box packing, complete/cancel
- **Settings entry:** "Moving Mode"

### Backup/Restore

- Added optional `moves.json` and `move_items.json` codecs to `BackupService`
- Ordered parent-first (moves before move_items)
- Legacy backups without these files restore cleanly
- New backup round-trips moves/items (tested)

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze --no-pub` | ✅ No issues found |
| `flutter test --no-pub` (full suite) | ✅ 309/309 passing |
| Migration v5→v6 | ✅ Tested (tables created, data preserved) |
| Backup round-trip | ✅ Tested |
| Legacy backup restore | ✅ Existing tests pass |

### Test breakdown (14 new in `test/phase12_moves_test.dart`)
1. Schema is v6 and moves tables exist
2. Create move with defaults
3. Move status advances through the flow
4. Cancel move from planning
5. Add items to move is idempotent
6. Move item status flow is forward-only
7. Bulk status update skips illegal transitions
8. packBox marks every item in a box as packed
9. addPlaceContents adds owned items from a place
10. addLocationContents includes subtree
11. completeMove re-homes delivered items
12. Progress snapshot aggregates statuses
13. Deleting a move cascades to move items
14. Backup round-trips moves and move items

### Migration test (1 new in `test/migration_test.dart`)
- v5→v6 migration creates moves tables without touching data

## Design decisions

- **Forward-only item statuses:** Prevents accidental regression (e.g., marking unpacked item as "to pack")
- **Idempotent item addition:** Safe to re-run imports without duplicates
- **Optional re-homing:** On completion, user chooses whether to update belonging locations to a destination; earlier-status items keep their locations
- **Container clearing:** Re-homed items have `containerId` cleared since the box may not exist at the destination

## Known limitations

- **Android build:** Cannot validate in sandbox (Gradle TLS/download issues). Phase 12 touches zero files under `android/`.
- **iOS build:** Requires macOS/Xcode.
- **Drift codegen:** `lib/core/database/keepit_database.g.dart` was manually extended (build_runner has a hook issue in this sandbox). User's PC `dart run build_runner build` will regenerate equivalent v6 code.
- **Share sheet:** Needs device validation (same as Phase 11).

## Files changed

**New:**
- `lib/core/database/repositories/move_repository.dart`
- `lib/core/database/repositories/move_item_repository.dart`
- `lib/features/moves/domain/move_service.dart`
- `lib/features/moves/presentation/moves_screen.dart`
- `lib/features/moves/presentation/move_detail_screen.dart`
- `test/phase12_moves_test.dart`
- `PHASE12_REPORT.md`

**Modified:**
- `lib/core/database/tables.dart` (Moves, MoveItems tables + indexes)
- `lib/core/database/keepit_database.dart` (schema v6, v5→v6 migration)
- `lib/core/database/keepit_database.g.dart` (regenerated/manually extended)
- `lib/core/database/repositories/repositories.dart` (exports)
- `lib/core/navigation/app_router.dart` (`/moves`, `/moves/:id` routes)
- `lib/features/settings/presentation/settings_screen.dart` (Moving Mode entry)
- `lib/shared/services/backup_service.dart` (moves/move_items codecs)
- `test/migration_test.dart` (v6 expectations, v5→v6 test)

## Constraints honored

- ✅ Existing features preserved (all 294 prior tests still pass)
- ✅ No user data altered (migration only adds tables)
- ✅ Offline-first (no network dependencies)
- ✅ One codebase (Flutter/Dart, no platform-specific code)
- ✅ No fake/mock production data
- ✅ Backup compatibility maintained
