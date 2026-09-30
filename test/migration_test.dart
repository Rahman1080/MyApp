import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/settings/data/settings_repository.dart';
import 'package:path/path.dart' as p;

/// Schema version guarantees and migration coverage:
/// - v4 is the current schema version
/// - onCreate creates every table and index
/// - a real v1 -> v2 upgrade (adding reminders_enabled and
///   privacy_policy_accepted to user_settings) preserves existing rows and
///   applies the new column defaults
/// - a real v2 -> v3 upgrade (adding value_cents and currency_code to
///   belongings) preserves existing rows; the new columns read as null
/// - a real v3 -> v4 upgrade (adding model, serial number, purchase link,
///   value unknown flag, condition, archive state and the belonging_photos /
///   belonging_history tables) preserves existing rows and applies defaults
/// - a v1 -> v4 chain runs every hop in order
/// Minimal database shell used only to hand-craft a v1-shaped database file
/// with raw SQL before the real [KeepItDatabase] migrates it.
/// A v1-shaped locations table. Every real v1+ database created by the
/// app has one (onCreate builds all tables); the hand-built fixtures in the
/// migration tests below need it explicitly because the v4 -> v5 migration
/// adds place_id to it.
Future<void> _createV1LocationsTable(_RawDb setup) {
  return setup.customStatement('''
      CREATE TABLE locations (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        parent_location_id TEXT,
        notes TEXT,
        photo_path TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
}

class _RawDb extends GeneratedDatabase {
  _RawDb(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  List<TableInfo> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
}

void main() {
  test('schema version is 9', () {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 9);
  });

  test('onCreate creates all tables and indices', () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = tables.map((r) => r.read<String>('name')).toSet();

    for (final expected in [
      'user_settings',
      'categories',
      'locations',
      'purchases',
      'products',
      'receipts',
      'warranties',
      'return_deadlines',
      'refunds',
      'deadlines',
      'belongings',
      'belonging_photos',
      'belonging_history',
      'documents',
      'reminders',
      'tags',
      'tag_links',
      'places',
      'moves',
      'move_items',
      'service_records',
      'warranty_claims',
      'household_members',
    ]) {
      expect(tableNames, contains(expected), reason: 'missing table $expected');
    }

    final indices = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = indices.map((r) => r.read<String>('name')).toSet();
    for (final expected in [
      'idx_purchases_status',
      'idx_purchases_purchase_date',
      'idx_deadlines_due_date',
      'idx_belongings_location_id',
      'idx_belongings_purchase_id',
      'idx_belongings_archive_state',
      'idx_belonging_photos_belonging',
      'idx_belonging_history_belonging',
      'idx_reminders_remind_at',
      'idx_tag_links_entity',
      'idx_locations_place_id',
      'idx_belongings_container_id',
      'idx_service_records_belonging',
      'idx_warranty_claims_warranty',
      'idx_warranties_belonging',
      'idx_belongings_owner_member',
      'idx_refunds_status',
    ]) {
      expect(indexNames, contains(expected), reason: 'missing index $expected');
    }

    // v4 columns exist on a fresh create.
    final belongingColumns = await db
        .customSelect("PRAGMA table_info('belongings')")
        .get();
    final columnNames = belongingColumns
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(columnNames, contains('value_cents'));
    expect(columnNames, contains('currency_code'));
    for (final column in [
      'model',
      'serial_number',
      'purchase_id',
      'value_unknown',
      'condition',
      'archive_state',
      'archived_at',
    ]) {
      expect(columnNames, contains(column), reason: 'missing column $column');
    }

    // v5 columns exist on a fresh create.
    final locationColumns = await db
        .customSelect("PRAGMA table_info('locations')")
        .get();
    final locationColumnNames = locationColumns
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(locationColumnNames, contains('place_id'));
    expect(columnNames, contains('is_container'));
    expect(columnNames, contains('container_id'));

    // Fresh installs are seeded with the default place so the
    // locations.place_id foreign key is always satisfiable.
    final places = await db.select(db.places).get();
    expect(places.length, 1);
    expect(places.single.id, 'place-default');
    expect(places.single.name, 'My Home');
  });

  test(
    'v1 -> v2 migration preserves settings and applies new defaults',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'keepit-migration-test',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v1.sqlite'));

      // Build a v1-shaped database by hand: user_settings without
      // reminders_enabled and privacy_policy_accepted.
      final setup = _RawDb(NativeDatabase(file));
      await setup.customStatement('''
      CREATE TABLE user_settings (
        id TEXT NOT NULL PRIMARY KEY,
        theme_mode TEXT NOT NULL DEFAULT 'system',
        app_lock_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (app_lock_enabled IN (0, 1)),
        biometric_unlock_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (biometric_unlock_enabled IN (0, 1)),
        onboarding_complete INTEGER NOT NULL DEFAULT 0
          CHECK (onboarding_complete IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      await setup.customStatement('''
      INSERT INTO user_settings
        (id, theme_mode, app_lock_enabled, biometric_unlock_enabled,
         onboarding_complete, created_at, updated_at)
      VALUES ('default', 'dark', 1, 0, 1, 1720000000, 1720000000)
    ''');
      // A real v1 database also carries the locations table; the v4 -> v5
      // migration adds place_id to it, so the fixture needs it too.
      await _createV1LocationsTable(setup);
      // migration chain touches belongings, so the shell includes it.
      await setup.customStatement('''
      CREATE TABLE belongings (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        category_id TEXT,
        location_id TEXT,
        photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        created_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        updated_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      )
    ''');
      await setup.customStatement('PRAGMA user_version = 1');
      await setup.close();

      // Opening with the current schema must run the 1 -> 2 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final settings = await db.select(db.userSettings).getSingle();
      expect(settings.id, 'default');
      // Existing data survived...
      expect(settings.themeMode, 'dark');
      expect(settings.appLockEnabled, isTrue);
      expect(settings.onboardingComplete, isTrue);
      // ...and the new columns got their defaults.
      expect(
        settings.remindersEnabled,
        isTrue,
        reason: 'v2 default for existing rows',
      );
      expect(
        settings.privacyPolicyAccepted,
        isFalse,
        reason: 'v2 default for existing rows',
      );

      // The migrated row is fully readable through the repository layer.
      final repo = SettingsRepository(db);
      expect(await repo.getThemeMode(), ThemeMode.dark);
      expect(await repo.getRemindersEnabled(), isTrue);
      expect(await repo.getPrivacyPolicyAccepted(), isFalse);
      expect(await repo.getAppLockEnabled(), isTrue);
    },
  );

  test('foreign keys are enforced on every connection', () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);

    final rows = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(rows.read<int>('foreign_keys'), 1);
  });

  test(
    'v2 -> v3 migration adds value columns, preserving belongings',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v23');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v2.sqlite'));

      // Hand-build a v2-shaped database: belongings without value_cents and
      // currency_code, plus a v2 user_settings row.
      final setup = _RawDb(NativeDatabase(file));
      // A real v2 database always has the purchases table (created in v1);
      // the 2 -> 4 upgrade chain adds a purchase_id FK column, so SQLite
      // requires the parent table when inserting belongings.
      await setup.customStatement('''
      CREATE TABLE purchases (
        id TEXT NOT NULL PRIMARY KEY,
        product_name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
      await setup.customStatement('''
      CREATE TABLE belongings (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        category_id TEXT,
        location_id TEXT,
        photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        created_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        updated_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      )
    ''');
      await setup.customStatement('''
      INSERT INTO belongings
        (id, name, brand, quantity, notes, created_at, updated_at)
      VALUES ('b1', 'Drill', 'Acme', 2, 'Garage shelf', 1720000000, 1720000000)
    ''');
      await setup.customStatement('''
      CREATE TABLE user_settings (
        id TEXT NOT NULL PRIMARY KEY,
        theme_mode TEXT NOT NULL DEFAULT 'system',
        app_lock_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (app_lock_enabled IN (0, 1)),
        biometric_unlock_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (biometric_unlock_enabled IN (0, 1)),
        onboarding_complete INTEGER NOT NULL DEFAULT 0
          CHECK (onboarding_complete IN (0, 1)),
        reminders_enabled INTEGER NOT NULL DEFAULT 1
          CHECK (reminders_enabled IN (0, 1)),
        privacy_policy_accepted INTEGER NOT NULL DEFAULT 0
          CHECK (privacy_policy_accepted IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      await _createV1LocationsTable(setup);
      await setup.customStatement('PRAGMA user_version = 2');
      await setup.close();

      // Opening with the current schema must run the 2 -> 3 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final belonging = await (db.select(
        db.belongings,
      )..where((t) => t.id.equals('b1'))).getSingle();
      expect(belonging.name, 'Drill');
      expect(belonging.brand, 'Acme');
      expect(belonging.quantity, 2);
      // New columns exist and read as null for pre-existing rows.
      expect(belonging.valueCents, isNull);
      expect(belonging.currencyCode, isNull);

      // New rows can store a value and it round-trips.
      final repo = BelongingRepository(db);
      await repo.create(
        BelongingsCompanion.insert(
          name: 'Camera',
          valueCents: const Value(24999),
          currencyCode: const Value('EUR'),
        ),
      );
      final camera = (await repo.search('Camera')).single;
      expect(camera.valueCents, 24999);
      expect(camera.currencyCode, 'EUR');

      // JSON round-trip (used by backup/restore) carries the new fields.
      final restored = Belonging.fromJson(camera.toJson());
      expect(restored.valueCents, 24999);
      expect(restored.currencyCode, 'EUR');
    },
  );

  test(
    'v3 -> v4 migration adds inventory columns, photos and history tables',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v34');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v3.sqlite'));

      // Hand-build a v3-shaped database: belongings with the v3 value columns
      // but none of the v4 inventory columns, and no photos/history tables.
      final setup = _RawDb(NativeDatabase(file));
      // A real v3 database always has the purchases table (created in v1);
      // drift's addColumn carries the FK clause, so SQLite requires it.
      await setup.customStatement('''
      CREATE TABLE purchases (
        id TEXT NOT NULL PRIMARY KEY,
        product_name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
      await setup.customStatement('''
      CREATE TABLE belongings (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        category_id TEXT,
        location_id TEXT,
        photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        value_cents INTEGER,
        currency_code TEXT,
        created_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        updated_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      )
    ''');
      await setup.customStatement('''
      INSERT INTO belongings
        (id, name, brand, quantity, notes, value_cents, currency_code,
         created_at, updated_at)
      VALUES ('b3', 'Drill', 'Acme', 2, 'Garage shelf', 4999, 'USD',
              1720000000, 1720000000)
    ''');
      await _createV1LocationsTable(setup);
      await setup.customStatement('PRAGMA user_version = 3');
      await setup.close();

      // Opening with the current schema must run the 3 -> 4 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final belonging = await (db.select(
        db.belongings,
      )..where((t) => t.id.equals('b3'))).getSingle();
      // Existing data survived...
      expect(belonging.name, 'Drill');
      expect(belonging.brand, 'Acme');
      expect(belonging.quantity, 2);
      expect(belonging.notes, 'Garage shelf');
      expect(belonging.valueCents, 4999);
      expect(belonging.currencyCode, 'USD');
      // ...and the new columns got their defaults.
      expect(
        belonging.archiveState,
        'owned',
        reason: 'v4 default for existing rows',
      );
      expect(
        belonging.valueUnknown,
        isFalse,
        reason: 'v4 default for existing rows',
      );
      expect(belonging.model, isNull);
      expect(belonging.serialNumber, isNull);
      expect(belonging.purchaseId, isNull);
      expect(belonging.condition, isNull);
      expect(belonging.archivedAt, isNull);

      // The new tables exist and start empty.
      final photos = await db.select(db.belongingPhotos).get();
      expect(photos, isEmpty);
      final history = await db.select(db.belongingHistory).get();
      expect(history, isEmpty);

      final indices = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      final indexNames = indices.map((r) => r.read<String>('name')).toSet();
      for (final expected in [
        'idx_belongings_purchase_id',
        'idx_belongings_archive_state',
        'idx_belonging_photos_belonging',
        'idx_belonging_history_belonging',
      ]) {
        expect(
          indexNames,
          contains(expected),
          reason: 'missing index $expected',
        );
      }

      // New rows can use the v4 fields and they round-trip.
      final repo = BelongingRepository(db);
      final id = await repo.create(
        BelongingsCompanion.insert(
          name: 'Camera',
          model: const Value('X100V'),
          serialNumber: const Value('SN-123'),
          condition: const Value('like_new'),
          archiveState: const Value('owned'),
        ),
      );
      final camera = await repo.getById(id);
      expect(camera?.model, 'X100V');
      expect(camera?.serialNumber, 'SN-123');
      expect(camera?.condition, 'like_new');
      // Creating an item writes the automatic "added" history entry.
      final entries = await db.select(db.belongingHistory).get();
      expect(entries.length, 1);
      expect(entries.single.belongingId, id);
    },
  );

  test('v1 -> v5 chain runs all migrations in order', () async {
    final dir = await Directory.systemTemp.createTemp('keepit-migration-v13');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'v1.sqlite'));

    // v1-shaped: old user_settings plus pre-v3 belongings.
    final setup = _RawDb(NativeDatabase(file));
    await setup.customStatement('''
      CREATE TABLE user_settings (
        id TEXT NOT NULL PRIMARY KEY,
        theme_mode TEXT NOT NULL DEFAULT 'system',
        app_lock_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (app_lock_enabled IN (0, 1)),
        biometric_unlock_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (biometric_unlock_enabled IN (0, 1)),
        onboarding_complete INTEGER NOT NULL DEFAULT 0
          CHECK (onboarding_complete IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await setup.customStatement('''
      INSERT INTO user_settings
        (id, theme_mode, app_lock_enabled, biometric_unlock_enabled,
         onboarding_complete, created_at, updated_at)
      VALUES ('default', 'system', 0, 0, 1, 1720000000, 1720000000)
    ''');
    await setup.customStatement('''
      CREATE TABLE belongings (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        category_id TEXT,
        location_id TEXT,
        photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        created_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        updated_at INTEGER NOT NULL
          DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      )
    ''');
    await setup.customStatement('''
      INSERT INTO belongings
        (id, name, quantity, created_at, updated_at)
      VALUES ('b9', 'Passport', 1, 1720000000, 1720000000)
    ''');
    // A real v1 database also has the locations table (created by onCreate);
    // the v4 -> v5 migration adds place_id to it.
    await setup.customStatement('''
      CREATE TABLE locations (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        parent_location_id TEXT,
        notes TEXT,
        photo_path TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await setup.customStatement('''
      INSERT INTO locations (id, name, created_at, updated_at)
      VALUES ('l9', 'Garage', 1720000000, 1720000000)
    ''');
    await setup.customStatement('PRAGMA user_version = 1');
    await setup.close();

    final db = KeepItDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Both hops applied: v2 settings columns...
    final settings = await db.select(db.userSettings).getSingle();
    expect(settings.remindersEnabled, isTrue);
    expect(settings.privacyPolicyAccepted, isFalse);
    // ...v3 belonging columns...
    final belonging = await (db.select(
      db.belongings,
    )..where((t) => t.id.equals('b9'))).getSingle();
    expect(belonging.name, 'Passport');
    expect(belonging.valueCents, isNull);
    expect(belonging.currencyCode, isNull);
    // ...and v4 inventory defaults.
    expect(belonging.archiveState, 'owned');
    expect(belonging.valueUnknown, isFalse);
    expect(belonging.model, isNull);
    expect(belonging.serialNumber, isNull);
    expect(belonging.purchaseId, isNull);
    // The new tables were created by the upgrade.
    expect(await db.select(db.belongingPhotos).get(), isEmpty);
    expect(await db.select(db.belongingHistory).get(), isEmpty);
    // ...and v5 household inventory: the default place exists, the old
    // location was backfilled to it, and the item is not a container.
    final places = await db.select(db.places).get();
    expect(places.length, 1);
    expect(places.single.id, 'place-default');
    expect(places.single.name, 'My Home');
    final location = await (db.select(
      db.locations,
    )..where((t) => t.id.equals('l9'))).getSingle();
    expect(location.placeId, 'place-default');
    expect(belonging.isContainer, isFalse);
    expect(belonging.containerId, isNull);
    final v5Indices = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final v5IndexNames = v5Indices.map((r) => r.read<String>('name')).toSet();
    expect(v5IndexNames, contains('idx_locations_place_id'));
    expect(v5IndexNames, contains('idx_belongings_container_id'));
  });

  test(
    'v4 -> v5 migration backfills the default place and container columns',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v45');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v4.sqlite'));

      // Hand-build a v4-shaped database: places table absent, locations
      // without place_id, belongings without container columns.
      final setup = _RawDb(NativeDatabase(file));
      await setup.customStatement('''
      CREATE TABLE locations (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        parent_location_id TEXT,
        notes TEXT,
        photo_path TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
      await setup.customStatement('''
      INSERT INTO locations (id, name, parent_location_id, created_at, updated_at)
      VALUES ('l1', 'Home', NULL, 1720000000, 1720000000),
             ('l2', 'Bedroom', 'l1', 1720000000, 1720000000)
    ''');
      await setup.customStatement('''
      CREATE TABLE belongings (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        category_id TEXT,
        location_id TEXT,
        photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        value_cents INTEGER,
        currency_code TEXT,
        model TEXT,
        serial_number TEXT,
        purchase_id TEXT,
        value_unknown INTEGER NOT NULL DEFAULT 0,
        condition TEXT,
        archive_state TEXT NOT NULL DEFAULT 'owned',
        archived_at INTEGER,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
      await setup.customStatement('''
      INSERT INTO belongings (id, name, location_id, created_at, updated_at)
      VALUES ('b1', 'Lamp', 'l2', 1720000000, 1720000000),
             ('b2', 'Spare bulb', NULL, 1720000000, 1720000000)
    ''');
      await setup.customStatement('PRAGMA user_version = 4');
      await setup.close();

      // Opening with the current schema must run the 4 -> 5 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      // Default place created exactly once...
      final places = await db.select(db.places).get();
      expect(places.length, 1);
      expect(places.single.id, 'place-default');
      // ...and every pre-existing location was assigned to it, so no manual
      // setup is forced on existing users.
      final locations = await db.select(db.locations).get();
      expect(locations.length, 2);
      for (final location in locations) {
        expect(
          location.placeId,
          'place-default',
          reason: 'location ${location.id} keeps working after the upgrade',
        );
      }
      // Existing belongings are not containers and sit in no container.
      final belongings = await db.select(db.belongings).get();
      expect(belongings.length, 2);
      for (final belonging in belongings) {
        expect(belonging.isContainer, isFalse);
        expect(belonging.containerId, isNull);
      }
      final lamp = belongings.firstWhere((b) => b.id == 'b1');
      expect(lamp.name, 'Lamp');
      expect(lamp.locationId, 'l2');
    },
  );

  test(
    'v5 -> v6 migration creates moves tables without touching data',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v56');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v5.sqlite'));

      // Build a v6 database, then drop the Phase 12 tables and rewind the
      // version to simulate a v5 database.
      final setup = KeepItDatabase(NativeDatabase(file));
      await setup.customStatement(
        "INSERT INTO belongings (id, name) VALUES "
        "('b1', 'Lamp')",
      );
      await setup.customStatement('DROP TABLE move_items');
      await setup.customStatement('DROP TABLE moves');
      await setup.customStatement('PRAGMA user_version = 5');
      await setup.close();

      // Opening with the current schema must run the 5 -> 6 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((r) => r.read<String>('name')).toSet();
      expect(tableNames, contains('moves'));
      expect(tableNames, contains('move_items'));
      // Existing data is untouched.
      final belongings = await db.select(db.belongings).get();
      expect(belongings.map((b) => b.id), contains('b1'));
    },
  );

  test(
    'v6 -> v7 migration adds lifecycle columns without touching data',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v67');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v6.sqlite'));

      // Hand-build a v6-shaped belongings table (no Phase 13 columns).
      final setup = _RawDb(NativeDatabase(file));
      await setup.customStatement('''
      CREATE TABLE belongings (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        model TEXT,
        serial_number TEXT,
        category_id TEXT,
        location_id TEXT,
        is_container INTEGER NOT NULL DEFAULT 0,
        container_id TEXT,
        purchase_id TEXT,
        photo_path TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        value_cents INTEGER,
        currency_code TEXT,
        value_unknown INTEGER NOT NULL DEFAULT 0,
        condition TEXT,
        archive_state TEXT NOT NULL DEFAULT 'owned',
        archived_at INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
      await setup.customStatement('''
      INSERT INTO belongings (id, name, archive_state, created_at, updated_at)
      VALUES ('b1', 'Lamp', 'owned', 1720000000, 1720000000)
    ''');
      await setup.customStatement('PRAGMA user_version = 6');
      await setup.close();

      // Opening with the current schema must run the 6 -> 7 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final cols = await db.customSelect("PRAGMA table_info(belongings)").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      for (final col in [
        'acquisition_type',
        'acquisition_date',
        'disposition_date',
        'disposition_price_cents',
        'disposition_currency_code',
        'disposition_recipient',
        'disposition_method',
        'disposition_notes',
      ]) {
        expect(names, contains(col), reason: 'missing column $col');
      }
      // Existing data is untouched; new columns read as null.
      final belongings = await db.select(db.belongings).get();
      expect(belongings, hasLength(1));
      expect(belongings.single.name, 'Lamp');
      expect(belongings.single.acquisitionType, isNull);
      expect(belongings.single.dispositionDate, isNull);
    },
  );

  test(
    'v7 -> v8 migration creates service tables without touching data',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v78');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v7.sqlite'));

      // Build a v8 database, then drop the Phase 14 tables and rewind the
      // version to simulate a v7 database.
      final setup = KeepItDatabase(NativeDatabase(file));
      await setup.customStatement(
        "INSERT INTO belongings (id, name) VALUES "
        "('b1', 'Lamp')",
      );
      await setup.customStatement('DROP TABLE warranty_claims');
      await setup.customStatement('DROP TABLE service_records');
      await setup.customStatement('PRAGMA user_version = 7');
      await setup.close();

      // Opening with the current schema must run the 7 -> 8 upgrade.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((r) => r.read<String>('name')).toSet();
      expect(tableNames, contains('service_records'));
      expect(tableNames, contains('warranty_claims'));
      // Existing data is untouched.
      final belongings = await db.select(db.belongings).get();
      expect(belongings.map((b) => b.id), contains('b1'));
    },
  );

  test(
    'v8 -> v9 migration creates household tables without touching data',
    () async {
      final dir = await Directory.systemTemp.createTemp('keepit-migration-v89');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v8.sqlite'));

      // Build a v9 database, then drop the Phase 15 table/columns and
      // rewind the version to simulate a v8 database.
      final setup = KeepItDatabase(NativeDatabase(file));
      await setup.customStatement(
        "INSERT INTO belongings (id, name) VALUES ('b1', 'Lamp')",
      );
      await setup.customStatement('DROP TABLE household_members');
      await setup.customStatement('PRAGMA user_version = 8');
      await setup.close();

      // Opening with the current schema must run the 8 -> 9 upgrade.
      // Note: SQLite cannot drop columns, so the v8 fixture keeps the
      // v9 columns; the migration is idempotent and skips them.
      final db = KeepItDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((r) => r.read<String>('name')).toSet();
      expect(tableNames, contains('household_members'));
      // Existing data is untouched.
      final belongings = await db.select(db.belongings).get();
      expect(belongings.map((b) => b.id), contains('b1'));
    },
  );
}
