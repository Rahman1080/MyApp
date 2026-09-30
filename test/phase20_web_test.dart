import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/web/domain/web_companion_service.dart';

/// Phase 20: Web Companion (static HTML export).
void main() {
  late KeepItDatabase db;
  late WebCompanionService web;
  late BelongingRepository belongings;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    web = WebCompanionService(db);
    belongings = BelongingRepository(db);
  });

  tearDown(() => db.close());

  group('Phase 20 Web Companion', () {
    test('generates valid HTML document', () async {
      final html = await web.generateHtml();
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<html'));
      expect(html, contains('</html>'));
    });

    test('includes page title', () async {
      final html = await web.generateHtml(title: 'My Stuff');
      expect(html, contains('<title>My Stuff</title>'));
      expect(html, contains('<h1>My Stuff</h1>'));
    });

    test('includes inventory items', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final html = await web.generateHtml();
      expect(html, contains('Hammer'));
      expect(html, contains('1 item(s)'));
    });

    test('escapes HTML in item names', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('<script>alert("x")</script>')),
      );

      final html = await web.generateHtml();
      // The raw script tag should not appear unescaped.
      expect(html, isNot(contains('<script>alert("x")</script>')));
      // The escaped version should appear.
      expect(html, contains('&lt;script&gt;'));
    });

    test('includes item details', () async {
      await belongings.create(
        const BelongingsCompanion(
          name: Value('Hammer'),
          brand: Value('Stanley'),
          model: Value('STHT51304'),
          valueCents: Value(2500),
        ),
      );

      final html = await web.generateHtml();
      expect(html, contains('Stanley'));
      expect(html, contains('STHT51304'));
      expect(html, contains('25.00'));
    });

    test('includes search functionality', () async {
      final html = await web.generateHtml();
      expect(html, contains('id="search"'));
      expect(html, contains('filterItems()'));
    });

    test('includes responsive CSS', () async {
      final html = await web.generateHtml();
      expect(html, contains('@media'));
      expect(html, contains('max-width'));
    });

    test('empty inventory generates valid page', () async {
      final html = await web.generateHtml();
      expect(html, contains('0 item(s)'));
      expect(html, contains('<!DOCTYPE html>'));
    });
  });
}
