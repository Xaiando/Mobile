import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/time/time_providers.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      db,
      overrides: [
        clockProvider.overrideWithValue(
          Clock.fixed(DateTime.utc(2026, 10, 1, 9)),
        ),
      ],
    );
    await tester.tap(find.text('Cellar'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Scrolls the journal editor's form until [finder] is built: down, or
  /// up with a negative [delta].
  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    double delta = 200,
  }) => tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );

  Future<void> type(WidgetTester tester, String label, String text) async {
    final field = find.widgetWithText(TextField, label);
    if (field.evaluate().isEmpty) await reveal(tester, field, delta: -200);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  testApp('logs a wine, links it to the curriculum and lists it', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('Your wine journal'), findsOneWidget);

    await tap(tester, find.text('Log a wine'));
    await type(tester, 'Producer', 'Example Producer');
    await type(tester, 'Appellation or region', 'Barolo');
    await type(tester, 'Grapes', 'Nebbiolo');

    final barolo = find.widgetWithText(FilterChip, 'Barolo · appellation');
    final nebbiolo = find.widgetWithText(FilterChip, 'Nebbiolo · grape');
    await reveal(tester, nebbiolo);
    expect(tester.widget<FilterChip>(barolo).selected, isTrue);
    expect(tester.widget<FilterChip>(nebbiolo).selected, isTrue);
    await tap(tester, nebbiolo);
    expect(tester.widget<FilterChip>(nebbiolo).selected, isFalse);

    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    expect(find.text('Example Producer'), findsWidgets);
    expect(find.widgetWithText(Chip, 'Barolo'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Nebbiolo'), findsNothing);
    expect(find.text('Tasted'), findsOneWidget);
    expect(find.text('2026-10-01'), findsOneWidget);

    await tap(tester, find.text('Cellar'));
    expect(find.widgetWithText(ListTile, 'Example Producer'), findsOneWidget);
  });

  testApp('drops a link whose name leaves the text, and saves an undated '
      'entry', (tester) async {
    await launch(tester);
    await tap(tester, find.text('Log a wine'));
    await type(tester, 'Appellation or region', 'Barolo');
    await reveal(
      tester,
      find.widgetWithText(FilterChip, 'Barolo · appellation'),
    );
    await type(tester, 'Appellation or region', 'Chablis');
    await reveal(
      tester,
      find.widgetWithText(FilterChip, 'Chablis · appellation'),
    );
    expect(
      find.widgetWithText(FilterChip, 'Barolo · appellation'),
      findsNothing,
    );
    await tap(tester, find.text('Clear'));
    expect(find.text('No tasting date'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Save'));

    final entry = (await tester.runAsync(
      () => WineJournal(db).watchAll().first,
    ))!.single;
    expect(entry.tastedOn, isNull);
    final links = await tester.runAsync(
      () => WineJournal(db).linkedNodeIds(entry.id),
    );
    expect(links, {'n_geo_chablis'});
  });

  testApp('says why an entry cannot be saved', (tester) async {
    await launch(tester);
    await tap(tester, find.text('Log a wine'));
    await type(tester, 'Vintage', '19x9');
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    expect(find.textContaining('A vintage is a year'), findsOneWidget);
    expect(find.textContaining('Name the wine'), findsOneWidget);
    // Drift's streams need real time: fake async would wait forever.
    final entries = await tester.runAsync(
      () => WineJournal(db).watchAll().first,
    );
    expect(entries, isEmpty);
  });

  testApp('edits and deletes an entry', (tester) async {
    await launch(tester);
    await tester.runAsync(
      () =>
          WineJournal(db)
              .create(const JournalDraft(producerName: 'Old name', rating: 3)),
    );
    await tester.pumpAndSettle();

    await tap(tester, find.text('Old name'));
    await tap(tester, find.byTooltip('Edit'));
    await type(tester, 'Producer', 'New name');
    await tap(tester, find.byTooltip('5 of 5'));
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    expect(find.text('New name'), findsWidgets);
    expect(find.bySemanticsLabel('Rated 5 of 5'), findsOneWidget);

    await tap(tester, find.byTooltip('Delete'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Your wine journal'), findsOneWidget);
  });
}
