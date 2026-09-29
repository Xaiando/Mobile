import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:image/image.dart' as image;
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/feedback/question_feedback.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
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
  late int stagedCleanupCalls;

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
    stagedCleanupCalls = 0;
    backup = UserDataBackup(
      db,
      clock: time.clock,
      clearRecoveredScans: () async {
        stagedCleanupCalls++;
      },
    );
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
    await JournalPhotoStore(db, clock: time.clock, random: Random(seed)).put(
      entryId: wine.id,
      kind: PhotoKind.label,
      bytes: Uint8List.fromList(
        image.encodePng(image.Image(width: 2, height: 2)),
      ),
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

  test('picked and saved file guards share the JSON byte ceiling', () {
    const limit = UserDataBackup.maxBackupFileBytes;
    UserDataBackup.checkPickedFileSize(limit);
    UserDataBackup.checkSavedFileSize(limit);
    expect(
      () => UserDataBackup.checkPickedFileSize(limit + 1),
      throwsA(
        isA<BackupException>().having(
          (error) => error.message,
          'message',
          contains('Nothing was imported'),
        ),
      ),
    );
    expect(
      () => UserDataBackup.checkSavedFileSize(limit + 1),
      throwsA(
        isA<BackupException>().having(
          (error) => error.message,
          'message',
          contains('will not leave data out'),
        ),
      ),
    );
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
    expect(document['format_version'], 2);
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
    expect(summary.photos, 1);
    expect(await contents(other), before);
  });

  test(
    'photo export includes the full byte-limit boundary and refuses more',
    () async {
      final journal = WineJournal(db, clock: time.clock, random: Random(1));
      final first = await journal.create(
        const JournalDraft(producerName: 'First capacity wine'),
      );
      final second = await journal.create(
        const JournalDraft(producerName: 'Second capacity wine'),
      );

      // SQL zeroblobs exercise the backup's byte budget without constructing
      // several enormous test images or duplicating their bytes in Dart.
      Future<void> addPhoto(
        int number,
        String entryId,
        String kind,
        int size,
      ) => db.customStatement(
        'INSERT INTO wine_journal_photos '
        '(id, wine_journal_entry_id, kind, mime_type, photo_bytes, created_at) '
        'VALUES (?, ?, ?, ?, zeroblob(?), ?)',
        [
          '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
          entryId,
          kind,
          'image/png',
          size,
          '2026-10-01T09:00:00.000Z',
        ],
      );

      const fullPhoto = JournalPhotoStore.maxBytes;
      await addPhoto(1, first.id, 'label', fullPhoto);
      await addPhoto(2, first.id, 'glass', fullPhoto);
      await addPhoto(3, second.id, 'label', fullPhoto);
      expect(fullPhoto * 3, UserDataBackup.maxExportPhotoBytes);

      final document = await backup.export();
      final tables = document['tables']! as Map<String, Object?>;
      final exported = tables['wine_journal_photos']! as List<Object?>;
      expect(exported, hasLength(3));
      for (final row in exported) {
        final photo = row! as Map<String, Object?>;
        expect(photo['photo_bytes'], isA<String>());
        expect((photo['photo_bytes']! as String).length, 11184812);
      }

      await addPhoto(4, second.id, 'glass', 1);
      Future<(int, int)> photoStats() async {
        final row = await db
            .customSelect(
              'SELECT COUNT(*) AS photo_count, '
              'SUM(length(photo_bytes)) AS total_bytes '
              'FROM wine_journal_photos',
            )
            .getSingle();
        return (row.read<int>('photo_count'), row.read<int>('total_bytes'));
      }

      final before = await photoStats();
      expect(before, (4, UserDataBackup.maxExportPhotoBytes + 1));
      final tooLarge = isA<BackupException>().having(
        (error) => error.message,
        'message',
        allOf(contains('24 MiB'), contains('will not leave photos out')),
      );
      await expectLater(backup.export(), throwsA(tooLarge));
      await expectLater(backup.exportJson(), throwsA(tooLarge));
      expect(
        await photoStats(),
        before,
        reason: 'export must not alter photos',
      );
    },
  );

  test('row capacity is symmetric and rejects before replacing data', () async {
    await study(db);
    final before = await contents(db);
    final rowCount = before.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    final json = await backup.exportJson();
    final document = jsonDecode(json) as Map<String, Object?>;
    final tables = document['tables']! as Map<String, Object?>;
    final wines = tables['wine_journal_entries']! as List<Object?>;
    (wines.single! as Map<String, Object?>)['producer_name'] = 'Wrong wine';
    final changed = jsonEncode(document);
    final tooFew = UserDataBackup(db, clock: time.clock, maxRows: rowCount - 1);
    await expectLater(
      tooFew.export(),
      throwsA(
        isA<BackupException>().having(
          (error) => error.message,
          'message',
          contains('${rowCount - 1}'),
        ),
      ),
    );
    await expectLater(
      tooFew.import(changed),
      throwsA(
        isA<BackupException>().having(
          (error) => error.message,
          'message',
          contains('Nothing was imported'),
        ),
      ),
    );
    expect(await contents(db), before);

    final atBoundary = UserDataBackup(db, clock: time.clock, maxRows: rowCount);
    expect((await atBoundary.export())['format'], UserDataBackup.format);
    final summary = await atBoundary.import(json);
    expect(summary.wines, 1);
    expect(await contents(db), before);
  });

  test('aggregate photo capacity is symmetric and preserves rows', () async {
    await study(db);
    final wine = (await db.select(db.wineJournalEntries).getSingle()).id;
    await JournalPhotoStore(db, clock: time.clock, random: Random(3)).put(
      entryId: wine,
      kind: PhotoKind.glass,
      bytes: Uint8List.fromList(
        image.encodePng(image.Image(width: 2, height: 2)),
      ),
    );
    final before = await contents(db);
    final photoBytes =
        (await db
                .customSelect(
                  'SELECT SUM(length(photo_bytes)) AS total_bytes '
                  'FROM wine_journal_photos',
                )
                .getSingle())
            .read<int>('total_bytes');
    final json = await backup.exportJson();
    final document = jsonDecode(json) as Map<String, Object?>;
    final tables = document['tables']! as Map<String, Object?>;
    final wines = tables['wine_journal_entries']! as List<Object?>;
    (wines.single! as Map<String, Object?>)['producer_name'] = 'Wrong wine';

    final tooFew = UserDataBackup(
      db,
      clock: time.clock,
      maxPhotoBytes: photoBytes - 1,
    );
    final photoLimit = isA<BackupException>().having(
      (error) => error.message,
      'message',
      contains('${photoBytes - 1} bytes'),
    );
    await expectLater(tooFew.export(), throwsA(photoLimit));
    await expectLater(tooFew.import(jsonEncode(document)), throwsA(photoLimit));
    expect(await contents(db), before);

    final atBoundary = UserDataBackup(
      db,
      clock: time.clock,
      maxPhotoBytes: photoBytes,
    );
    expect((await atBoundary.export())['format'], UserDataBackup.format);
    final summary = await atBoundary.import(json);
    expect(summary.photos, 2);
    expect(await contents(db), before);
  });

  test(
    'JSON byte capacity is symmetric and keeps an existing database',
    () async {
      await study(db);
      await db.customStatement(
        "UPDATE wine_journal_entries SET producer_name = 'Cuvée été'",
      );
      final before = await contents(db);
      final json = await backup.exportJson();
      final fileBytes = utf8.encode(json).length;
      expect(fileBytes, greaterThan(json.length));

      final tooFew = UserDataBackup(
        db,
        clock: time.clock,
        maxFileBytes: fileBytes - 1,
      );
      await expectLater(
        tooFew.exportJson(),
        throwsA(
          isA<BackupException>().having(
            (error) => error.message,
            'message',
            contains('will not leave data out'),
          ),
        ),
      );
      await expectLater(
        tooFew.import(json),
        throwsA(
          isA<BackupException>().having(
            (error) => error.message,
            'message',
            contains('Nothing was imported'),
          ),
        ),
      );
      expect(await contents(db), before);

      final atBoundary = UserDataBackup(
        db,
        clock: time.clock,
        maxFileBytes: fileBytes,
      );
      expect(await atBoundary.exportJson(), json);
      await atBoundary.import(json);
      expect(await contents(db), before);
    },
  );

  test('a format-1 backup keeps its legacy photo reference', () async {
    await study(db);
    await db.customStatement(
      "UPDATE wine_journal_entries SET photo_ref = 'legacy-opaque'",
    );
    final document =
        jsonDecode(await backup.exportJson()) as Map<String, Object?>;
    document['format_version'] = 1;
    document['schema_version'] = 4;
    final tables = document['tables']! as Map<String, Object?>;
    tables.remove('wine_journal_photos');

    final other = await freshDatabase();
    addTearDown(other.close);
    final summary = await UserDataBackup(
      other,
      clock: time.clock,
    ).import(jsonEncode(document));
    expect(summary.photos, 0);
    expect(
      (await other.select(other.wineJournalEntries).getSingle()).photoRef,
      'legacy-opaque',
    );
    expect(await other.select(other.wineJournalPhotos).get(), isEmpty);
  });

  test('missing or null table arrays cannot erase existing data', () async {
    await study(db);
    final before = await contents(db);
    final exported = await backup.exportJson();
    final notABackup = isA<BackupException>().having(
      (error) => error.message,
      'message',
      'This file is not a Sommelier backup.',
    );

    for (final version in [1, 2]) {
      for (final table in [
        'review_events',
        if (version == 2) 'wine_journal_photos',
      ]) {
        expect(before[table], isNotEmpty, reason: '$table has data to lose');
        for (final missing in [true, false]) {
          final document = jsonDecode(exported) as Map<String, Object?>;
          document['format_version'] = version;
          final tables = document['tables']! as Map<String, Object?>;
          if (version == 1) {
            document['schema_version'] = 4;
            tables.remove('wine_journal_photos');
          }
          if (missing) {
            tables.remove(table);
          } else {
            tables[table] = null;
          }
          final caseName =
              'format $version $table '
              '${missing ? 'missing' : 'null'}';
          await expectLater(
            backup.import(jsonEncode(document)),
            throwsA(notABackup),
            reason: caseName,
          );
          expect(await contents(db), before, reason: caseName);
        }
      }
    }
  });

  test('a corrupt photo refuses import before replacing any rows', () async {
    await study(db);
    final before = await contents(db);
    final document =
        jsonDecode(await backup.exportJson()) as Map<String, Object?>;
    final tables = document['tables']! as Map<String, Object?>;
    final photos = tables['wine_journal_photos']! as List<Object?>;
    final photo = photos.single! as Map<String, Object?>;
    for (final bad in [
      '%%%not-base64',
      base64Encode([1, 2, 3]),
    ]) {
      photo['photo_bytes'] = bad;
      await expectLater(
        backup.import(jsonEncode(document)),
        throwsA(isA<BackupException>()),
      );
      expect(await contents(db), before);
    }
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
      (d) => d['format_version'] = 3,
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
    expect(stagedCleanupCalls, 0);
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
    backup = UserDataBackup(
      db,
      clock: time.clock,
      clearRecoveredScans: () async {
        // Pending photo cleanup must follow the completed database rewrite.
        final saved = await contents(db);
        for (final table in UserDataBackup.tables) {
          expect(
            saved[table],
            table == 'scheduler_configs' || table == 'user_settings'
                ? hasLength(1)
                : isEmpty,
            reason: table,
          );
        }
        expect(
          saved['user_settings']!.single['name'],
          UserDataBackup.recoveredScanErasePendingSetting,
        );
        stagedCleanupCalls++;
      },
    );
    await backup.eraseAll();
    expect(stagedCleanupCalls, 1);
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

  test(
    'interrupted scan erase persists intent and finishes after restart',
    () async {
      await study(db);
      final preEraseBackup = await backup.exportJson();
      var discardCalls = 0;
      backup = UserDataBackup(
        db,
        clock: time.clock,
        discardLostPickerData: () async => discardCalls++,
        clearRecoveredScans: () async => throw StateError('disk unavailable'),
      );
      await expectLater(backup.eraseAll(), throwsA(isA<BackupException>()));
      expect(discardCalls, 1);
      expect((await LearnerSettings(db).current()).isOnboarded, isFalse);
      final exported = await backup.export();
      expect(
        (exported['tables']! as Map<String, Object?>)['user_settings'],
        isEmpty,
      );
      await expectLater(
        backup.import(preEraseBackup),
        throwsA(isA<BackupException>()),
      );
      expect((await LearnerSettings(db).current()).isOnboarded, isFalse);
      expect(
        await (db.select(db.userSettings)..where(
              (row) => row.name.equals(
                UserDataBackup.recoveredScanErasePendingSetting,
              ),
            ))
            .getSingleOrNull(),
        isNotNull,
      );

      final restarted = UserDataBackup(
        db,
        clock: time.clock,
        discardLostPickerData: () async => discardCalls++,
        clearRecoveredScans: () async {
          // Deleting files is attempted while the durable erase marker exists.
          expect(
            await (db.select(db.userSettings)..where(
                  (row) => row.name.equals(
                    UserDataBackup.recoveredScanErasePendingSetting,
                  ),
                ))
                .getSingleOrNull(),
            isNotNull,
          );
          stagedCleanupCalls++;
        },
      );
      await restarted.resumePendingRecoveredScanErase();
      await restarted.resumePendingRecoveredScanErase();
      expect(discardCalls, 3);
      expect(stagedCleanupCalls, 1);
      expect(
        await (db.select(db.userSettings)..where(
              (row) => row.name.equals(
                UserDataBackup.recoveredScanErasePendingSetting,
              ),
            ))
            .getSingleOrNull(),
        isNull,
      );
    },
  );

  test('failed picker discard leaves erase marker for retry', () async {
    await study(db);
    backup = UserDataBackup(
      db,
      clock: time.clock,
      discardLostPickerData: () async => throw StateError('picker unavailable'),
      clearRecoveredScans: () async => stagedCleanupCalls++,
    );
    await expectLater(backup.eraseAll(), throwsA(isA<BackupException>()));
    expect(stagedCleanupCalls, 0);
    expect(
      await (db.select(db.userSettings)..where(
            (row) => row.name.equals(
              UserDataBackup.recoveredScanErasePendingSetting,
            ),
          ))
          .getSingleOrNull(),
      isNotNull,
    );
  });
}
