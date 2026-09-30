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
@DriftDatabase(
  tables: [
    UserSettings,
    Categories,
    Locations,
    Purchases,
    Products,
    Receipts,
    Warranties,
    ReturnDeadlines,
    Refunds,
    Deadlines,
    Belongings,
    Documents,
    Reminders,
    Tags,
    TagLinks,
  ],
)
class KeepItDatabase extends _$KeepItDatabase {
  KeepItDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          for (final indexSql in keepItIndices) {
            await customStatement(indexSql);
          }
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Step-by-step upgrades; keep this chain exhaustive.
          if (from == 1) {
            // v1 -> v2 (Phase 7): new UserSettings columns. The declared
            // column defaults backfill existing rows (reminders on,
            // privacy policy not yet accepted).
            await m.addColumn(
                userSettings, userSettings.remindersEnabled);
            await m.addColumn(
                userSettings, userSettings.privacyPolicyAccepted);
          }
          if (from < 3) {
            // v2 -> v3 (Phase 8): optional estimated value on belongings.
            // Both columns are nullable, so existing rows read as null.
            await m.addColumn(belongings, belongings.valueCents);
            await m.addColumn(belongings, belongings.currencyCode);
          }
        },
        beforeOpen: (details) async {
          // Enforce foreign keys on every connection; SQLite disables them
          // by default and drift does not enable them automatically.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
