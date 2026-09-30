import 'package:drift/drift.dart';

import 'tables.dart';

part 'keepit_database.g.dart';

/// The single offline-first database for KeepIt.
///
/// All tables, foreign keys and indices are defined in [tables.dart].
/// Schema version history:
/// - v1 (2026-09-29): initial schema for Phase 1.
/// - v2 (2026-09-30): UserSettings gains `reminders_enabled` and
///   `privacy_policy_accepted` (Phase 7). Existing rows get the declared
///   defaults (true / false) via the column defaults.
/// - v3 (2026-09-30): Belongings gains `value_cents` and `currency_code`
///   (Phase 8). Both are nullable, so existing rows simply read as null.
/// - v4 (2026-09-30): Phase 9 personal-property inventory. Belongings gains
///   `model`, `serial_number`, `purchase_id` (FK), `value_unknown`,
///   `condition`, `archive_state` (default 'owned') and `archived_at`;
///   new `belonging_photos` and `belonging_history` tables. Existing rows
///   keep their data; new columns read as null/defaults.
/// - v5 (2026-09-30): Phase 10 home & household inventory. New `places`
///   table; Locations gains `place_id` (FK, default 'place-default') and the
///   migration creates a default "My Home" place and assigns every existing
///   location to it. Belongings gains `is_container` and `container_id`.
/// - v6 (2026-09-30): Phase 12 moving mode. New `moves` and `move_items`
///   tables for tracking relocations; no existing data touched.
/// - v7 (2026-09-30): Phase 13 item lifecycle. Belongings gains 8 lifecycle
///   columns (`acquisition_type`, `acquisition_date`, `disposition_date`,
///   `disposition_price_cents`, `disposition_currency_code`,
///   `disposition_recipient`, `disposition_method`, `disposition_notes`).
/// - v8 (2026-09-30): Phase 14 service records and warranty claims. New
///   `service_records` and `warranty_claims` tables; Warranties gains
///   `belonging_id` (FK to belongings).
/// - v9 (2026-09-30): Phase 15 household sharing. New `household_members`
///   table; Belongings gains `privacy_level` (default 'private') and
///   `owner_member_id` (FK to household_members).
@DriftDatabase(
  tables: [
    UserSettings,
    Categories,
    Places,
    Locations,
    Purchases,
    Products,
    Receipts,
    Warranties,
    ReturnDeadlines,
    Refunds,
    Deadlines,
    Belongings,
    BelongingPhotos,
    BelongingHistory,
    Documents,
    Reminders,
    Tags,
    TagLinks,
    Moves,
    MoveItems,
    ServiceRecords,
    WarrantyClaims,
    HouseholdMembers,
  ],
)
class KeepItDatabase extends _$KeepItDatabase {
  KeepItDatabase(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      for (final indexSql in keepItIndices) {
        await customStatement(indexSql);
      }
      // Fresh installs start with the default place, so the
      // locations.place_id FK (defaulting to 'place-default') is always
      // satisfied. Upgrades from v4 get it from the v4 -> v5 migration.
      await into(places).insert(
        PlacesCompanion.insert(
          id: const Value(defaultPlaceId),
          name: 'My Home',
        ),
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Step-by-step upgrades; keep this chain exhaustive.
      if (from == 1) {
        // v1 -> v2 (Phase 7): new UserSettings columns. The declared
        // column defaults backfill existing rows (reminders on,
        // privacy policy not yet accepted).
        await m.addColumn(userSettings, userSettings.remindersEnabled);
        await m.addColumn(userSettings, userSettings.privacyPolicyAccepted);
      }
      if (from < 3) {
        // v2 -> v3 (Phase 8): optional estimated value on belongings.
        // Both columns are nullable, so existing rows read as null.
        await m.addColumn(belongings, belongings.valueCents);
        await m.addColumn(belongings, belongings.currencyCode);
      }
      if (from < 4) {
        // v3 -> v4 (Phase 9): personal-property inventory.
        // New columns are nullable or carry defaults, so existing
        // belongings keep their data and read sensible defaults
        // ('owned', valueUnknown false).
        await m.addColumn(belongings, belongings.model);
        await m.addColumn(belongings, belongings.serialNumber);
        await m.addColumn(belongings, belongings.purchaseId);
        await m.addColumn(belongings, belongings.valueUnknown);
        await m.addColumn(belongings, belongings.condition);
        await m.addColumn(belongings, belongings.archiveState);
        await m.addColumn(belongings, belongings.archivedAt);
        await m.createTable(belongingPhotos);
        await m.createTable(belongingHistory);
        await customStatement(
          'CREATE INDEX idx_belongings_purchase_id ON belongings (purchase_id)',
        );
        await customStatement(
          'CREATE INDEX idx_belongings_archive_state ON belongings (archive_state)',
        );
        await customStatement(
          'CREATE INDEX idx_belonging_photos_belonging ON belonging_photos (belonging_id)',
        );
        await customStatement(
          'CREATE INDEX idx_belonging_history_belonging ON belonging_history (belonging_id, occurred_at)',
        );
      }
      if (from < 5) {
        // v4 -> v5 (Phase 10): home & household inventory.
        // 1. Create the places table and insert the default place first,
        //    so the new locations.place_id FK (defaulting to the default
        //    place id) is satisfied when existing rows are backfilled.
        await m.createTable(places);
        await into(places).insert(
          PlacesCompanion.insert(
            id: const Value(defaultPlaceId),
            name: 'My Home',
          ),
        );
        // 2. place_id on locations: the SQL default backfills every
        //    existing row to the default place; no user action needed.
        await m.addColumn(locations, locations.placeId);
        // 3. Container mode on belongings: existing rows are not
        //    containers and sit in no container.
        await m.addColumn(belongings, belongings.isContainer);
        await m.addColumn(belongings, belongings.containerId);
        await customStatement(
          'CREATE INDEX idx_locations_place_id ON locations (place_id)',
        );
        await customStatement(
          'CREATE INDEX idx_belongings_container_id ON belongings (container_id)',
        );
      }
      if (from < 6) {
        // v5 -> v6 (Phase 12): moving mode.
        // Two brand-new tables; no existing rows are touched.
        await m.createTable(moves);
        await m.createTable(moveItems);
        await customStatement(
          'CREATE INDEX idx_moves_status ON moves (status)',
        );
        await customStatement(
          'CREATE INDEX idx_move_items_move ON move_items (move_id, status)',
        );
        await customStatement(
          'CREATE INDEX idx_move_items_belonging ON move_items (belonging_id)',
        );
      }
      if (from < 7) {
        // v6 -> v7 (Phase 13): item lifecycle.
        // Acquisition and disposition columns on belongings; all nullable
        // so existing rows are untouched. Idempotent: skips columns that
        // already exist (e.g. if a previous partial upgrade added them).
        final existingCols = await customSelect(
          "SELECT name FROM pragma_table_info('belongings')",
        ).get().then((rows) => rows.map((r) => r.read<String>('name')).toSet());
        Future<void> addIfMissing(String name, GeneratedColumn column) async {
          if (!existingCols.contains(name)) {
            await m.addColumn(belongings, column);
          }
        }

        await addIfMissing('acquisition_type', belongings.acquisitionType);
        await addIfMissing('acquisition_date', belongings.acquisitionDate);
        await addIfMissing('disposition_date', belongings.dispositionDate);
        await addIfMissing(
          'disposition_price_cents',
          belongings.dispositionPriceCents,
        );
        await addIfMissing(
          'disposition_currency_code',
          belongings.dispositionCurrencyCode,
        );
        await addIfMissing(
          'disposition_recipient',
          belongings.dispositionRecipient,
        );
        await addIfMissing('disposition_method', belongings.dispositionMethod);
        await addIfMissing('disposition_notes', belongings.dispositionNotes);
      }
      if (from < 8) {
        // v7 -> v8 (Phase 14): advanced warranty & service history.
        // Two brand-new tables; no existing rows are touched.
        // Idempotent: skips tables/columns that already exist.
        final existingTables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get().then((rows) => rows.map((r) => r.read<String>('name')).toSet());

        if (!existingTables.contains('service_records')) {
          await m.createTable(serviceRecords);
          await customStatement(
            'CREATE INDEX idx_service_records_belonging ON service_records '
            '(belonging_id, service_date)',
          );
        }
        if (!existingTables.contains('warranty_claims')) {
          await m.createTable(warrantyClaims);
          await customStatement(
            'CREATE INDEX idx_warranty_claims_warranty ON warranty_claims '
            '(warranty_id, claim_date)',
          );
        }
        // Nullable direct belonging link on warranties; existing rows keep
        // their purchase-based link. Only if warranties table exists
        // (it may not in partial v1 fixtures used by migration tests).
        if (existingTables.contains('warranties')) {
          final warrantyCols = await customSelect(
            "SELECT name FROM pragma_table_info('warranties')",
          ).get().then((rows) => rows.map((r) => r.read<String>('name')).toSet());
          if (!warrantyCols.contains('belonging_id')) {
            await m.addColumn(warranties, warranties.belongingId);
          }
        }
      }
      if (from < 9) {
        // v8 -> v9 (Phase 15): household/family sharing (local-only).
        // New household_members table; privacy_level and owner_member_id
        // on belongings. Privacy defaults to 'private'; existing items
        // stay private.
        final existingTables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get().then((rows) => rows.map((r) => r.read<String>('name')).toSet());

        if (!existingTables.contains('household_members')) {
          await m.createTable(householdMembers);
        }

        final belongingCols = await customSelect(
          "SELECT name FROM pragma_table_info('belongings')",
        ).get().then((rows) => rows.map((r) => r.read<String>('name')).toSet());
        if (!belongingCols.contains('privacy_level')) {
          await m.addColumn(belongings, belongings.privacyLevel);
        }
        if (!belongingCols.contains('owner_member_id')) {
          await m.addColumn(belongings, belongings.ownerMemberId);
        }
      }
    },
    beforeOpen: (details) async {
      // Enforce foreign keys on every connection; SQLite disables them
      // by default and drift does not enable them automatically.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
