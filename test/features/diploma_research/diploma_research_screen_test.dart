import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_research/diploma_research.dart';
import 'package:sommelier/core/diploma_research/diploma_research_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/features/diploma_research/diploma_research_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

class _SavedCopies implements ResearchCopyFiles {
  String? text;

  @override
  Future<bool> save(String name, List<int> bytes) async {
    expect(name, 'd6-research-workspace.txt');
    text = utf8.decode(bytes);
    return true;
  }
}

class _DelayedResearchRepository extends DiplomaResearchRepository {
  _DelayedResearchRepository(super.db, {super.clock, super.random});

  Completer<void>? holdTextSave;

  @override
  Future<DiplomaResearchWorkspace> updateText(String field, String text) async {
    if (holdTextSave case final gate?) {
      await gate.future;
    }
    return super.updateText(field, text);
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaResearchRepository repository;
  late _SavedCopies copies;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = DiplomaResearchRepository(
      db,
      clock: time.clock,
      random: Random(23),
    );
    copies = _SavedCopies();
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diplomaResearchRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          researchCopyFilesProvider.overrideWithValue(copies),
        ],
        child: const MaterialApp(home: DiplomaResearchScreen()),
      ),
    );
    await settle(tester);
  }

  testApp('D6 screen saves text and exports an ungraded tutor copy', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('not an official WSET title'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('d6-start')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('d6-title')),
      'My own vineyard question',
    );
    await tester.enterText(
      find.byKey(const ValueKey('d6-brief')),
      'I will compare evidence.',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('d6-draft')));
    await tester.enterText(
      find.byKey(const ValueKey('d6-draft')),
      'Four words in this draft.',
    );
    await settle(tester);
    expect(find.textContaining('5 approximate draft words'), findsOneWidget);
    expect(
      (await tester.runAsync(() => repository.load()))!.workspace!.title,
      'My own vineyard question',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('d6-add-source')));
    await tester.tap(find.byKey(const ValueKey('d6-add-source')));
    await settle(tester);
    final id = (await tester.runAsync(() => repository.load()))!
        .workspace!
        .sources
        .single
        .id;
    final citation = find.byKey(ValueKey('d6-source-$id-citation'));
    await tester.ensureVisible(citation);
    await tester.enterText(citation, 'Author, vineyard study');
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('d6-export')));
    await tester.tap(find.byKey(const ValueKey('d6-export')));
    await settle(tester);
    expect(copies.text, contains('My own vineyard question'));
    expect(copies.text, contains('Author, vineyard study'));
    expect(copies.text, contains('Four words in this draft.'));
    expect(copies.text, contains('Not an official WSET submission or grade.'));
    expect(tester.takeException(), isNull);
  });

  testApp('reopening the screen restores saved research fields', (
    tester,
  ) async {
    await repository.start();
    await repository.updateText('title', 'Saved project');
    await repository.updateText('draft', 'My saved argument.');
    await show(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('d6-title')))
          .initialValue,
      'Saved project',
    );
    expect(find.textContaining('3 approximate draft words'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testApp('export waits for a pending text save', (tester) async {
    final delayed = _DelayedResearchRepository(
      db,
      clock: time.clock,
      random: Random(31),
    );
    repository = delayed;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('d6-start')));
    await settle(tester);
    delayed.holdTextSave = Completer<void>();
    await tester.enterText(
      find.byKey(const ValueKey('d6-title')),
      'A still-pending edit',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('d6-export')));
    await tester.tap(find.byKey(const ValueKey('d6-export')));
    await tester.pump();
    expect(copies.text, isNull);
    expect(find.byKey(const ValueKey('d6-saving')), findsOneWidget);
    delayed.holdTextSave!.complete();
    await settle(tester);
    expect(copies.text, contains('A still-pending edit'));
    expect(
      (await tester.runAsync(() => repository.load()))!.workspace!.title,
      'A still-pending edit',
    );
    expect(tester.takeException(), isNull);
  });

  testApp('back navigation waits for the last queued edit', (tester) async {
    final delayed = _DelayedResearchRepository(
      db,
      clock: time.clock,
      random: Random(37),
    );
    repository = delayed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diplomaResearchRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          researchCopyFilesProvider.overrideWithValue(copies),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiplomaResearchScreen(),
                  ),
                ),
                child: const Text('Open research'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open research'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('d6-start')));
    await settle(tester);
    delayed.holdTextSave = Completer<void>();
    await tester.enterText(
      find.byKey(const ValueKey('d6-title')),
      'Save before leaving',
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(DiplomaResearchScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('d6-saving')), findsOneWidget);
    delayed.holdTextSave!.complete();
    await settle(tester);
    expect(find.byType(DiplomaResearchScreen), findsNothing);
    expect((await repository.load()).workspace!.title, 'Save before leaving');
    expect(tester.takeException(), isNull);
  });
}
