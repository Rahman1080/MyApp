# KEEPIT Phase 11 Report — Insurance Inventory and Reports

**Date:** 2026-09-30
**Status:** Complete and verified in sandbox
**Schema version:** 5 (no schema changes in this phase)

## Objective

Turn the inventory into a documentation system for possessions:
professional PDF inventory reports (full / home / room / category /
selected-items scopes), a missing-information report with completion
suggestions, and user-initiated ZIP evidence export (PDF + photos +
receipts + documents). Hard lines honored: no legal claims, no claim
KEEPIT determines coverage, never invent missing fields, everything
user-controlled, no automatic uploads.

## What was built

### Domain layer (`lib/features/reports/domain/`)

- **`inventory_report.dart`** — `InventoryReport`, `ReportItem`, `ReportScope`
  (full / place / location-subtree / category / selected), `MissingInfoEntry`
  with the six missing-information checks (receipt, photos, location,
  purchase date, value, serial number) each carrying a human-readable
  suggestion. `valueByCurrency` groups known values by currency code —
  currencies are never converted or mixed.
- **`report_service.dart`** — assembles reports from the existing
  repositories (belongings, places, locations, categories, purchases,
  receipts, warranties, documents, photos). Resolves effective locations
  for items nested in containers, builds full "where is it?" paths,
  defaults to owned items with an opt-in for inactive states.
- **`pdf_report_builder.dart`** — multipage PDF via the pure-Dart `pdf`
  package. Contains only available information: item details
  (name/category/photo/brand/model/serial/purchase date/prices/location/
  receipt/warranty/documents/notes), a missing-information appendix, and
  a disclaimer stating KEEPIT makes no legal or coverage determination.
  Embeds the first valid photo per item; skips missing/corrupt/oversized
  images without failing. Mixed currencies are listed separately, never
  summed across currencies. Builder-emitted em/en dashes are mapped to
  ASCII because the built-in Helvetica font only covers WinAnsi.
- **`evidence_export_service.dart`** — user-initiated ZIP containing
  `inventory-report.pdf` plus all report photo paths, receipt images, and
  document files. Missing files are skipped; duplicate file names are
  disambiguated. No automatic uploads anywhere.

### Presentation (`lib/features/reports/presentation/reports_screen.dart`)

Scope picker (report type radio group + place/location/category/selected
pickers), "include past items" toggle, report summary card (item count,
per-currency totals, documentation status), missing-information section
with expandable per-item suggestions, and three export actions:
**Save PDF**, **Share PDF** (via `share_plus`), **Export evidence ZIP**.
Reached from Settings and via the app router. Uses `SingleChildScrollView`
+ `Column` (see "Notable debugging" below).

### Supporting changes

- `BelongingRepository.getAll()` — one-shot query (the widget test's
  original `watchAll().first` chain could stall under FakeAsync).
- `pubspec.yaml`: added `pdf: ^3.12.0`, `share_plus: ^13.3.0`.
- `pubspec.lock`: regenerated; sandbox resolves Flutter-3.38.7-compatible
  transitives (meta 1.17.0, archive 4.0.9, …). The user's PC on newer
  Flutter will resolve newer pinned versions on its own `flutter pub get`
  — known asymmetry, no action needed.
- Generated plugin registrants updated for `share_plus`
  (android/ios/linux/macos/windows).

## Tests

New file `test/phase11_reports_test.dart` — **19 tests**, all passing:

- Report scopes: full, place, location subtree (incl. containers), category,
  selected items, inactive-item opt-in.
- Item assembly: effective location through container nesting, category,
  purchase/receipt/warranty/document/photo wiring.
- Missing information: all six checks, suggestions present, complete items
  excluded.
- PDF: empty report, small report with photos/long names/missing files,
  250-item large inventory, **20-photo gallery** (PDF embeds first photo
  only, stays valid), Unicode names (emoji/CJK/accents) do not crash.
- Evidence ZIP: contains PDF + photos + receipts + documents; duplicate
  names disambiguated; missing files skipped.
- Widget test: generating a full report shows summary, all three export
  actions, and the missing-information section.

**Full suite: 294/294 passing** (`flutter test --no-pub`).
**Analyzer: clean** (`flutter analyze --no-pub`).
**Format: clean** (`dart format` on all touched files).

## Android / iOS compatibility review

- `pdf` is pure Dart — no platform code, works on Android and iOS.
- `share_plus` officially supports Android and iOS; no extra manifest /
  Info.plist configuration required for basic file sharing.
- **Android build in sandbox:** still blocked by the known sandbox
  infrastructure issue (Gradle wrapper distribution download fails with
  TLS broken pipe; daemon localhost IPC unreliable). Phase 11 adds no
  native code, so nothing new for the native build to compile. Production
  APK/AAB must be built on the user's PC as established.
- **iOS build:** requires macOS/Xcode — not available in this sandbox.
  No iOS-specific code paths were added; `share_plus` handles the iOS
  share sheet via its own plugin.
- **Share-sheet smoke testing** needs a real device and remains unverified;
  the widget test covers UI presence, not the OS share sheet.

## Backup / restore review

No schema or migration changes in Phase 11 (schema stays v5). Reports are
read-only views over existing tables. The existing backup/restore tests
(migration_test.dart, backup coverage) all pass in the full 294-test run —
no regressions.

## Limitations and honest caveats

1. **PDF Unicode:** the built-in Helvetica covers WinAnsi only. Emoji, CJK,
   and other non-Latin scripts in user-entered names/notes render blank
   (the PDF still generates without crashing — verified by test). A bundled
   Unicode TTF font (~1 MB APK cost) can be added in a later phase if needed.
2. **ListView quirk:** during testing, export buttons placed after the
   summary `Card` inside a `ListView` were built but never attached to the
   render tree (a `SliverChildListDelegate` reconciliation quirk reproducible
   only with this screen's exact child sequence; minimal repros work fine).
   Fixed by using `SingleChildScrollView` + `Column`, which is also more
   appropriate for this form-style screen.
3. **Share sheet** behavior is only UI-tested; OS-level share needs device
   validation.
4. **Printing** is out of scope — belongs to Phase 23.
5. "Receipt available" requires a receipt row with a non-empty image path
   (evidence-oriented by design).

## Files

New:
- `lib/features/reports/domain/inventory_report.dart`
- `lib/features/reports/domain/report_service.dart`
- `lib/features/reports/domain/pdf_report_builder.dart`
- `lib/features/reports/domain/evidence_export_service.dart`
- `lib/features/reports/presentation/reports_screen.dart`
- `test/phase11_reports_test.dart`

Modified:
- `lib/core/navigation/app_router.dart` (reports route)
- `lib/features/settings/presentation/settings_screen.dart` (entry point)
- `lib/core/database/repositories/belonging_repository.dart` (`getAll()`)
- `pubspec.yaml`, `pubspec.lock`
- Generated plugin registrants (share_plus)

## Next phase

Phase 12 — Moving Mode. Phase 11 changes are unpushed in the sandbox;
the user pushes from his PC with normal git (never force-push the
sandbox's synthetic history).
