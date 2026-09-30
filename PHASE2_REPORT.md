# KEEPIT — Phase 2 Completion Report

**Date:** 2026-09-30
**Status:** Phase 2 complete (data/domain layer, no UI changes)

## What was built

### Repositories (`lib/core/database/repositories/`, 15 files)
Typed CRUD + reactive streams for all 14 entities, with a barrel export
(`repositories.dart`):
- `purchase_repository.dart` — CRUD, `watchAll({status})`, `searchByName`,
  `allExcept` (duplicate-detection pool), cascade delete to products/receipts
- `product_repository.dart`, `receipt_repository.dart`,
  `warranty_repository.dart` (+ `expiringOnOrBefore`),
  `return_deadline_repository.dart` (+ `dueOnOrBefore`),
  `refund_repository.dart` (+ `watchByStatus`)
- `deadline_repository.dart` — `watchUpcoming`, `dueOnOrBefore`, `markDone`
- `reminder_repository.dart` — `watchPending`, `overduePending`,
  `forEntity`, `deleteForEntity`
- `belonging_repository.dart`, `location_repository.dart`,
  `document_repository.dart`, `category_repository.dart`
- `tag_repository.dart` — `getOrCreate`, idempotent `link`/`unlink`,
  `tagsForEntity`, `entityIdsForTag`, cascade on tag delete
- `exceptions.dart` — `RecordNotFoundException`,
  `ReferentialIntegrityException`, `RecordAlreadyExistsException`, and
  `guardConstraints()` which translates SQLite extended result codes
  (787 = FK, 2067 = unique) into typed exceptions

### Business logic (`lib/shared/services/`, 7 files)
- `text_similarity.dart` — normalization, Levenshtein, token-set similarity
- `warranty_service.dart` — `WarrantyDuration` (days/months/years),
  month-end-clamped date math, `warrantyExpiryDate`,
  `warrantyDaysRemaining`, `warrantyStatus` (active/expiringSoon ≤30d/expired)
- `return_deadline_service.dart` — `returnDaysLeft`, `isReturnOverdue`,
  `returnWindowStatus` (available/approaching ≤7d/expired),
  `returnDeadlineFromWindow`
- `duplicate_detector.dart` — `findDuplicateCandidates`: token-set name
  similarity ≥ 0.8 AND normalized store match AND price within 1% or $1
  AND date within 7 days; ranked by score. Detection only — never
  merges or deletes.
- `global_search.dart` — `searchAll` across purchases, receipts,
  belongings, locations, deadlines, documents; case-insensitive,
  ranked exact > prefix > substring, per-entity limit
- `location_service.dart` — `locationPath` breadcrumb, `descendants`,
  `belongingsInLocationTree`, `wouldCreateCycle` (cycle-guarded)
- `reminder_scheduler.dart` — `computeFireTimes` (offsets + optional
  HH:mm, skips past times, sorted/deduped), `nextOccurrence` for
  daily/weekly/monthly/yearly repeats

## Verification

- `flutter analyze`: **No issues found**
- `flutter test`: **107/107 passed** (4 pre-existing Phase 1 smoke tests +
  103 new), covering:
  - warranty/return calculations incl. leap-year and month-end edge cases
  - duplicate detection: exact dup, near-dup, non-dup, different
    store/price, far-apart dates, ranking, and a no-auto-merge guarantee
  - global search: multi-entity, case-insensitivity, notes fields,
    ranking, per-entity limits, empty query
  - location hierarchy: 3-level breadcrumb, descendants, tree-wide
    belongings, cycle detection
  - reminder math: offsets, due-time override, past-time skipping,
    repeat occurrences
  - repository CRUD/streams for every entity, not-found errors,
    FK violations → `ReferentialIntegrityException`,
    unique violations → `RecordAlreadyExistsException`,
    cascade delete (purchase → products/receipts),
    SET NULL on location-parent delete
  - migration: schemaVersion == 1, all 15 tables + key indices created,
    ALTER TABLE upgrade scaffold preserves data, FK pragma enforced

## Design notes / compromises

1. **Repository `create` returns `Future<void>`**, not the id: drift's
   `insert()` returns the SQLite rowid (`int`), and ids are client-generated
   UUIDs, so callers keep the id they generated. `TagRepository.getOrCreate`
   generates its own id via `newRecordId()`.
2. **Global search** uses SQL `LIKE` pre-filtering (case-insensitive for
   ASCII) plus in-Dart ranking — appropriate for personal-scale data, no
   FTS index needed yet.
3. **Duplicate detection** loads all purchases into memory per check —
   fine for MVP scale; index-backed blocking can come later if needed.
4. **No APK build in this phase** (nothing user-visible changed, per plan);
   gates were `flutter analyze` + `flutter test`.

## Files created

**Repositories:** `lib/core/database/repositories/` — `exceptions.dart`,
`purchase_repository.dart`, `product_repository.dart`,
`receipt_repository.dart`, `warranty_repository.dart`,
`return_deadline_repository.dart`, `refund_repository.dart`,
`deadline_repository.dart`, `reminder_repository.dart`,
`belonging_repository.dart`, `location_repository.dart`,
`document_repository.dart`, `category_repository.dart`,
`tag_repository.dart`, `repositories.dart`

**Services:** `lib/shared/services/` — `text_similarity.dart`,
`warranty_service.dart`, `return_deadline_service.dart`,
`duplicate_detector.dart`, `global_search.dart`, `location_service.dart`,
`reminder_scheduler.dart`

**Tests:** `test/` — `text_similarity_test.dart`,
`warranty_service_test.dart`, `return_deadline_service_test.dart`,
`reminder_scheduler_test.dart`, `duplicate_detector_test.dart`,
`global_search_test.dart`, `location_service_test.dart`,
`repositories_purchase_test.dart`, `repositories_org_test.dart`,
`migration_test.dart`

No changes to UI code, database schema (still v1), or `pubspec.yaml`
(no new dependencies).

## Next steps (Phase 3+)

- Phase 3: Home screen + Purchases CRUD UI on top of these repositories
- Phase 5 will wire `ReminderScheduler` into flutter_local_notifications
- Phase 7 backup/export can reuse the repository layer for serialization

## Post-phase fix (2026-09-30)
- `addWarrantyDuration` used `.add(Duration(days: n))`, which shifts wall-clock time across DST transitions in local timezones (test failed: expected 2026-04-01 00:00, got 01:00). Replaced with calendar-day arithmetic via the `DateTime` constructor (`day + duration.days`), which normalizes in calendar terms. Full suite re-verified: **107/107 tests pass**, `flutter analyze` clean.
