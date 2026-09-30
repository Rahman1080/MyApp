import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/category_repository.dart';
import 'package:keepit/core/database/repositories/deadline_repository.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/core/database/repositories/reminder_repository.dart';
import 'package:keepit/core/notifications/notification_service.dart';
import 'package:keepit/core/notifications/reminder_coordinator.dart';
import 'package:keepit/features/deadlines/presentation/deadline_form_screen.dart';

import 'fake_notification_backend.dart';

/// Widget tests for the deadline form: validation, and the permission-gated
/// reminder flow (rationale first, OS prompt only after "Allow").
void main() {
  late KeepItDatabase db;
  late FakeNotificationBackend backend;
  late NotificationService notificationService;
  late ReminderCoordinator coordinator;
  late DeadlineRepository deadlines;
  late ReminderRepository reminders;

  setUp(() {
    initTestTimezones();
    db = openInMemoryDatabase();
    backend = FakeNotificationBackend();
    reminders = ReminderRepository(db);
    notificationService = NotificationService(
      backend: backend,
      reminders: reminders,
    );
    coordinator = ReminderCoordinator(
      reminders: reminders,
      notifications: notificationService,
    );
    deadlines = DeadlineRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeadlineFormScreen(
          deadlineRepository: deadlines,
          categoryRepository: CategoryRepository(db),
          purchaseRepository: PurchaseRepository(db),
          reminderRepository: reminders,
          reminderCoordinator: coordinator,
          notificationService: notificationService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pump();
  }

  /// Pumps frames until [condition] holds, bounded so a stuck UI fails fast
  /// instead of hanging. Needed because the saving spinner animates
  /// indefinitely, which defeats pumpAndSettle.
  Future<void> pumpUntil(
    WidgetTester tester,
    Future<bool> Function() condition,
  ) async {
    for (var i = 0; i < 200; i++) {
      if (await condition()) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Timed out waiting for condition.');
  }

  Future<void> waitForSave(WidgetTester tester) => pumpUntil(
        tester,
        () async =>
            (await deadlines.getUpcoming(includeDone: true)).isNotEmpty,
      );

  /// Lets the post-row bookkeeping (reminder rows + scheduling) finish. The
  /// deadline row is written before reminders, so waiting for the row alone
  /// races the reminder assertions.
  Future<void> settleAfterSave(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Picks a due date through the date picker in text-input mode, so the
  /// test does not depend on the current calendar month layout.
  Future<void> pickDueDate(WidgetTester tester, DateTime date) async {
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    // Switch the date picker from calendar to text-input mode.
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      '${date.month}/${date.day}/${date.year}',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('requires a title', (tester) async {
    await pumpForm(tester);
    await tapSave(tester);
    await tester.pump();
    expect(find.text('Give the deadline a title.'), findsOneWidget);
    expect(await deadlines.getUpcoming(includeDone: true), isEmpty);
  });

  testWidgets('requires a due date', (tester) async {
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(const Key('deadline-title')),
      'Pay rent',
    );
    await tapSave(tester);
    await tester.pump();
    expect(find.text('Pick a due date.'), findsOneWidget);
    expect(await deadlines.getUpcoming(includeDone: true), isEmpty);
  });

  testWidgets('saving with reminders asks permission, then schedules',
      (tester) async {
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(const Key('deadline-title')),
      'Pay rent',
    );
    final due = DateTime.now().add(const Duration(days: 30));
    await pickDueDate(tester, DateTime(due.year, due.month, due.day));

    // Enable all three reminder switches ("On the day" is on by default).
    // They sit below the fold, so scroll them into view first.
    await tester.scrollUntilVisible(
      find.text('A week before'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final switches = find.byType(SwitchListTile);
    expect(switches, findsNWidgets(3));
    await tester.tap(switches.at(0));
    await tester.pump();
    await tester.tap(switches.at(1));
    await tester.pump();

    // The rationale must appear first and the OS prompt only after tapping
    // "Continue".
    await tapSave(tester);
    await pumpUntil(
      tester,
      () async => find.text('Enable reminders?').evaluate().isNotEmpty,
    );
    expect(backend.requestCalls, 0);
    await tester.tap(find.text('Continue'));
    // Scheduling is the last step of the save, so wait for it directly.
    await pumpUntil(tester, () async => backend.scheduled.length == 3);

    expect(backend.requestCalls, 1);
    final saved = await deadlines.getUpcoming(includeDone: true);
    expect(saved, hasLength(1));
    expect(saved.single.title, 'Pay rent');
    final rows = await reminders.forEntity('deadline', saved.single.id);
    // A week before, a day before, on the day — all still future.
    expect(rows, hasLength(3));
    expect(backend.scheduled, hasLength(3));
  });

  testWidgets('denied permission saves the deadline without reminders',
      (tester) async {
    backend.grantPermissions = false;
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(const Key('deadline-title')),
      'Pay rent',
    );
    final due = DateTime.now().add(const Duration(days: 30));
    await pickDueDate(tester, DateTime(due.year, due.month, due.day));

    await tapSave(tester);
    await pumpUntil(
      tester,
      () async => find.text('Enable reminders?').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Continue'));
    // The denial notice must appear (it auto-dismisses, so assert inside the
    // wait rather than after the settle pumps below).
    var sawDeniedMessage = false;
    await pumpUntil(tester, () async {
      final found = find
          .text(
            'Notifications were denied, so this was saved without reminders.',
          )
          .evaluate()
          .isNotEmpty;
      if (found) sawDeniedMessage = true;
      return found;
    });
    expect(sawDeniedMessage, isTrue);
    await waitForSave(tester);
    await settleAfterSave(tester);

    expect(backend.requestCalls, 1);
    final saved = await deadlines.getUpcoming(includeDone: true);
    expect(saved, hasLength(1));
    expect(
      await reminders.forEntity('deadline', saved.single.id),
      isEmpty,
    );
    expect(backend.scheduled, isEmpty);
  });

  testWidgets('no reminders enabled means no permission prompt', (tester) async {
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(const Key('deadline-title')),
      'Pay rent',
    );
    final due = DateTime.now().add(const Duration(days: 30));
    await pickDueDate(tester, DateTime(due.year, due.month, due.day));

    // Turn off all three reminder switches ("On the day" is on by default).
    // They sit below the fold, so scroll them into view first.
    await tester.scrollUntilVisible(
      find.text('A week before'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    for (final tile in tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList()) {
      if (tile.value) {
        await tester.tap(find.byWidget(tile));
        await tester.pumpAndSettle();
      }
    }

    await tapSave(tester);
    await waitForSave(tester);
    await settleAfterSave(tester);
    await tester.pump();
    expect(find.text('Enable reminders?'), findsNothing);
    expect(backend.requestCalls, 0);
    final saved = await deadlines.getUpcoming(includeDone: true);
    expect(saved, hasLength(1));
    expect(
      await reminders.forEntity('deadline', saved.single.id),
      isEmpty,
    );
  });
}
