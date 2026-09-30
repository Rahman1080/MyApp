# KEEPIT — Phase 6 Report: Belongings, Locations & "Where Is It?" Search

**Date:** 2026-09-30
**Scope:** Phase 6 only (My Stuff tab, hierarchical locations, global search UI, Home quick-action wiring).
**Toolchain:** Flutter 3.38.7 · Dart 3.10.7 · JDK 17 · compileSdk 36 · AGP 8.11.1 · minSdk 24

## What was built

### 1. My Stuff tab (real, replaces the Phase 1 placeholder)
- `lib/features/belongings/presentation/belongings_screen.dart` — live list of belongings with a search-as-you-type field, category filter chips (All + user categories), photo thumbnails, category/brand/quantity subtitles and a location breadcrumb per row. Rows without a location show a "no location set" hint icon. FAB → `/stuff/new`; AppBar actions → global search and the locations browser. Friendly empty states for first run vs. no matches.
- `belonging_form_screen.dart` — add/edit: name (validated), brand, category dropdown, **hierarchical location picker** (indented tree labels), quantity stepper, notes, and a photo picker (camera/gallery via the Phase 4 `PermissionService`; stored with the new `FileStorage.saveBelongingPhoto` into app-private `belongings/`). Photos are persisted only on save; replacing a photo deletes the old stored file.
- `belonging_detail_screen.dart` — large photo, fact rows (brand, category, quantity, notes), tappable location breadcrumb (deep-links to the locations browser at that level), **Move** bottom-sheet action, edit/delete. Delete removes the row plus its stored photo and documents' files (document rows cascade at the DB level; files are cleaned explicitly).
- Routes: `/stuff`, `/stuff/new`, `/stuff/:id`, `/stuff/:id/edit`.

### 2. Hierarchical locations
- `lib/features/locations/presentation/locations_screen.dart` — tree browser at `/stuff/locations`: drill down into sub-locations, breadcrumb chips to climb back up, each level showing sub-locations (with child counts) and the belongings stored directly in it. Root level shows top-level locations plus "Not put away" belongings. Location rows have a Rename / move / Delete menu. Delete confirmation states that sub-locations move to the top level (schema `ON DELETE SET NULL`); after deleting the level being viewed, the browser steps up to the parent. Accepts `?focus=<id>` to open at a specific level (used by search results).
- `location_form_screen.dart` — add/edit: name (validated), parent picker ("Inside (optional)" with full breadcrumb labels, "Top level" default), notes. **Cycle prevention:** the picker lists every location except the edited one and its descendants, computed with the existing `LocationService.wouldCreateCycle`. "Add sub-location" pre-selects the current level as parent.
- Routes: `/stuff/locations`, `/stuff/locations/new?parentId=…`, `/stuff/locations/:locationId/edit`.

### 3. "Where is it?" search
- `lib/features/search/presentation/search_screen.dart` — at `/search`: autofocused field with 300 ms debounce, results grouped by type (Purchases / Receipts / Belongings / Locations / Deadlines / Documents) with counts. Belonging rows show their location breadcrumb inline; location rows show their full breadcrumb; every row navigates to its detail (receipts → owning purchase, documents → owning purchase or belonging, locations → browser focused at that level). Empty state hints: "Try 'passport', 'warranty', 'kitchen'…". Built on the Phase 2 `GlobalSearchService` ranking — no new search logic needed.
- Shared helpers: `lib/features/belongings/presentation/widgets/location_path.dart` — `buildLocationPaths` (id → "Home > Bedroom > Drawer", cycle-safe), `flattenLocationTree` (depth-annotated, cycle-safe), and the `LocationPathText` widget. Covered by 6 unit tests including cycle termination.

### 4. Supporting changes
- `FileStorage.saveBelongingPhoto` — app-private `belongings/<uuid>.<ext>` copy, same allow-list/sanitizing discipline as receipts.
- `DocumentService.pickAndAttachBelonging` / `documentsForBelonging`; `DocumentRepository.getByBelonging` (one-shot, widget-test safe); `DocumentsSection` now accepts `belongingId` (exactly one of `purchaseId`/`belongingId`) — purchase flows unchanged.
- `LocationRepository.getAll` (one-shot, matching `CategoryRepository.getAll`).
- Home quick actions: "Add belonging" now opens `/stuff/new`; the stale "Add deadline" coming-soon link (leftover copy from Phase 5) now opens `/deadlines/new`.

## Verification

- `flutter analyze` — **no issues**.
- `flutter test` — **180/180 passed** (170 pre-existing preserved + 10 new):
  - `location_path_test.dart` (6): breadcrumbs, unknown-parent chains, cycle termination, tree flattening with depths.
  - `phase6_forms_test.dart` (4): belonging name validation, successful save, parent picker excludes self + descendants, new locations nest anywhere.
- Android debug build: **BUILD SUCCESSFUL** (`flutter build apk --debug`). APK remains oversized (~1.6 GB) due to the sandbox stub NDK (known limitation, unchanged since Phase 1).
- iOS static review: no new plugins (image_picker/file_picker already vetted in Phase 4); all new code is pure Dart/Flutter with no Android-only paths; `go_router` query-parameter routes behave identically on iOS. Real Xcode compilation still requires macOS.

## Decisions & notes for later phases

- No schema changes (still v1); no migrations needed.
- Belonging schema has no value/currency column, so the form omits it (brand/quantity/notes cover the practical need).
- One receipt per purchase — unchanged known limitation from Phase 4.
- Moving a belonging or deleting a location never deletes belongings; deleting a location only nulls children's parent (top level) and clears belongings' location to "not put away", with explicit user messaging.
- Notification payload routing untouched (Phase 6 adds no notifications).
