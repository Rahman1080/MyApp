# KEEPIT Phase 10 — Home and Household Inventory — Report

**Date:** 2026-09-30
**Status:** Complete in sandbox: `flutter analyze` clean, 275/275 tests pass. Android APK validation could not run in the sandbox (Gradle environment issue, no `android/` changes in Phase 10 — see Verification). Not pushed — push from your PC with normal git (never force-push the sandbox's synthetic history).

## What was built

Phase 10 organizes possessions by real physical spaces, on top of the existing Drift/SQLite database — no rebuild, no architecture change, no features removed.

**Hierarchy:** Place → Room/Area → Shelf → Box. Locations gained a non-null `place_id` (FK, default `'place-default'`); a new `places` table holds named places. Existing users get a default **"My Home"** place automatically — no forced setup.

**Containers:** Belongings gained `is_container` (default false) and a self-FK `container_id`. A belonging flagged as a container is a box/bin/folder that holds other belongings. Items inside a container derive their physical location from it (their own `location_id` is cleared on move-in, restored to the container's location on move-out).

**Templates:** Room quick-picks — Living Room, Bedroom, Kitchen, Bathroom, Garage, Basement, Attic, Closet, Office, Storage — plus free custom names. Place name suggestions (My Home, Parents' Home, Apartment, Garage, Storage Unit, Office, Car).

**"What is here?"** — per-location summaries: sub-location count, container count, direct-item count (items inside boxes excluded from the direct count).

**"Where is it?"** — full paths like `My Home > Bedroom > Drawer > Blue Folder`, computed through container ancestors and the location tree, prefixed with the place name. Containers are searchable through the normal global search (name/notes/tags), and their paths show in results.

**Moves:**
- Single item → location or container; multi-select bulk move → location or container.
- Move a whole location subtree to another place (place cascades to descendants; children created under a parent inherit its place automatically).
- Empty a container (contents move out to a chosen location, box stays).
- Cycle prevention everywhere: a location can't go under itself/descendant; a container can't go inside itself/descendant (throws `ReferentialIntegrityException`).
- Every move writes an automatic history entry ("Moved…", "Taken out of…").

**Dashboard (Locations tab):** total items, total containers, items without locations, items with unknown value.

**UI:** place chips + place management on the Locations screen, location drill-down with breadcrumbs, room-template chips in the location form, container toggle in the item form, container detail with contents list, move-destination bottom sheet (locations tree / containers / "no location", with cycle-unsafe containers hidden), bulk move from the Belongings screen via long-press.

**Backup/restore:** new `places` codec (restored before locations so the FK holds); `place_id`/`is_container` backfilled on legacy backups — a pre-Phase-10 backup restores cleanly with everything assigned to the default place.

## Schema: v5

- v4 → v5 migration: creates `places`, inserts the default `place-default` / "My Home" row, adds `locations.place_id` (backfilled to the default for all existing rows), adds `belongings.is_container` / `belongings.container_id`, creates `idx_locations_place_id` and `idx_belongings_container_id`.
- Fresh installs: `onCreate` now seeds the default place. (This was a real bug found during test repair — without it, the `place_id` FK made *every* location insert fail on fresh installs, since the default row only existed via the upgrade path.)

## Verification (all re-run in sandbox, 2026-09-30)

- `flutter analyze` — **clean, no issues**.
- `flutter test` — **275/275 pass** (was 248 in Phase 9). Includes:
  - 8 migration tests: schema version 5, onCreate seeds default place, v1→v2, v2→v3, v3→v4, full v1→v5 chain, and a dedicated v4→v5 backfill test (existing locations keep working, items are not containers).
  - 26 new `test/phase10_household_test.dart`: place CRUD + deletion guards, subtree place moves, hierarchy cycle rejection, container nesting/ancestors/descendants, container cycle rejection, move-in clears location, move-out restores it, empty-container, bulk moves, history entries, full "where is it?" paths incl. non-default place, "what is here?" counts, dashboard counts, backup round-trip with places+containers, legacy backup (no places file) restoring onto the default place, and a widget test for the move-destination sheet (excluded containers hidden).
- Android build validation — **could not be completed in the sandbox** (environmental, not code-related). `flutter build apk --debug` never got past the Gradle bootstrap: the wrapper cannot download its Gradle 8.14 distribution here (TLS handshake to services.gradle.org dies with a broken pipe — direct egress is blocked and the wrapper bootstrap ignores the proxy config), and a locally-installed Gradle 8.14 gets past the wrapper but its daemon cannot reliably communicate over the sandbox's localhost sockets ("Could not receive a message from the daemon" / serialization type-tag errors, intermittent — a debug APK built fine in this same sandbox at 08:39 today). Dependency downloads were also blocked until proxy auth was supplied, and even then the daemon IPC failures persisted. Notably, Phase 10 changes **zero files under `android/`** (verified via `git diff` — all changes are Dart + tests), so there is nothing new for the native build to compile; `flutter analyze` (clean) and the 275 passing tests already compile every changed line. The real validation remains the build on your PC, which is the sanctioned path for all production artifacts anyway. Sandbox APKs are test-only per the standing rule.
- `pubspec.yaml` / `pubspec.lock` byte-identical to remote (restored after sandbox `pub get` downgraded Flutter-pinned transitives).

## Bugs found and fixed during test repair

1. Fresh databases never seeded the default place → FK failure on any location insert. Fixed in `onCreate`.
2. `BelongingRepository.create` read `.value` on an absent `isContainer` → fixed to check `.present` first.
3. Migration tests hand-built partial DBs without a `locations` table (real DBs always have one); fixtures updated to include a v1-shaped locations table.
4. Gradle wrapper could not download its distribution in this sandbox (TLS/broken-pipe on the wrapper bootstrap's direct connection); worked around with a locally installed Gradle 8.14, which then hit sandbox localhost socket issues with its daemon IPC — documented under Verification above rather than claimed as fixed.

## Constraints honored

- No full rebuild, no database architecture change (Drift/SQLite kept), no features removed — all Phase 1–9 behavior and tests intact.
- Existing data preserved via the tested v4→v5 migration; backup/restore stays compatible both ways.
- "Do not finish if tests fail" — the 45 initial failures were diagnosed to a common root cause (missing default-place seed) and fixed; suite is green before this report.

## For you

- Pull and push from your PC as usual; the generated `keepit_database.g.dart` and launcher icons still need regenerating/adding there (`dart run build_runner build` after cloning).
- Anything not covered: production release build + Play signing remain on your PC; no widget test yet for the container-detail screen's add/remove flows (covered at repository level).
