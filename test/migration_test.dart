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
/// - v3 is the current schema version
/// - onCreate creates every table and index
/// - a real v1 -> v2 upgrade (adding reminders_enabled and
///   privacy_policy_accepted to user_settings) preserves existing rows and
///   applies the new column defaults
/// - a real v2 -> v3 upgrade (adding value_cents and currency_code to
///   belongings) preserves existing rows; the new columns read as null
/// - a v1 -> v3 chain runs both hops in order
/// Minimal database shell used only to hand-craft a v1-shaped database file
/// with raw SQL before the real [KeepItDatabase] migrates it.
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
  test('schema version is 3', () {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 3);
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
      'documents',
      'reminders',
      'tags',
      'tag_links',
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
      'idx_reminders_remind_at',
      'idx_tag_links_entity',
    ]) {
      expect(indexNames, contains(expected), reason: 'missing index $expected');
    }

    // v3 columns exist on a fresh create.
    final belongingColumns = await db
        .customSelect("PRAGMA table_info('belongings')")
        .get();
    final columnNames =
        belongingColumns.map((r) => r.read<String>('name')).toSet();
    expect(columnNames, contains('value_cents'));
    expect(columnNames, contains('currency_code'));
  });

  test('v1 -> v2 migration preserves settings and applies new defaults',
      () async {
    final dir = await Directory.systemTemp.createTemp('keepit-migration-test');
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
    // A real v1 database also carries every other table; the v1 -> v3
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
    expect(settings.remindersEnabled, isTrue,
        reason: 'v2 default for existing rows');
    expect(settings.privacyPolicyAccepted, isFalse,
        reason: 'v2 default for existing rows');

    // The migrated row is fully readable through the repository layer.
    final repo = SettingsRepository(db);
    expect(await repo.getThemeMode(), ThemeMode.dark);
    expect(await repo.getRemindersEnabled(), isTrue);
    expect(await repo.getPrivacyPolicyAccepted(), isFalse);
    expect(await repo.getAppLockEnabled(), isTrue);
  });

  test('foreign keys are enforced on every connection', () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);

    final rows = await db
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    expect(rows.read<int>('foreign_keys'), 1);
  });

  test('v2 -> v3 migration adds value columns, preserving belongings',
      () async {
    final dir = await Directory.systemTemp.createTemp('keepit-migration-v23');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'v2.sqlite'));

    // Hand-build a v2-shaped database: belongings without value_cents and
    // currency_code, plus a v2 user_settings row.
    final setup = _RawDb(NativeDatabase(file));
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
    await setup.customStatement('PRAGMA user_version = 2');
    await setup.close();

    // Opening with the current schema must run the 2 -> 3 upgrade.
    final db = KeepItDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final belonging =
        await (db.select(db.belongings)..where((t) => t.id.equals('b1')))
            .getSingle();
    expect(belonging.name, 'Drill');
    expect(belonging.brand, 'Acme');
    expect(belonging.quantity, 2);
    // New columns exist and read as null for pre-existing rows.
    expect(belonging.valueCents, isNull);
    expect(belonging.currencyCode, isNull);

    // New rows can store a value and it round-trips.
    final repo = BelongingRepository(db);
    await repo.create(BelongingsCompanion.insert(
      name: 'Camera',
      valueCents: const Value(24999),
      currencyCode: const Value('EUR'),
    ));
    final camera =
        (await repo.search('Camera')).single;
    expect(camera.valueCents, 24999);
    expect(camera.currencyCode, 'EUR');

    // JSON round-trip (used by backup/restore) carries the new fields.
    final restored = Belonging.fromJson(camera.toJson());
    expect(restored.valueCents, 24999);
    expect(restored.currencyCode, 'EUR');
  });

  test('v1 -> v3 chain runs both migrations in order', () async {
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
    await setup.customStatement('PRAGMA user_version = 1');
    await setup.close();

    final db = KeepItDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Both hops applied: v2 settings columns...
    final settings = await db.select(db.userSettings).getSingle();
    expect(settings.remindersEnabled, isTrue);
    expect(settings.privacyPolicyAccepted, isFalse);
    // ...and v3 belonging columns.
    final belonging =
        await (db.select(db.belongings)..where((t) => t.id.equals('b9')))
            .getSingle();
    expect(belonging.name, 'Passport');
    expect(belonging.valueCents, isNull);
    expect(belonging.currencyCode, isNull);
  });
}
