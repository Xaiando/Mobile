import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/core/time/time_providers.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// Backlog T2: the Tasting tab.
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
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Scrolls the open tasting until [finder] is built.
  Future<void> reveal(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find
            .descendant(
              of: find.byType(Stepper),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  /// The chip [label] of attribute [key].
  Finder chip(String key, String label) => find.descendant(
    of: find.byKey(ValueKey('tasting-attribute-$key')),
    matching: find.text(label),
  );

  // Drift's streams need real time: fake async would wait forever.
  Future<T> read<T>(WidgetTester tester, Future<T> Function() query) async =>
      (await tester.runAsync(query)) as T;

  testApp('fills in a whole grid, finishes it and lists it', (tester) async {
    await launch(tester);
    await tab(tester, 'Tasting');
    expect(find.text('Practise tasting'), findsOneWidget);

    await tap(tester, find.text('New tasting'));
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'tg_structured',
      reason: 'the WSET track tastes with the structured grid',
    );
    await tap(tester, find.text('Start tasting'));

    final grid = await read(
      tester,
      () => TastingPractice(db).layout('tg_structured'),
    );
    expect(find.text('Jammy'), findsNothing, reason: 'the other grid');
    for (final (i, section) in grid.sections.indexed) {
      for (final attribute in grid.inSection(section)) {
        await tap(tester, chip(attribute.key, attribute.values.last.label));
        if (!attribute.isSingle) {
          await tap(tester, chip(attribute.key, attribute.values.first.label));
        }
      }
      await tap(tester, find.byKey(ValueKey('tasting-step-next-$i')));
    }
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Chalk and lemon.',
    );
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('tasting-step-finish')));

    expect(find.textContaining('Finished 2026-10-01'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Chalk and lemon.'), 300);

    final session = (await read(
      tester,
      () => TastingPractice(db).watchSessions().first,
    )).single;
    expect(session.completedAt, DateTime.utc(2026, 10, 1, 9));
    expect(session.isBlind, isTrue);
    expect(session.notes, 'Chalk and lemon.');
    final answers = await read(
      tester,
      () => TastingPractice(db).answers(session.id),
    );
    expect(answers.keys.toSet(), {for (final a in grid.attributes) a.key});
    expect(answers['acidity'], {'very_high'});
    expect(answers['aromas'], {'citrus', 'savoury'});

    await tap(tester, find.byType(BackButton));
    expect(find.widgetWithText(ListTile, 'Structured tasting'), findsOneWidget);
    expect(find.textContaining('Finished 2026-10-01 · Blind'), findsOneWidget);
  });

  testApp('resumes a tasting where it stopped, and says what is missing', (
    tester,
  ) async {
    await launch(tester);
    await tester.runAsync(() async {
      final tasting = TastingPractice(db);
      final session = await tasting.start('tg_deductive', isBlind: false);
      final grid = await tasting.layout('tg_deductive');
      for (final attribute in grid.inSection('Sight')) {
        await tasting.choose(session.id, attribute.key, {
          attribute.values.first.valueKey,
        });
      }
    });
    await tab(tester, 'Tasting');
    expect(find.textContaining('In progress'), findsOneWidget);

    await tap(tester, find.text('Deductive tasting'));
    expect(
      chip('fruit_state', 'Jammy').hitTestable(),
      findsOneWidget,
      reason: 'the tasting opens at its first unfinished section',
    );
    await tap(tester, chip('fruit_state', 'Jammy'));

    await reveal(tester, find.text('Notes and wine'));
    await tap(tester, find.text('Notes and wine'));
    await tap(tester, find.byKey(const ValueKey('tasting-step-finish')));
    expect(
      find.textContaining('Answer the rest of the grid first: Wood'),
      findsOneWidget,
    );
    expect(find.text('Choose one'), findsWidgets);
    final session = (await read(
      tester,
      () => TastingPractice(db).watchSessions().first,
    )).single;
    expect(session.completedAt, isNull);

    await tap(tester, find.byTooltip('Delete'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Practise tasting'), findsOneWidget);
  });

  testApp('tastes a wine from the journal blind, and reveals it at the end', (
    tester,
  ) async {
    await launch(tester);
    await tester.runAsync(
      () => WineJournal(db).create(
        const JournalDraft(
          producerName: 'Example Producer',
          appellationText: 'Chablis',
        ),
      ),
    );
    await tab(tester, 'Cellar');
    await tap(tester, find.text('Example Producer'));
    await tap(tester, find.byTooltip('Taste this wine'));

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
      reason: 'a known wine is tasted sighted unless the learner says',
    );
    await tap(tester, find.text('Blind tasting'));
    await tap(tester, find.text('Start tasting'));

    await reveal(tester, find.text('Notes and wine'));
    await tap(tester, find.text('Notes and wine'));
    expect(find.text('The wine is revealed when you finish.'), findsOneWidget);
    expect(find.textContaining('Example Producer'), findsNothing);

    // One write at a time: each one wakes the screen's queries, which run
    // on the test's fake clock and must finish before the next write.
    final tasting = TastingPractice(db);
    final session = (await read(
      tester,
      () => tasting.watchSessions().first,
    )).single;
    final grid = await read(
      tester,
      () => tasting.layout(session.tastingGridId),
    );
    for (final attribute in grid.attributes) {
      await tester.runAsync(
        () => tasting.choose(session.id, attribute.key, {
          attribute.values.first.valueKey,
        }),
      );
      await tester.pumpAndSettle();
    }
    await tap(tester, find.byKey(const ValueKey('tasting-step-finish')));
    expect(find.text('The wine was Example Producer'), findsOneWidget);

    await tap(tester, find.text('The wine was Example Producer'));
    expect(find.text('Tastings'), findsOneWidget);
    expect(find.textContaining('Finished 2026-10-01 · Blind'), findsOneWidget);
  });
}
