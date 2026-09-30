import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

/// Repository CRUD, streams and constraints for the organization-side
/// entities: deadlines, reminders, belongings, locations, documents,
/// categories and tags.
void main() {
  late KeepItDatabase db;
  late DeadlineRepository deadlines;
  late ReminderRepository reminders;
  late BelongingRepository belongings;
  late LocationRepository locations;
  late DocumentRepository documents;
  late CategoryRepository categories;
  late TagRepository tags;

  setUp(() {
    db = openInMemoryDatabase();
    deadlines = DeadlineRepository(db);
    reminders = ReminderRepository(db);
    belongings = BelongingRepository(db);
    locations = LocationRepository(db);
    documents = DocumentRepository(db);
    categories = CategoryRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  String newId() => const Uuid().v4();

  group('DeadlineRepository', () {
    test('watchUpcoming hides done items unless asked', () async {
      final openId = newId();
      await deadlines.create(
        DeadlinesCompanion.insert(
          id: Value(openId),
          title: 'Renew passport',
          dueDate: DateTime(2026, 11, 1),
        ),
      );
      final doneId = newId();
      await deadlines.create(
        DeadlinesCompanion.insert(
          id: Value(doneId),
          title: 'Old bill',
          dueDate: DateTime(2026, 8, 1),
        ),
      );
      await deadlines.markDone(doneId, done: true);

      final upcoming = await deadlines.watchUpcoming().first;
      expect(upcoming.map((d) => d.id), [openId]);

      final all = await deadlines.watchUpcoming(includeDone: true).first;
      expect(all.map((d) => d.id).toSet(), {openId, doneId});
    });

    test('dueOnOrBefore finds open deadlines in range', () async {
      await deadlines.create(
        DeadlinesCompanion.insert(
          id: Value(newId()),
          title: 'Car registration',
          dueDate: DateTime(2026, 10, 5),
        ),
      );
      await deadlines.create(
        DeadlinesCompanion.insert(
          id: Value(newId()),
          title: 'Far future',
          dueDate: DateTime(2027, 1, 1),
        ),
      );
      final due = await deadlines.dueOnOrBefore(DateTime(2026, 10, 31));
      expect(due.map((d) => d.title), ['Car registration']);
    });

    test('deadline with unknown purchase violates FK', () async {
      expect(
        () => deadlines.create(
          DeadlinesCompanion.insert(
            id: Value(newId()),
            title: 'Orphan',
            dueDate: DateTime(2026, 10, 5),
            relatedPurchaseId: const Value('no-such-purchase'),
          ),
        ),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });
  });

  group('ReminderRepository', () {
    test('watchPending orders by fire time; markDone hides', () async {
      final reminderId = newId();
      await reminders.create(
        RemindersCompanion.insert(
          id: Value(reminderId),
          title: 'Return the shoes',
          remindAt: DateTime(2026, 10, 2, 9),
        ),
      );
      await reminders.create(
        RemindersCompanion.insert(
          id: Value(newId()),
          title: 'Earlier one',
          remindAt: DateTime(2026, 10, 1, 9),
        ),
      );

      var pending = await reminders.watchPending().first;
      expect(
        pending.map((r) => r.title),
        ['Earlier one', 'Return the shoes'],
      );

      await reminders.markDone(reminderId, done: true);
      pending = await reminders.watchPending().first;
      expect(pending.map((r) => r.title), ['Earlier one']);
    });

    test('overduePending finds past-due reminders', () async {
      await reminders.create(
        RemindersCompanion.insert(
          id: Value(newId()),
          title: 'Missed',
          remindAt: DateTime(2026, 9, 1),
        ),
      );
      await reminders.create(
        RemindersCompanion.insert(
          id: Value(newId()),
          title: 'Future',
          remindAt: DateTime(2026, 12, 1),
        ),
      );
      final overdue = await reminders.overduePending(DateTime(2026, 9, 29));
      expect(overdue.map((r) => r.title), ['Missed']);
    });

    test('deleteForEntity removes only linked reminders', () async {
      const entityId = 'deadline-1';
      await reminders.create(
        RemindersCompanion.insert(
          id: Value(newId()),
          title: 'Linked 7d',
          remindAt: DateTime(2026, 10, 1),
          entityType: const Value('deadline'),
          entityId: const Value(entityId),
        ),
      );
      final otherId = newId();
      await reminders.create(
        RemindersCompanion.insert(
          id: Value(otherId),
          title: 'Unlinked',
          remindAt: DateTime(2026, 10, 1),
        ),
      );

      await reminders.deleteForEntity('deadline', entityId);
      expect(await reminders.forEntity('deadline', entityId), isEmpty);
      expect(await reminders.getById(otherId), isNotNull);
    });
  });

  group('LocationRepository + BelongingRepository', () {
    test('location with unknown parent violates FK', () async {
      expect(
        () => locations.create(
          LocationsCompanion.insert(
            id: Value(newId()),
            name: 'Drawer',
            parentLocationId: const Value('no-such-parent'),
          ),
        ),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });

    test('deleting a parent nulls the child reference (SET NULL)', () async {
      final homeId = newId();
      await locations.create(
        LocationsCompanion.insert(id: Value(homeId), name: 'Home'),
      );
      final childId = newId();
      await locations.create(
        LocationsCompanion.insert(
          id: Value(childId),
          name: 'Bedroom',
          parentLocationId: Value(homeId),
        ),
      );

      await locations.delete(homeId);
      expect((await locations.requireById(childId)).parentLocationId, isNull);
    });

    test('watchByLocation streams belongings of that location', () async {
      final drawerId = newId();
      await locations.create(
        LocationsCompanion.insert(id: Value(drawerId), name: 'Drawer'),
      );
      await belongings.create(
        BelongingsCompanion.insert(
          id: Value(newId()),
          name: 'Passport',
          locationId: Value(drawerId),
        ),
      );
      final items = await belongings.watchByLocation(drawerId).first;
      expect(items.map((b) => b.name), ['Passport']);
    });

    test('belonging with unknown location violates FK', () async {
      expect(
        () => belongings.create(
          BelongingsCompanion.insert(
            id: Value(newId()),
            name: 'Camera',
            locationId: const Value('no-such-location'),
          ),
        ),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });
  });

  group('DocumentRepository', () {
    test('watchByPurchase streams documents for the purchase', () async {
      final purchaseId = newId();
      await PurchaseRepository(db).create(
        PurchasesCompanion.insert(
          id: Value(purchaseId),
          productName: 'TV',
        ),
      );
      await documents.create(
        DocumentsCompanion.insert(
          id: Value(newId()),
          title: 'Warranty card',
          filePath: '/docs/warranty.pdf',
          purchaseId: Value(purchaseId),
        ),
      );
      final docs = await documents.watchByPurchase(purchaseId).first;
      expect(docs.map((d) => d.title), ['Warranty card']);
    });

    test('document with unknown purchase violates FK', () async {
      expect(
        () => documents.create(
          DocumentsCompanion.insert(
            id: Value(newId()),
            title: 'Orphan',
            filePath: '/docs/orphan.pdf',
            purchaseId: const Value('no-such-purchase'),
          ),
        ),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });
  });

  group('CategoryRepository', () {
    test('duplicate category name is rejected', () async {
      await categories.create(
        CategoriesCompanion.insert(id: Value(newId()), name: 'Electronics'),
      );
      expect(
        () => categories.create(
          CategoriesCompanion.insert(id: Value(newId()), name: 'Electronics'),
        ),
        throwsA(isA<RecordAlreadyExistsException>()),
      );
    });

    test('watchAll streams alphabetically', () async {
      await categories.create(
        CategoriesCompanion.insert(id: Value(newId()), name: 'Books'),
      );
      await categories.create(
        CategoriesCompanion.insert(id: Value(newId()), name: 'Appliances'),
      );
      final all = await categories.watchAll().first;
      expect(all.map((c) => c.name), ['Appliances', 'Books']);
    });
  });

  group('TagRepository', () {
    test('getOrCreate returns the same tag twice', () async {
      final first = await tags.getOrCreate('gift');
      final second = await tags.getOrCreate('gift');
      expect(first.id, second.id);
    });

    test('link is idempotent; tagsForEntity resolves tags', () async {
      final tag = await tags.getOrCreate('gift');
      const entityId = 'purchase-9';
      await tags.link(
        tagId: tag.id,
        entityType: 'purchase',
        entityId: entityId,
      );
      await tags.link(
        tagId: tag.id,
        entityType: 'purchase',
        entityId: entityId,
      );

      final linked = await tags.tagsForEntity(
        entityType: 'purchase',
        entityId: entityId,
      );
      expect(linked.map((t) => t.name), ['gift']);

      final ids = await tags.entityIdsForTag(tag.id, 'purchase');
      expect(ids, [entityId]);

      await tags.unlink(
        tagId: tag.id,
        entityType: 'purchase',
        entityId: entityId,
      );
      expect(
        await tags.tagsForEntity(
          entityType: 'purchase',
          entityId: entityId,
        ),
        isEmpty,
      );
    });

    test('deleting a tag cascades its links', () async {
      final tag = await tags.getOrCreate('temp');
      await tags.link(tagId: tag.id, entityType: 'purchase', entityId: 'p-1');
      await tags.delete(tag.id);
      expect(await tags.entityIdsForTag(tag.id, 'purchase'), isEmpty);
    });
  });
}
