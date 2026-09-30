import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/core/database/tables.dart';
import 'package:keepit/features/ask/domain/ask_service.dart';

/// Phase 16: Ask KEEPIT — grounded natural-language search.
void main() {
  late KeepItDatabase db;
  late AskKeepitService ask;
  late BelongingRepository belongings;
  late LocationRepository locations;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    ask = AskKeepitService(db);
    belongings = BelongingRepository(db);
    locations = LocationRepository(db);

    // Seed test data.
    final locId = newRecordId();
    await locations.create(
      LocationsCompanion(
        id: Value(locId),
        name: const Value('Garage'),
      ),
    );
    await belongings.create(
      BelongingsCompanion(
        name: const Value('Hammer'),
        locationId: Value(locId),
        valueCents: const Value(2500),
        currencyCode: const Value('USD'),
      ),
    );
    await belongings.create(
      const BelongingsCompanion(name: Value('Screwdriver')),
    );
  });

  tearDown(() => db.close());

  group('Phase 16 Ask KEEPIT', () {
    test('parses "where is X" intent', () {
      final q = ask.parseQuery('where is hammer');
      expect(q.intent, AskIntent.whereIs);
      expect(q.subject, 'hammer');
    });

    test('parses "where\'s X" intent', () {
      final q = ask.parseQuery("where's hammer");
      expect(q.intent, AskIntent.whereIs);
      expect(q.subject, 'hammer');
    });

    test('parses "what is in Y" intent', () {
      final q = ask.parseQuery('what is in garage');
      expect(q.intent, AskIntent.whatIsIn);
      expect(q.subject, 'garage');
    });

    test('parses "warranty for X" intent', () {
      final q = ask.parseQuery('warranty for hammer');
      expect(q.intent, AskIntent.warrantyFor);
      expect(q.subject, 'hammer');
    });

    test('parses "when did I buy X" intent', () {
      final q = ask.parseQuery('when did i buy hammer');
      expect(q.intent, AskIntent.whenBought);
      expect(q.subject, 'hammer');
    });

    test('parses "how much is X worth" intent', () {
      final q = ask.parseQuery('how much is hammer worth');
      expect(q.intent, AskIntent.howMuchWorth);
      expect(q.subject, 'hammer');
    });

    test('parses "show me X" as search', () {
      final q = ask.parseQuery('show me hammer');
      expect(q.intent, AskIntent.search);
      expect(q.subject, 'hammer');
    });

    test('answers "where is hammer" with location', () async {
      final answer = await ask.ask('where is hammer');
      expect(answer.hasResults, isTrue);
      expect(answer.answerText, contains('Hammer'));
      expect(answer.answerText, contains('Garage'));
    });

    test('answers "where is X" for unknown item honestly', () async {
      final answer = await ask.ask('where is unicorn');
      expect(answer.hasResults, isFalse);
      expect(answer.answerText, contains("couldn't find"));
    });

    test('answers "what is in garage" with items', () async {
      final answer = await ask.ask('what is in garage');
      expect(answer.hasResults, isTrue);
      expect(answer.answerText, contains('Hammer'));
    });

    test('answers "how much is hammer worth" with value', () async {
      final answer = await ask.ask('how much is hammer worth');
      expect(answer.hasResults, isTrue);
      expect(answer.answerText, contains('25.00'));
    });

    test('answers "how much is X worth" for item without value', () async {
      final answer = await ask.ask('how much is screwdriver worth');
      expect(answer.answerText, contains('no value'));
    });

    test('never fabricates data', () async {
      // Asking about something that doesn't exist must not invent an answer.
      final answer = await ask.ask('where is the moon');
      expect(answer.hasResults, isFalse);
      // The answer must explicitly state it couldn't find the item,
      // not hallucinate a location.
      expect(answer.answerText.toLowerCase(), contains("couldn't find"));
    });
  });
}
