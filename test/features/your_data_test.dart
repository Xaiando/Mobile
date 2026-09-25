import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';
import 'package:sommelier/features/settings/your_data.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// Stands in for the platform's file dialogs.
class _Files implements BackupFiles {
  String? savedName;
  List<int>? saved;
  List<int>? toOpen;

  @override
  Future<bool> save(String name, List<int> bytes) async {
    savedName = name;
    saved = bytes;
    return true;
  }

  @override
  Future<List<int>?> open() async => toOpen;
}

/// Backlog R1: Settings → Your data, and flagging a question.
void main() {
  late AppDatabase db;
  late _Files files;

  setUp(() {
    db = openTestDatabase();
    files = _Files();
  });
  tearDown(() => db.close());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      db,
      overrides: [
        backupFilesProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(
          Clock.fixed(DateTime.utc(2026, 10, 1, 9)),
        ),
      ],
    );
    await tap(tester, find.text('WSET Level 3'));
  }

  /// Opens Settings and taps [label] in it.
  Future<void> setting(WidgetTester tester, String label) async {
    if (find.text('Settings').evaluate().isEmpty) {
      await tap(tester, find.widgetWithText(NavigationDestination, 'Home'));
      await tap(tester, find.byTooltip('Settings'));
    }
    await tester.scrollUntilVisible(find.text(label), 300);
    await tap(tester, find.text(label));
  }

  // Drift's streams need real time: fake async would wait forever.
  Future<T> read<T>(WidgetTester tester, Future<T> Function() query) async =>
      (await tester.runAsync(query)) as T;

  Future<List<String?>> producers(WidgetTester tester) async => [
    for (final entry in await read(
      tester,
      () => WineJournal(db).watchAll().first,
    ))
      entry.producerName,
  ];

  /// Starts a practice session and answers its first card.
  Future<void> studyOneCard(WidgetTester tester) async {
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    await tap(tester, find.widgetWithText(FilledButton, 'Start session'));
    final question = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    ).read(studySessionProvider).value!.turn!.question;
    if (question.isMultipleChoice) {
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, question.answer.name),
      );
    } else {
      await tap(tester, find.text('Show answer'));
      await tap(tester, find.widgetWithText(FilledButton, 'Good'));
    }
  }

  testApp('exports the data, and imports a backup over it', (tester) async {
    await tester.runAsync(
      () =>
          WineJournal(db)
              .create(const JournalDraft(producerName: 'Kept Producer')),
    );
    await launch(tester);

    await setting(tester, 'Export your data');
    expect(find.text('Your data is saved.'), findsOneWidget);
    expect(files.savedName, 'sommelier-backup-2026-10-01.json');
    final exported =
        jsonDecode(utf8.decode(files.saved!)) as Map<String, Object?>;
    expect(exported['format'], 'sommelier-user-data');
    final tables = exported['tables']! as Map<String, Object?>;
    expect(
      [
        for (final row in tables['wine_journal_entries']! as List)
          row['producer_name'],
      ],
      ['Kept Producer'],
    );

    await tester.runAsync(
      () =>
          WineJournal(db)
              .create(const JournalDraft(producerName: 'Added Later')),
    );
    await tester.pumpAndSettle();
    files.toOpen = files.saved;
    await setting(tester, 'Import a backup');
    await tap(tester, find.widgetWithText(FilledButton, 'Choose a file'));
    expect(
      find.text('Imported 0 reviews, 1 wine and 0 tastings.'),
      findsOneWidget,
    );
    expect(await producers(tester), ['Kept Producer']);
  });

  testApp('says when a file is not a backup, and keeps the data', (
    tester,
  ) async {
    await tester.runAsync(
      () =>
          WineJournal(db)
              .create(const JournalDraft(producerName: 'Kept Producer')),
    );
    await launch(tester);
    for (final bytes in [
      utf8.encode('A shopping list'),
      [0xff, 0xfe, 0x00],
    ]) {
      files.toOpen = bytes;
      await setting(tester, 'Import a backup');
      await tap(tester, find.widgetWithText(FilledButton, 'Choose a file'));
      expect(find.text('This file is not a Sommelier backup.'), findsOneWidget);
    }
    expect(await producers(tester), ['Kept Producer']);
  });

  testApp('resets the progress, and erasing starts onboarding again', (
    tester,
  ) async {
    await launch(tester);
    await studyOneCard(tester);
    Future<int> states() async =>
        (await read(tester, () => db.select(db.reviewStates).get())).length;
    expect(await states(), 1);

    await setting(tester, 'Reset study progress');
    await tap(tester, find.widgetWithText(FilledButton, 'Reset'));
    expect(find.text('Your study progress is reset.'), findsOneWidget);
    expect(await states(), 0);

    await setting(tester, 'Erase all data');
    await tap(tester, find.widgetWithText(FilledButton, 'Erase'));
    expect(find.text('Welcome to Sommelier Study Companion'), findsOneWidget);
  });

  testApp('flags a question, and Settings counts the flag', (tester) async {
    await launch(tester);
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    await tap(tester, find.widgetWithText(FilledButton, 'Start session'));
    final question = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    ).read(studySessionProvider).value!.turn!.question;

    await tap(tester, find.byTooltip('Flag this question'));
    await tap(tester, find.text('The question is unclear'));
    await tester.enterText(find.byType(TextField), '  Two answers fit.  ');
    await tap(tester, find.widgetWithText(FilledButton, 'Flag'));
    expect(
      find.textContaining('The flag is kept on this device'),
      findsOneWidget,
    );

    final flag = (await read(
      tester,
      () => db.select(db.questionFlags).get(),
    )).single;
    expect(
      (flag.knowledgeItemId, flag.questionTemplateId, flag.reason, flag.note),
      (
        question.knowledgeItemId,
        question.questionTemplateId,
        'unclear',
        'Two answers fit.',
      ),
    );

    await setting(tester, 'Questions you flagged');
    expect(find.textContaining('1 flagged.'), findsOneWidget);
  });
}
