# Phase 15 Report — Household/Family Sharing

**Date:** 2026-09-30
**Status:** ✅ Complete
**Tests:** 343/343 passing (11 new Phase 15 tests + 1 new migration test)
**Analyzer:** Clean (no issues)

## What was built

Phase 15 introduces local-only household/family sharing with privacy Private by default. No cloud sync — sharing is managed locally on the device.

### Schema (v8 → v9)

**New table:**
- `household_members` — local family/household members
  - `id`, `name`, `relationship` (spouse/child/parent/roommate/other)
  - `color_hex` (avatar color), `notes`, timestamps

**Modified:**
- `belongings.privacy_level` (TEXT, default 'private') — 'private' | 'shared'
- `belongings.owner_member_id` (nullable, FK to household_members, ON DELETE SET NULL)

**Migration:** v8→v9 creates the household_members table and adds the two columns. Idempotent (checks for existing tables/columns). Existing belongings default to 'private' — no data is exposed by default.

### Domain

**`PrivacyLevel`** (in household_member_repository.dart):
- Constants: `private` (default), `shared`
- `label()` for UI display, `isValid()` for validation

**`HouseholdMemberRepository`**:
- `create()` — adds member with name/relationship/color/notes
- `getById()`, `getAll()` (ordered by name)
- `update()`, `delete()` (FK clears owner references)
- `belongingsForMember()` — items owned by a member

**`HouseholdService`** (in `lib/features/household/domain/`):
- `addMember()` / `members()` / `removeMember()`
- `setPrivacy()` — validates level, logs history event
- `assignOwner()` — validates member exists, logs history event
- `belongingsForMember()` — items for a specific member
- `sharedBelongings()` / `privateBelongings()` — privacy-filtered queries

### Privacy model

- **Default Private:** All belongings are 'private' unless explicitly set to 'shared'
- **Local-only:** No network calls, no cloud sync (Phase 17 will add optional cloud)
- **Owner assignment:** Belongings can be assigned to a household member (who owns/uses it)
- **History integration:** Privacy changes and owner assignments log to belonging history
- **Safe deletion:** Removing a member clears owner references (SET NULL), doesn't delete belongings

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze --no-pub` | ✅ No issues found |
| `flutter test --no-pub` (full suite) | ✅ 343/343 passing |
| Migration v8→v9 | ✅ Tested (table created, data preserved) |
| Migration v7→v8, v6→v7 | ✅ Still pass (idempotent) |

### Test breakdown (11 new in `test/phase15_household_test.dart`)
1. Schema is v9 with household_members table
2. addMember creates household member
3. belongings default to private privacy
4. setPrivacy changes privacy level
5. setPrivacy rejects invalid level
6. assignOwner links belonging to member
7. assignOwner rejects unknown member
8. assignOwner with null clears owner
9. sharedBelongings returns only shared items
10. removeMember clears owner references (FK SET NULL)
11. privacy level labels resolve

### Migration test (1 new in `test/migration_test.dart`)
- v8→v9 migration creates household tables without touching data

## Design decisions

- **Local-first:** Phase 15 is intentionally local-only. Cloud sync (Phase 17) will build on this foundation
- **Privacy by default:** The 'private' default ensures no accidental data exposure. Users must explicitly share
- **Separate member table:** Household members are distinct from app users — this supports family devices and shared tablets
- **Nullable owner:** Items can be unassigned (household-shared) or assigned to a specific member
- **History logging:** Privacy and ownership changes are audited in the belonging timeline

## Known limitations

- **Android build:** Cannot validate in sandbox (Gradle issues). Phase 15 touches zero files under `android/`.
- **iOS build:** Requires macOS/Xcode.
- **Drift codegen:** `.g.dart` manually extended (build_runner hook issue). User's PC `dart run build_runner build` will regenerate equivalent v9 code.
- **UI:** Phase 15 domain and repositories are complete and tested; UI screens for member management and privacy controls are not yet built (can be added as a follow-up or in a later phase).
- **Sharing mechanism:** Actual data sharing between devices (export/import, QR codes) is deferred to Phase 17 (cloud sync) or a future local-sharing enhancement.

## Files changed

**New:**
- `lib/core/database/repositories/household_member_repository.dart`
- `lib/features/household/domain/household_service.dart`
- `test/phase15_household_test.dart`
- `PHASE15_REPORT.md`

**Modified:**
- `lib/core/database/tables.dart` (HouseholdMembers, Belongings.privacyLevel, Belongings.ownerMemberId)
- `lib/core/database/keepit_database.dart` (schema v9, v8→v9 migration)
- `lib/core/database/keepit_database.g.dart` (manually extended)
- `test/migration_test.dart` (v9 expectations, v8→v9 test)
- `test/phase12_moves_test.dart` (v9 schema expectation)
- `test/phase13_lifecycle_test.dart` (v9 schema expectation)
- `test/phase14_warranty_test.dart` (v9 schema expectation)

## Constraints honored

- ✅ Existing features preserved (all 332 prior tests still pass)
- ✅ No user data altered (migration only adds tables/nullable columns, defaults to private)
- ✅ Offline-first (no network dependencies)
- ✅ One codebase (Flutter/Dart)
- ✅ No fake/mock production data
- ✅ Backup compatibility maintained (new tables use standard patterns)
- ✅ Privacy by default (local-only, no cloud, private default)
