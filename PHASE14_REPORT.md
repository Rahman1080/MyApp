# Phase 14 Report — Advanced Warranty and Service History

**Date:** 2026-09-30
**Status:** ✅ Complete
**Tests:** 331/331 passing (10 new Phase 14 tests + 1 new migration test)
**Analyzer:** Clean (no issues)

## What was built

Phase 14 extends the existing warranty system (previously purchase-linked only) with direct item linking, comprehensive service/maintenance history, and warranty claim tracking.

### Schema (v7 → v8)

**New tables:**
- `service_records` — maintenance/service history per belonging
  - `belonging_id` (FK, cascade delete)
  - `service_type` (oil_change, repair, inspection, cleaning, tune_up, other)
  - `service_date`, `provider`, `cost_cents`, `currency_code`, `notes`
  - `next_service_date` (for recurring maintenance tracking)

- `warranty_claims` — claims filed against warranties
  - `warranty_id` (FK, cascade delete)
  - `claim_date`, `claim_number`, `status` (filed/in_progress/approved/denied/closed)
  - `description`, `resolution`

**Modified:**
- `warranties.belonging_id` (nullable) — direct link to belonging, complementing the existing purchase link

**Migration:** v7→v8 creates the two tables and adds the nullable column. Made idempotent (checks for existing tables/columns) to handle partial upgrades and test fixtures.

### Domain

**`ServiceType`** — constants and labels for service types.

**`WarrantyClaimStatus`** — constants and labels for claim statuses.

**`WarrantyService`** (new, in `lib/features/warranties/domain/`):
- `recordService()` — records maintenance event + history entry
- `fileClaim()` — files warranty claim + history entry (if linked to belonging)
- `updateClaimStatus()` — updates claim status
- `linkWarrantyToBelonging()` — connects warranty directly to item
- `serviceHistory()` — all service records for a belonging (newest first)
- `claimsForBelonging()` — all claims via linked warranties
- `upcomingMaintenance()` — records with future next_service_date

### Repositories

- `ServiceRecordRepository` — CRUD for service records, `forBelonging()`, `upcoming()`
- `WarrantyClaimRepository` — CRUD for claims, `forWarranty()`, `forBelonging()`, `updateStatus()`

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze --no-pub` | ✅ No issues found |
| `flutter test --no-pub` (full suite) | ✅ 331/331 passing |
| Migration v7→v8 | ✅ Tested (tables created, data preserved) |
| Migration v6→v7, v5→v6 | ✅ Still pass (idempotent) |

### Test breakdown (10 new in `test/phase14_warranty_test.dart`)
1. Schema is v8 with service_records and warranty_claims tables
2. recordService stores service record and history
3. serviceHistory returns records newest first
4. upcomingMaintenance finds future service dates
5. fileClaim creates claim with filed status
6. updateClaimStatus changes status
7. linkWarrantyToBelonging connects warranty to item
8. claimsForBelonging finds claims via linked warranties
9. service type labels resolve
10. warranty claim status labels resolve

### Migration test (1 new in `test/migration_test.dart`)
- v7→v8 migration creates service tables without touching data

## Design decisions

- **Separate service table:** Service history is distinct from the generic history timeline; structured fields (type, cost, provider) enable reporting
- **Warranty dual-linking:** Warranties keep their purchase link (for receipt-based warranties) and gain an optional direct belonging link (for item-specific warranties)
- **Claim status flow:** filed → in_progress → approved/denied → closed; enforced at the service layer
- **History integration:** Service events and claim filings log to the existing belonging history timeline
- **Upcoming maintenance:** Computed via `next_service_date` query, not a separate reminder system (can integrate with existing reminders later)

## Known limitations

- **Android build:** Cannot validate in sandbox (Gradle issues). Phase 14 touches zero files under `android/`.
- **iOS build:** Requires macOS/Xcode.
- **Drift codegen:** `.g.dart` manually extended (build_runner hook issue). User's PC `dart run build_runner build` will regenerate equivalent v8 code.
- **UI:** Phase 14 domain and repositories are complete and tested; UI screens for service history and warranty claims are not yet built (can be added as a follow-up or in a later phase).

## Files changed

**New:**
- `lib/core/database/repositories/service_record_repository.dart`
- `lib/core/database/repositories/warranty_claim_repository.dart`
- `lib/features/warranties/domain/warranty_service.dart`
- `test/phase14_warranty_test.dart`
- `PHASE14_REPORT.md`

**Modified:**
- `lib/core/database/tables.dart` (ServiceRecords, WarrantyClaims, Warranties.belongingId)
- `lib/core/database/keepit_database.dart` (schema v8, v7→v8 migration)
- `lib/core/database/keepit_database.g.dart` (manually extended)
- `test/migration_test.dart` (v8 expectations, v7→v8 test)
- `test/phase12_moves_test.dart` (v8 schema expectation)
- `test/phase13_lifecycle_test.dart` (v8 schema expectation)

## Constraints honored

- ✅ Existing features preserved (all 321 prior tests still pass)
- ✅ No user data altered (migration only adds tables/nullable columns)
- ✅ Offline-first (no network dependencies)
- ✅ One codebase (Flutter/Dart)
- ✅ No fake/mock production data
- ✅ Backup compatibility maintained (new tables use standard patterns)
