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

  /// Journal writes cross the SQLite event loop. Wait for the actual saved
  /// row before asserting the route, rather than assuming one UI pump is
  /// enough for a duplicate check and transaction.
  Future<void> waitForEntry(
    WidgetTester tester,
    bool Function(WineJournalEntry) matches,
  ) async {
    await tester.runAsync(
      () =>
          WineJournal(db)
              .watchAll()
              .firstWhere((entries) => entries.any(matches))
              .timeout(const Duration(seconds: 10)),
    );
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
    await waitForEntry(
      tester,
      (entry) => entry.producerName == 'Example Producer',
    );
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
    await reveal(tester, find.text('Clear'), delta: -200);
    await tap(tester, find.text('Clear'));
    expect(find.text('No tasting date'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await waitForEntry(tester, (entry) => entry.appellationText == 'Chablis');

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
    await waitForEntry(tester, (entry) => entry.producerName == 'New name');
    expect(find.text('New name'), findsWidgets);
    expect(find.bySemanticsLabel('Rated 5 of 5'), findsOneWidget);

    await tap(tester, find.byTooltip('Delete'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Your wine journal'), findsOneWidget);
  });

  testApp('label text only fills clues the learner accepts', (tester) async {
    await launch(tester);
    await tap(tester, find.text('Log a wine'));
    await type(tester, 'Producer', 'Transcript Estate');
    final raw = find.widgetWithText(
      TextField,
      'Recognized or manually transcribed label text',
    );
    await reveal(tester, raw);
    await tester.enterText(raw, 'Transcript Estate 2019 13.5%');
    await tester.pumpAndSettle();

    final vintage = find.widgetWithText(TextField, 'Vintage');
    final abv = find.widgetWithText(TextField, 'Alcohol %');
    await reveal(tester, vintage, delta: -200);
    expect(tester.widget<TextField>(vintage).controller!.text, isEmpty);
    expect(tester.widget<TextField>(abv).controller!.text, isEmpty);

    await reveal(tester, find.text('Use vintage 2019'));
    await tap(tester, find.text('Use vintage 2019'));
    await tap(tester, find.text('Use 13.5% alcohol'));
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await waitForEntry(
      tester,
      (entry) =>
          entry.producerName == 'Transcript Estate' &&
          entry.vintage == 2019 &&
          entry.abvPercent == 13.5,
    );
  });

  testApp('full-label clues fill only accepted, still-empty fields', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, find.text('Log a wine'));
    await type(tester, 'Producer', 'Hand typed estate');
    final raw = find.widgetWithText(
      TextField,
      'Recognized or manually transcribed label text',
    );
    await reveal(tester, raw);
    await tester.enterText(
      raw,
      'Producer: Scanned Estate\nCuvée Réserve\nBarolo DOCG\n'
      'Grapes: Nebbiolo\n2020\n14%',
    );
    await tester.pumpAndSettle();

    final producerChip = find.ancestor(
      of: find.text('Use producer Scanned Estate'),
      matching: find.byType(ActionChip),
    );
    expect(tester.widget<ActionChip>(producerChip).onPressed, isNull);
    for (final label in [
      'Use cuvée Réserve',
      'Use region Barolo',
      'Use grapes Nebbiolo',
      'Use vintage 2020',
      'Use 14.0% alcohol',
    ]) {
      await tap(tester, find.text(label));
    }
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await waitForEntry(
      tester,
      (entry) =>
          entry.producerName == 'Hand typed estate' &&
          entry.cuveeName == 'Réserve' &&
          entry.appellationText == 'Barolo' &&
          entry.grapesText == 'Nebbiolo' &&
          entry.vintage == 2020 &&
          entry.abvPercent == 14,
    );
  });

  testApp('keeps transcribed label text while scrolling through the editor', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, find.text('Log a wine'));
    final raw = find.widgetWithText(
      TextField,
      'Recognized or manually transcribed label text',
    );
    await reveal(tester, raw);
    await tester.enterText(raw, 'Estate 2019 13.5%');
    await tester.pumpAndSettle();
    expect(find.text('Use vintage 2019'), findsOneWidget);

    await reveal(
      tester,
      find.widgetWithText(TextField, 'Producer'),
      delta: -350,
    );
    await reveal(tester, raw, delta: 350);
    expect(tester.widget<TextField>(raw).controller!.text, 'Estate 2019 13.5%');
    expect(find.text('Use vintage 2019'), findsOneWidget);
    expect(find.text('Use 13.5% alcohol'), findsOneWidget);
  });

  testApp('warns before saving a separate duplicate', (tester) async {
    await tester.runAsync(
      () => WineJournal(db).create(
        const JournalDraft(producerName: 'Repeated Estate', vintage: 2020),
      ),
    );
    await launch(tester);
    await tap(tester, find.text('Log a wine'));
    await type(tester, 'Producer', 'Repeated Estate');
    await type(tester, 'Vintage', '2020');
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    expect(find.text('Similar wine already logged'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Review'));
    final before = await tester.runAsync(
      () => WineJournal(db).watchAll().first,
    );
    expect(before, hasLength(1));

    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await tap(tester, find.widgetWithText(FilledButton, 'Save separate entry'));
    await tester.runAsync(
      () =>
          WineJournal(db)
              .watchAll()
              .firstWhere((entries) => entries.length == 2)
              .timeout(const Duration(seconds: 10)),
    );
    await tester.pumpAndSettle();
  });
}
