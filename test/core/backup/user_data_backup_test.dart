import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/feedback/question_feedback.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/settings/user_settings.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late UserDataBackup backup;

  Future<AppDatabase> freshDatabase() async {
    final fresh = openTestDatabase();
    await CurriculumIngester(
      fresh,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    return fresh;
  }

  // Two databases are open at once on purpose: the backup's source and its
  // destination.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    db = await freshDatabase();
    backup = UserDataBackup(db, clock: time.clock);
  });
  tearDown(() => db.close());

  /// A learner who has used every part of the app, so every user table has
  /// rows: a track, settings, reviews, a flag, a wine and a tasting.
  Future<void> study(AppDatabase db, {int seed = 1}) async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final settings = LearnerSettings(db, clock: time.clock);
    await settings.confirmAge();
    await settings.completeOnboarding();
    await settings.setAppearance(AppearanceMode.dark);

    final reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(seed),
    );
    final presenter = QuestionPresenter(db);
    final mcq = await presenter.present(
      'ki_chablis_grape',
      'qt_principal_grape_fwd_mcq',
      seed: 7,
    );
    await reviews.answerMultipleChoice(mcq, mcq.answer);
    await reviews.gradeFlashcard(
      await presenter.present(
        'ki_champagne_soil',
        'qt_soil_fwd_flashcard',
        seed: 1,
      ),
      fsrs.Rating.good,
    );
    await QuestionFeedback(db, clock: time.clock, random: Random(seed)).flag(
      itemId: 'ki_chablis_grape',
      templateId: 'qt_principal_grape_fwd_mcq',
      reason: FlagReason.unclear,
      note: 'Two answers fit.',
    );
    final wine = await WineJournal(db, clock: time.clock, random: Random(seed))
        .create(
          const JournalDraft(
            producerName: 'Example Producer',
            appellationText: 'Chablis',
            rating: 4,
          ),
          nodeIds: {'n_geo_chablis'},
        );
    final tasting = TastingPractice(
      db,
      clock: time.clock,
      random: Random(seed),
    );
    final session = await tasting.start(
      'tg_structured',
      journalEntryId: wine.id,
    );
    await tasting.choose(session.id, 'acidity', {'high'});
    await tasting.choose(session.id, 'aromas', {'citrus', 'mineral'});
  }

  Future<Map<String, List<Map<String, Object?>>>> contents(
    AppDatabase db,
  ) async => {
    for (final table in UserDataBackup.tables)
      table: [
        for (final row
            in await db
                .customSelect('SELECT * FROM "$table" ORDER BY rowid')
                .get())
          row.data,
      ],
  };

  test('lists every user table, parents first (UD-1)', () async {
    Future<List<String>> names(String sql) async => [
      for (final row in await db.customSelect(sql).get())
        row.read<String>('name'),
    ];
    final tables = await names(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    // Curriculum and generated tables carry the ingestion guard.
    final curriculum = await names(
      "SELECT tbl_name AS name FROM sqlite_master WHERE type = 'trigger' "
      "AND name LIKE '%_read_only_insert'",
    );
    const locks = {'curriculum_ingestions', 'user_data_rewrites'};
    expect(UserDataBackup.tables.toSet(), {
      for (final table in tables)
        if (!curriculum.contains(table) && !locks.contains(table)) table,
    });
    // A table comes after every user table it references.
    for (final (i, table) in UserDataBackup.tables.indexed) {
      final parents = await names(
        "SELECT \"table\" AS name FROM pragma_foreign_key_list('$table')",
      );
      for (final parent in parents) {
        final at = UserDataBackup.tables.indexOf(parent);
        expect(at, lessThan(i), reason: '$table references $parent');
      }
    }
  });

  test('export then import round-trips every user table (R1)', () async {
    await study(db);
    final before = await contents(db);
    for (final table in UserDataBackup.tables) {
      expect(before[table], isNotEmpty, reason: '$table has rows to carry');
    }
    final json = await backup.exportJson();
    final document = jsonDecode(json) as Map<String, Object?>;
    expect(document['format'], 'sommelier-user-data');
    expect(document['schema_version'], db.schemaVersion);
    expect(document['curriculum_release'], bundledDataset().version);
    expect(document['exported_at'], '2026-10-01T09:00:00.000Z');

    final other = await freshDatabase();
    addTearDown(other.close);
    final summary = await UserDataBackup(other, clock: time.clock).import(json);
    expect(
      (summary.reviews, summary.wines, summary.tastings, summary.flags),
      (2, 1, 1, 1),
    );
    expect(await contents(other), before);
  });

  test('an import replaces everything, the review log included', () async {
    await study(db);
    final json = await backup.exportJson();
    final saved = await contents(db);

    time.advance(const Duration(days: 3));
    await study(db, seed: 2);
    expect(await contents(db), isNot(saved));

    await backup.import(json);
    expect(await contents(db), saved);
  });

  test('refuses a file that is not a backup, and changes nothing', () async {
    await study(db);
    final saved = await contents(db);
    for (final text in [
      'not json',
      '[]',
      '{"format": "something-else", "format_version": 1}',
      '{"format": "sommelier-user-data"}',
      '{"format": "sommelier-user-data", "format_version": 1, "tables": []}',
      '{"format": "sommelier-user-data", "format_version": 1, '
          '"tables": {"user_settings": [{"name": ["a list"]}]}}',
    ]) {
      await expectLater(
        backup.import(text),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            'This file is not a Sommelier backup.',
          ),
        ),
        reason: text,
      );
    }
    expect(await contents(db), saved);
  });

  test('refuses a backup from a newer app', () async {
    final newer = isA<BackupException>().having(
      (e) => e.message,
      'message',
      startsWith('This backup comes from a newer version'),
    );
    Map<String, Object?> document() => {
      'format': 'sommelier-user-data',
      'format_version': 1,
      'schema_version': db.schemaVersion,
      'tables': <String, Object?>{},
    };
    for (final change in <void Function(Map<String, Object?>)>[
      (d) => d['format_version'] = 2,
      (d) => d['schema_version'] = db.schemaVersion + 1,
      (d) => d['tables'] = {'wine_cellar_bins': <Object?>[]},
      (d) => d['tables'] = {
        'user_settings': [
          {
            'name': 'appearance',
            'value': 'dark',
            'updated_at': '2026-10-01T09:00:00.000Z',
            'synced_at': '2026-10-01T09:00:00.000Z',
          },
        ],
      },
    ]) {
      final d = document();
      change(d);
      await expectLater(backup.import(jsonEncode(d)), throwsA(newer));
    }
  });

  test(
    'refuses curriculum content this release lacks, and changes nothing',
    () async {
      await study(db);
      final saved = await contents(db);
      final document =
          jsonDecode(await backup.exportJson()) as Map<String, Object?>;
      final tables = document['tables']! as Map<String, Object?>;
      final flags = tables['question_flags']! as List<Object?>;
      (flags.single! as Map<String, Object?>)['knowledge_item_id'] =
          'ki_from_a_later_release';

      await expectLater(
        backup.import(jsonEncode(document)),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            startsWith('This backup refers to curriculum content'),
          ),
        ),
      );
      expect(await contents(db), saved, reason: 'the deletions rolled back');
    },
  );

  test('a reset clears the progress and keeps everything else', () async {
    await study(db);
    final saved = await contents(db);
    final states = db.select(db.reviewStates).watch().map((s) => s.length);
    final seen = expectLater(states, emitsInOrder([2, 0]));

    await backup.resetProgress();
    await seen;
    final after = await contents(db);
    for (final table in UserDataBackup.tables) {
      expect(
        after[table],
        UserDataBackup.progressTables.contains(table) ? isEmpty : saved[table],
        reason: table,
      );
    }

    // Studying starts again from nothing.
    final presenter = QuestionPresenter(db);
    final mcq = await presenter.present(
      'ki_chablis_grape',
      'qt_principal_grape_fwd_mcq',
      seed: 7,
    );
    final result = await ReviewService(
      db,
      clock: time.clock,
    ).answerMultipleChoice(mcq, mcq.answer);
    expect(result.before, isNull);
    expect(result.after.reps, 1);
  });

  test('erasing everything leaves a fresh install', () async {
    await study(db);
    await backup.eraseAll();
    final after = await contents(db);
    for (final table in UserDataBackup.tables) {
      expect(
        after[table],
        table == 'scheduler_configs' ? hasLength(1) : isEmpty,
        reason: table,
      );
    }
    expect((await LearnerSettings(db).current()).isOnboarded, isFalse);
  });
}
