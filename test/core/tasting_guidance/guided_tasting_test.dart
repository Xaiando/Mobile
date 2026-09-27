import 'dart:convert';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, TransactionExecutor;
import 'package:drift/native.dart' show NativeDatabase, SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
import 'guided_tasting_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late GuidedTastingRepository repository;
  late _TransactionCounter transactions;
  setUp(() async {
    transactions = _TransactionCounter();
    db = AppDatabase(NativeDatabase.memory().interceptWith(transactions));
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L1');
    repository = GuidedTastingRepository(
      db,
      bank: guidedTastingFixtureBank(),
      clock: time.clock,
    );
  });
  tearDown(() => db.close());

  test('malformed guided history remains in backups beside readable sessions', () async {
    final valid = await repository.start(1);
    final bad = <String, String>{
      '${GuidedTastingRepository.recordPrefix}12345678_1234_4234_8234_123456789ab1':
          '{invalid',
      '${GuidedTastingRepository.recordPrefix}12345678_1234_4234_8234_123456789ab2':
          '[]',
      '${GuidedTastingRepository.recordPrefix}12345678_1234_4234_8234_123456789abc':
          jsonEncode(valid.toJson()),
    };
    for (final entry in bad.entries) {
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: entry.key,
              value: entry.value,
              updatedAt: time.now,
            ),
          );
    }
    final recovered = await repository.historyWithDiagnostics();
    expect(recovered.entries.single.sessionId, valid.sessionId);
    expect(recovered.unreadableCount, 3);
    expect((await repository.history()).single.sessionId, valid.sessionId);
    final backup = await UserDataBackup(db, clock: time.clock).exportJson();
    await UserDataBackup(db, clock: time.clock).eraseAll();
    await UserDataBackup(db, clock: time.clock).import(backup);
    expect((await repository.historyWithDiagnostics()).unreadableCount, 3);
    expect((await repository.history()).single.sessionId, valid.sessionId);
    final raw = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    for (final entry in bad.entries) {
      expect(raw[entry.key], entry.value);
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  Future<GuidedTastingRecord> complete(GuidedTastingRecord record) async {
    await repository.choose(record.sessionId, 'sweetness', {'dry'});
    for (final prompt in record.level.evidencePrompts) {
      await repository.evidence(
        record.sessionId,
        prompt.id,
        'Observed evidence supports this description.',
      );
    }
    return repository.finish(record.sessionId);
  }

  test('guided writes, finishing and legacy reconciliation each use one transaction', () async {
    final record = await repository.start(1);
    transactions.reset();
    await repository.choose(record.sessionId, 'sweetness', {'dry'});
    expect(transactions.begun, 1);
    expect(transactions.committed, 1);
    expect(transactions.rolledBack, 0);

    transactions.reset();
    await repository.evidence(
      record.sessionId,
      'description',
      'Dry palate evidence.',
    );
    expect(transactions.begun, 1);
    expect(transactions.committed, 1);
    expect(transactions.rolledBack, 0);

    transactions.reset();
    final finished = await repository.finish(record.sessionId);
    expect(transactions.begun, 1);
    expect(transactions.committed, 1);
    expect(transactions.rolledBack, 0);
    expect(finished.isFinished, isTrue);

    await repository.practice.choose(record.sessionId, 'aromas', {'citrus'});
    transactions.reset();
    final reopened = (await repository.current())!;
    expect(transactions.begun, 1);
    expect(transactions.committed, 1);
    expect(transactions.rolledBack, 0);
    expect(reopened.isFinished, isFalse);
    expect(reopened.completedObservations, isEmpty);
    expect(reopened.evidence['description'], 'Dry palate evidence.');
  });

  test('joined guided and observation writes reject missing or foreign transactions', () async {
    final record = await repository.start(1);
    final settingsBefore = await db.select(db.userSettings).get();
    transactions.reset();
    await expectLater(
      repository.chooseInTransaction(record.sessionId, 'sweetness', {'dry'}),
      throwsStateError,
    );
    await expectLater(
      repository.evidenceInTransaction(
        record.sessionId,
        'description',
        'Outside transaction.',
      ),
      throwsStateError,
    );
    await expectLater(
      repository.practice.chooseInTransaction(record.sessionId, 'sweetness', {
        'dry',
      }),
      throwsStateError,
    );
    final other = openTestDatabase();
    try {
      await expectLater(
        other.transaction(
          () => repository.chooseInTransaction(record.sessionId, 'sweetness', {
            'dry',
          }),
        ),
        throwsStateError,
      );
      await expectLater(
        other.transaction(
          () => repository.evidenceInTransaction(
            record.sessionId,
            'description',
            'Foreign transaction.',
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        other.transaction(
          () => repository.practice.chooseInTransaction(
            record.sessionId,
            'sweetness',
            {'dry'},
          ),
        ),
        throwsStateError,
      );
    } finally {
      await other.close();
    }
    expect(transactions.begun, 0);
    expect(await db.select(db.tastingDescriptors).get(), isEmpty);
    expect(await db.select(db.userSettings).get(), settingsBefore);
  });

  test('failed guided observation replacement retains the previous value atomically', () async {
    final record = await repository.start(1);
    await repository.choose(record.sessionId, 'sweetness', {'dry'});
    transactions.reset();
    await expectLater(
      repository.choose(record.sessionId, 'sweetness', {'unknown'}),
      throwsA(isA<SqliteException>()),
    );
    expect(transactions.begun, 1);
    expect(transactions.committed, 0);
    expect(transactions.rolledBack, 1);
    expect(await repository.observations(record), {
      'sweetness': {'dry'},
    });
  });

  test(
    'failed guided completion snapshot rolls back legacy completion',
    () async {
      final record = await repository.start(1);
      await repository.choose(record.sessionId, 'sweetness', {'dry'});
      await repository.evidence(
        record.sessionId,
        'description',
        'Observed evidence.',
      );
      final settingsBefore = await db.select(db.userSettings).get();
      await db.customStatement('''CREATE TEMP TRIGGER reject_guided_completion
      BEFORE UPDATE ON user_settings
      WHEN NEW.name LIKE 'guided_tasting_record_v1_%'
      BEGIN SELECT RAISE(ABORT, 'fixture guided snapshot failure'); END;''');
      try {
        transactions.reset();
        await expectLater(
          repository.finish(record.sessionId),
          throwsA(isA<SqliteException>()),
        );
        expect(transactions.begun, 1);
        expect(transactions.committed, 0);
        expect(transactions.rolledBack, 1);
        expect(
          (await repository.session(record.sessionId)).completedAt,
          isNull,
        );
        expect(await db.select(db.userSettings).get(), settingsBefore);
      } finally {
        await db.customStatement('DROP TRIGGER reject_guided_completion');
      }
      expect((await repository.read(record.sessionId)).isFinished, isFalse);
    },
  );

  test('imported unknown calibration vocabulary is recoverable without changing raw snapshots', () async {
    final corrupt = <String, String>{};
    for (final invalidAttribute in [true, false]) {
      final saved = await complete(
        await repository.start(1, caseId: 'case_l1'),
      );
      await repository.leaveCurrent();
      final row = saved.toJson();
      final reference =
          (row['calibration']['referenceObservations'] as List).first
              as Map<String, dynamic>;
      if (invalidAttribute) {
        reference['attributeKey'] = 'missing_attribute';
      } else {
        reference['valueKeys'] = ['missing_value'];
      }
      final key =
          '${GuidedTastingRepository.recordPrefix}${saved.sessionId.replaceAll('-', '_')}';
      corrupt[key] = jsonEncode(row);
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(name: key, value: corrupt[key]!, updatedAt: time.now),
          );
      await expectLater(
        repository.read(saved.sessionId),
        throwsFormatException,
      );
    }
    final valid = await complete(await repository.start(1, caseId: 'case_l1'));
    // Both dry and off-dry are an acceptable training reference range, even
    // though a learner's sweetness observation chooses one value.
    expect(valid.calibration!.referenceObservations.single.valueKeys, [
      'dry',
      'off_dry',
    ]);
    final backup = UserDataBackup(db, clock: time.clock);
    final exported = await backup.exportJson();
    await backup.eraseAll();
    await backup.import(exported);
    final recovered = await repository.historyWithDiagnostics();
    expect(recovered.unreadableCount, 2);
    expect(recovered.entries.single.toJson(), valid.toJson());
    final raw = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    for (final entry in corrupt.entries) {
      expect(raw[entry.key], entry.value);
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test('retired calibration links do not make historical feedback unreadable', () async {
    final saved = await complete(await repository.start(1, caseId: 'case_l1'));
    final row = saved.toJson();
    row['calibration']['itemIds'] = ['ki_retired_calibration'];
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name:
                '${GuidedTastingRepository.recordPrefix}${saved.sessionId.replaceAll('-', '_')}',
            value: jsonEncode(row),
            updatedAt: time.now,
          ),
        );
    final recovered = await repository.historyWithDiagnostics();
    expect(recovered.unreadableCount, 0);
    expect(recovered.entries.single.isFinished, isTrue);
    expect(recovered.entries.single.calibration!.itemIds, [
      'ki_retired_calibration',
    ]);
    expect((await repository.read(saved.sessionId)).toJson(), row);
  });

  test(
    'guided history propagates storage failures while reconciling legacy edits',
    () async {
      final saved = await complete(await repository.start(1));
      await TastingPractice(
        db,
        clock: time.clock,
      ).choose(saved.sessionId, 'sweetness', {'off_dry'});
      await db.customStatement('''CREATE TEMP TRIGGER reject_guided_history
      BEFORE UPDATE ON user_settings
      WHEN NEW.name LIKE 'guided_tasting_record_v1_%'
      BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END;''');
      await expectLater(
        repository.historyWithDiagnostics(),
        throwsA(isA<SqliteException>()),
      );
      await db.customStatement('DROP TRIGGER reject_guided_history');
      final recovered = await repository.historyWithDiagnostics();
      expect(recovered.unreadableCount, 0);
      expect(recovered.entries.single.isFinished, isFalse);
    },
  );

  test(
    'physical observation persists in existing tables with safe settings keys',
    () async {
      final record = await repository.start(1);
      expect(record.calibration, isNull);
      expect((await repository.session(record.sessionId)).isBlind, isTrue);
      await repository.choose(record.sessionId, 'sweetness', {'dry'});
      await repository.evidence(
        record.sessionId,
        'description',
        'Dry palate supports a dry description.',
      );
      final settings = await db.select(db.userSettings).get();
      expect(settings.every((row) => !row.name.contains('-')), isTrue);
      final restarted = GuidedTastingRepository(
        db,
        bank: guidedTastingFixtureBank(),
        clock: time.clock,
      );
      expect(
        (await restarted.current())!.evidence['description'],
        'Dry palate supports a dry description.',
      );
      expect(await restarted.observations(record), {
        'sweetness': {'dry'},
      });
      expect(await db.select(db.tastingDescriptors).get(), hasLength(1));
    },
  );

  test(
    'completion requires both observations and nonblank written evidence',
    () async {
      final record = await repository.start(1);
      await expectLater(repository.finish(record.sessionId), throwsStateError);
      await repository.evidence(record.sessionId, 'description', '   ');
      await repository.choose(record.sessionId, 'sweetness', {'dry'});
      await expectLater(repository.finish(record.sessionId), throwsStateError);
      await repository.evidence(
        record.sessionId,
        'description',
        'Observed evidence.',
      );
      final finished = await repository.finish(record.sessionId);
      expect(finished.isFinished, isTrue);
      await expectLater(
        repository.evidence(
          record.sessionId,
          'description',
          'Changed after completion',
        ),
        throwsStateError,
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(await db.select(db.reviewStates).get(), isEmpty);
    },
  );

  test(
    'repeated concurrent finishes preserve one snapshot and no exam pass',
    () async {
      final draft = await repository.start(1);
      await repository.choose(draft.sessionId, 'sweetness', {'dry'});
      await repository.evidence(
        draft.sessionId,
        'description',
        'Persisted evidence.',
      );
      final other = GuidedTastingRepository(
        db,
        bank: guidedTastingFixtureBank(),
        clock: time.clock,
      );
      final results = await Future.wait([
        repository.finish(draft.sessionId),
        other.finish(draft.sessionId),
      ]);
      expect(results.first.toJson(), results.last.toJson());
      time.advance(const Duration(hours: 1));
      expect(
        (await repository.finish(draft.sessionId)).toJson(),
        results.first.toJson(),
      );
      expect(
        (await db.select(db.userSettings).get()).any(
          (row) => row.name.startsWith('exam_pass_'),
        ),
        isFalse,
      );
    },
  );

  test(
    'calibration snapshots survive bank changes and backup restore',
    () async {
      var record = await repository.start(1, caseId: 'case_l1');
      await expectLater(
        repository.selfAssess(record.sessionId, {'evidence'}),
        throwsStateError,
      );
      record = await complete(record);
      record = await repository.selfAssess(record.sessionId, {'evidence'});
      final backup = await UserDataBackup(db, clock: time.clock).exportJson();
      await UserDataBackup(db, clock: time.clock).eraseAll();
      await UserDataBackup(db, clock: time.clock).import(backup);
      final changed = guidedTastingFixtureMap()..['version'] = 'fixture.2';
      for (final calibration in changed['cases'] as List) {
        calibration['feedback'] = 'Changed feedback';
      }
      final newer = GuidedTastingRepository(
        db,
        bank: GuidedTastingBank.fromJson(jsonEncode(changed)),
        clock: time.clock,
      );
      expect((await newer.current())!.toJson(), record.toJson());
      expect(
        (await newer.current())!.calibration!.feedback,
        isNot('Changed feedback'),
      );
    },
  );

  test(
    'legacy optional observation changes reopen stale guidance completion',
    () async {
      var record = await complete(await repository.start(1, caseId: 'case_l1'));
      record = await repository.selfAssess(record.sessionId, {'evidence'});
      await TastingPractice(
        db,
        clock: time.clock,
      ).choose(record.sessionId, 'aromas', {'citrus'});
      final reopened = (await repository.current())!;
      expect(reopened.isFinished, isFalse);
      expect(reopened.selfAssessment, isEmpty);
      expect(reopened.completedObservations, isEmpty);
      expect(reopened.evidence, record.evidence);
      expect(
        (await repository.finish(record.sessionId))
            .completedObservations['aromas'],
        {'citrus'},
      );
    },
  );

  test('Level 3 requires quality and ageing evidence without grading wine identity', () async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final record = await repository.start(3);
    await repository.choose(record.sessionId, 'sweetness', {'off_dry'});
    await repository.evidence(
      record.sessionId,
      'quality',
      'Evidence supports a quality judgment.',
    );
    await expectLater(repository.finish(record.sessionId), throwsStateError);
    await repository.evidence(
      record.sessionId,
      'ageing',
      'Evidence supports an ageing judgment.',
    );
    final finished = await repository.finish(record.sessionId);
    expect(finished.isFinished, isTrue);
    expect(finished.calibration, isNull);
    await expectLater(
      repository.selfAssess(record.sessionId, {'evidence'}),
      throwsStateError,
    );
  });

  test(
    'case membership, expired links and invalid grid references fail safely',
    () async {
      await expectLater(
        repository.start(2, caseId: 'case_l2'),
        throwsStateError,
      );
      final changed = guidedTastingFixtureMap();
      changed['cases'][0]['referenceObservations'][0]['valueKeys'] = [
        'unknown',
      ];
      final broken = GuidedTastingRepository(
        db,
        bank: GuidedTastingBank.fromJson(jsonEncode(changed)),
        clock: time.clock,
      );
      await expectLater(
        broken.start(1, caseId: 'case_l1'),
        throwsFormatException,
      );
      expect(await db.select(db.tastingSessions).get(), isEmpty);
      await db.writeCurriculum(
        () => runSql(db, [
          "UPDATE knowledge_relations SET valid_until='2026-01-01' WHERE subject_id='n_geo_chablis' AND relation_type='PERMITS_PRINCIPAL_GRAPE'",
        ]),
      );
      await expectLater(
        repository.start(1, caseId: 'case_l1'),
        throwsStateError,
      );
      expect(await repository.current(), isNull);
    },
  );

  test('saved identity and UTC spelling reject corrupt guided records', () async {
    final record = await repository.start(1);
    final finished = await complete(record);
    for (final row in [
      {
        ...finished.toJson(),
        'sessionId': '00000000-0000-4000-8000-000000000000',
      },
      {...finished.toJson(), 'completedAt': '2026-09-27T10:00:00'},
      {...finished.toJson(), 'completedAt': '2026-02-30T00:00:00.000Z'},
      {
        ...finished.toJson(),
        'evidence': {'description': ' '},
      },
    ]) {
      final key =
          '${GuidedTastingRepository.recordPrefix}${record.sessionId.replaceAll('-', '_')}';
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: key,
              value: jsonEncode(row),
              updatedAt: time.clock.now(),
            ),
          );
      await expectLater(repository.current(), throwsFormatException);
    }
  });

  test(
    'resuming saved draft restores selection without dropping another draft',
    () async {
      final first = await repository.start(1);
      await repository.leaveCurrent();
      final second = await repository.start(1);
      await expectLater(repository.resume(first.sessionId), throwsStateError);
      expect((await repository.current())!.sessionId, second.sessionId);
      await repository.leaveCurrent();
      await repository.resume(first.sessionId);
      expect((await repository.current())!.sessionId, first.sessionId);
      expect(await repository.history(), hasLength(2));
    },
  );

  test('leaving selection keeps draft history and all legacy grids', () async {
    final record = await repository.start(1);
    await repository.evidence(
      record.sessionId,
      'description',
      'Saved unfinished evidence.',
    );
    await repository.leaveCurrent();
    expect(await repository.current(), isNull);
    expect(await repository.history(), hasLength(1));
    expect((await repository.read(record.sessionId)).evidence, isNotEmpty);
    final grids = await TastingPractice(db).grids();
    expect(
      grids.map((g) => g.id),
      containsAll(['tg_wset_sat_l3', 'tg_cms_dtm_certified']),
    );
    await repository.start(1);
    expect(await repository.history(), hasLength(2));
  });
}

class _TransactionCounter extends QueryInterceptor {
  int begun = 0;
  int committed = 0;
  int rolledBack = 0;

  void reset() {
    begun = 0;
    committed = 0;
    rolledBack = 0;
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    begun++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await super.commitTransaction(inner);
    committed++;
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await super.rollbackTransaction(inner);
    rolledBack++;
  }
}
