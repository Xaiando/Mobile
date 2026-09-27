import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
import 'rehearsal_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late RehearsalRepository repository;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "UPDATE certifications SET is_selectable=1 WHERE id IN ('WSET_L1','WSET_L2')",
        "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L1','ki_chablis_grape','core',1,NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L1');
    repository = RehearsalRepository(
      db,
      bank: rehearsalFixtureBank(),
      clock: time.clock,
      random: Random(1),
    );
  });
  tearDown(() => db.close());

  test(
    'exact presets sample unique current facts and retain a deadline',
    () async {
      for (var level = 1; level <= 3; level++) {
        await LearnerProfiles(
          db,
          clock: time.clock,
        ).selectTrack('WSET_L$level');
        final attempt = await repository.start(level);
        expect(attempt.mcqs.length, level == 1 ? 30 : 50);
        expect(
          attempt.mcqs.map((q) => q.id).toSet().length,
          attempt.mcqs.length,
        );
        expect(attempt.written.length, level == 3 ? 4 : 0);
        expect(
          attempt.deadline.difference(attempt.startedAt).inSeconds,
          [2700, 3600, 7200][level - 1],
        );
        await repository.finish(attempt.id);
      }
      expect(await repository.history(), hasLength(3));
    },
  );

  test(
    'blueprint sampling respects every bucket without duplicate questions',
    () async {
      repository = RehearsalRepository(
        db,
        bank: rehearsalFixtureBank(blueprint: true),
        clock: time.clock,
        random: Random(4),
      );
      final attempt = await repository.start(1);
      final counts = <String, int>{};
      for (final question in attempt.mcqs) {
        counts.update(
          question.blueprintByLevel['1']!,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      expect(counts, {'process': 6, 'styles': 18, 'service': 6});
      expect(attempt.mcqs.map((q) => q.id).toSet(), hasLength(30));
    },
  );

  test(
    'an undersupplied bucket fails rather than shortening the preset',
    () async {
      final bank = rehearsalFixtureMap(blueprint: true);
      (bank['mcqs'] as List).removeWhere(
        (q) => q['blueprintByLevel']['1'] == 'service',
      );
      repository = RehearsalRepository(
        db,
        bank: RehearsalBank.fromJson(jsonEncode(bank)),
        clock: time.clock,
      );
      await expectLater(repository.start(1), throwsStateError);
      expect(await repository.current(), isNull);
    },
  );

  test(
    'active track, expired links and unmapped links gate sampling',
    () async {
      await expectLater(repository.start(2), throwsStateError);
      await db.writeCurriculum(
        () => runSql(db, [
          "UPDATE knowledge_relations SET valid_until='2026-01-01' WHERE subject_id='n_geo_chablis' AND relation_type='PERMITS_PRINCIPAL_GRAPE'",
        ]),
      );
      await expectLater(repository.start(1), throwsStateError);
      final bank = rehearsalFixtureMap();
      for (final question in bank['mcqs'] as List) {
        question['itemIds'] = ['ki_barolo_min_ageing'];
      }
      repository = RehearsalRepository(
        db,
        bank: RehearsalBank.fromJson(jsonEncode(bank)),
        clock: time.clock,
      );
      await expectLater(repository.start(1), throwsStateError);
    },
  );

  test('restart preserves answers and timer and expiry freezes them', () async {
    final attempt = await repository.start(1);
    final question = attempt.mcqs.first;
    await repository.answerMcq(
      attempt.id,
      question.id,
      question.correctOptionId,
    );
    time.advance(const Duration(minutes: 10));
    final restarted = RehearsalRepository(
      db,
      bank: rehearsalFixtureBank(),
      clock: time.clock,
    );
    var saved = (await restarted.current())!;
    expect(saved.answers[question.id], question.correctOptionId);
    expect(saved.remaining(time.now), const Duration(minutes: 35));
    await expectLater(restarted.start(1), throwsStateError);
    time.advance(const Duration(minutes: 40));
    saved = (await restarted.current())!;
    expect(saved.finishReason, 'expired');
    expect(saved.completedAt, attempt.deadline);
    expect(saved.mcqCorrect, 1);
    await expectLater(
      restarted.answerMcq(attempt.id, question.id, 'b'),
      throwsStateError,
    );
  });

  test(
    'simultaneous finalizations and repeated finish have one stable result',
    () async {
      final attempt = await repository.start(1);
      final other = RehearsalRepository(
        db,
        bank: rehearsalFixtureBank(),
        clock: time.clock,
      );
      final results = await Future.wait([
        repository.finish(attempt.id),
        other.finish(attempt.id),
      ]);
      expect(results[0].toJson(), results[1].toJson());
      time.advance(const Duration(days: 1));
      expect((await other.finish(attempt.id)).toJson(), results[0].toJson());
      expect(await repository.history(), hasLength(1));
      expect(await db.select(db.reviewStates).get(), isEmpty);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(
        await (db.select(
          db.userSettings,
        )..where((s) => s.name.like('exam_pass_%'))).get(),
        isEmpty,
      );
    },
  );

  test('a rejected late MCQ or prose write commits expiry before the error', () async {
    for (final level in [1, 3]) {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L$level');
      final attempt = await repository.start(level);
      if (level == 1) {
        await repository.answerMcq(
          attempt.id,
          attempt.mcqs.first.id,
          attempt.mcqs.first.correctOptionId,
        );
      } else {
        await repository.answerWritten(
          attempt.id,
          attempt.written.first.id,
          'Saved before expiry.',
        );
      }
      time.advance(
        attempt.deadline.difference(time.now) + const Duration(seconds: 1),
      );
      await expectLater(
        level == 1
            ? repository.answerMcq(attempt.id, attempt.mcqs.first.id, 'b')
            : repository.answerWritten(
                attempt.id,
                attempt.written.first.id,
                'Too late.',
              ),
        throwsStateError,
      );
      // Read the raw setting before any current()/finish() can repair it.
      final name =
          '${RehearsalRepository.attemptPrefix}${attempt.id.replaceAll('-', '_')}';
      final setting = await (db.select(
        db.userSettings,
      )..where((s) => s.name.equals(name))).getSingle();
      final saved = RehearsalAttempt.fromJson(
        jsonDecode(setting.value) as Map<String, dynamic>,
      );
      expect(saved.finishReason, 'expired');
      expect(saved.completedAt, attempt.deadline);
      if (level == 1) {
        expect(
          saved.answers[attempt.mcqs.first.id],
          attempt.mcqs.first.correctOptionId,
        );
      } else {
        expect(saved.prose[attempt.written.first.id], 'Saved before expiry.');
      }
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test(
    'saved snapshots survive a changed bank and backup round trip',
    () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      var attempt = await repository.start(3);
      final written = attempt.written.first;
      attempt = await repository.answerWritten(
        attempt.id,
        written.id,
        'My original explanation.',
      );
      await expectLater(
        repository.selfAssess(attempt.id, written.id, {
          written.criteria.first.id,
        }),
        throwsStateError,
      );
      attempt = await repository.finish(attempt.id);
      attempt = await repository.selfAssess(attempt.id, written.id, {
        written.criteria.first.id,
      });
      final export = await UserDataBackup(db, clock: time.clock).exportJson();
      await UserDataBackup(db, clock: time.clock).eraseAll();
      await UserDataBackup(db, clock: time.clock).import(export);
      final changed = rehearsalFixtureMap()..['version'] = 'test.2';
      for (final q in changed['mcqs'] as List) {
        q['prompt'] = 'Changed bank prompt';
        q['correctOptionId'] = 'b';
      }
      for (final q in changed['written'] as List) {
        q['criteria'][0]['text'] = 'Changed criterion';
      }
      final newer = RehearsalRepository(
        db,
        bank: RehearsalBank.fromJson(jsonEncode(changed)),
        clock: time.clock,
      );
      expect((await newer.current())!.toJson(), attempt.toJson());
      expect(
        (await newer.current())!.prose[written.id],
        'My original explanation.',
      );
    },
  );

  test(
    'invalid option, criterion and question IDs never alter the draft',
    () async {
      final attempt = await repository.start(1);
      await expectLater(
        repository.answerMcq(
          attempt.id,
          attempt.mcqs.first.id,
          'not-an-option',
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.answerMcq(attempt.id, 'not-a-question', 'a'),
        throwsFormatException,
      );
      expect((await repository.current())!.answers, isEmpty);
      await repository.finish(attempt.id);
      await repository.discardCurrent();
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final writtenAttempt = await repository.start(3);
      await repository.finish(writtenAttempt.id);
      await expectLater(
        repository.selfAssess(
          writtenAttempt.id,
          writtenAttempt.written.first.id,
          {'missing'},
        ),
        throwsFormatException,
      );
    },
  );

  test('abandon retains history while allowing a new attempt', () async {
    final original = await repository.start(1);
    await repository.answerMcq(original.id, original.mcqs.first.id, 'a');
    await repository.discardCurrent();
    expect(await repository.current(), isNull);
    final history = await repository.history();
    expect(history.single.finishReason, 'abandoned');
    expect(history.single.answers, isNotEmpty);
    final next = await repository.start(1);
    expect(next.id, isNot(original.id));
    expect(await repository.history(), hasLength(2));
  });

  test('historical draft selection survives restart and backup with its original timer', () async {
    final attempt = await repository.start(1);
    await repository.answerMcq(
      attempt.id,
      attempt.mcqs.first.id,
      attempt.mcqs.first.correctOptionId,
    );
    await repository.resetCurrentPointer();
    time.advance(const Duration(minutes: 10));
    final resumed = await repository.resume(attempt.id);
    expect(resumed.deadline, attempt.deadline);
    expect(resumed.remaining(time.now), const Duration(minutes: 35));
    final backup = await UserDataBackup(db, clock: time.clock).exportJson();
    await UserDataBackup(db, clock: time.clock).eraseAll();
    await UserDataBackup(db, clock: time.clock).import(backup);
    final restarted = RehearsalRepository(
      db,
      bank: rehearsalFixtureBank(),
      clock: time.clock,
    );
    expect((await restarted.current())!.toJson(), resumed.toJson());
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test(
    'a historical draft cannot hide or end another selected draft',
    () async {
      final old = await repository.start(1);
      await repository.resetCurrentPointer();
      final current = await repository.start(1);
      await expectLater(repository.resume(old.id), throwsStateError);
      await expectLater(
        repository.discardCurrent(expectedId: old.id),
        throwsStateError,
      );
      expect((await repository.current())!.id, current.id);
      expect((await repository.read(old.id)).isFinished, isFalse);
      expect((await repository.read(current.id)).isFinished, isFalse);
      await repository.discardCurrent(expectedId: current.id);
      expect((await repository.resume(old.id)).id, old.id);
      expect((await repository.current())!.id, old.id);
    },
  );

  test(
    'leaving finished history preserves and returns another selected draft',
    () async {
      final old = await repository.start(1);
      await repository.finish(old.id);
      final current = await repository.start(1);
      expect((await repository.resume(old.id)).isFinished, isTrue);
      expect((await repository.current())!.id, current.id);
      final returned = (await repository.leaveFinished(old.id))!;
      expect(returned.id, current.id);
      expect(returned.isFinished, isFalse);
      await expectLater(repository.leaveFinished(current.id), throwsStateError);
      expect((await repository.current())!.id, current.id);
      await repository.finish(current.id);
      expect(await repository.leaveFinished(current.id), isNull);
      expect(await repository.current(), isNull);
    },
  );

  test('reading or opening expired history commits its deadline without restarting it', () async {
    final attempt = await repository.start(1);
    await repository.resetCurrentPointer();
    time.advance(const Duration(minutes: 46));
    final saved = await repository.resume(attempt.id);
    expect(saved.finishReason, 'expired');
    expect(saved.completedAt, attempt.deadline);
    expect(saved.deadline, attempt.deadline);
    expect(await repository.current(), isNull);
    final key =
        '${RehearsalRepository.attemptPrefix}${attempt.id.replaceAll('-', '_')}';
    final raw = await (db.select(
      db.userSettings,
    )..where((s) => s.name.equals(key))).getSingle();
    expect(
      RehearsalAttempt.fromJson(jsonDecode(raw.value) as Map<String, dynamic>)
          .finishReason,
      'expired',
    );
    expect((await repository.read(attempt.id)).toJson(), saved.toJson());
    await expectLater(
      repository.answerMcq(attempt.id, attempt.mcqs.first.id, 'a'),
      throwsStateError,
    );
  });

  test(
    'saved timestamps require UTC, exact duration and consistent completion',
    () async {
      final attempt = await repository.start(1);
      Map<String, dynamic> snapshot() =>
          jsonDecode(jsonEncode(attempt.toJson())) as Map<String, dynamic>;
      final variants = <Map<String, dynamic>>[
        snapshot()..['startedAt'] = '2026-01-01T12:00:00',
        snapshot()
          ..['deadline'] = attempt.deadline
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        snapshot()
          ..['completedAt'] = attempt.startedAt
              .subtract(const Duration(seconds: 1))
              .toIso8601String()
          ..['finishReason'] = 'submitted',
        snapshot()
          ..['completedAt'] = attempt.deadline
              .add(const Duration(seconds: 1))
              .toIso8601String()
          ..['finishReason'] = 'submitted',
        snapshot()
          ..['completedAt'] = attempt.startedAt.toIso8601String()
          ..['finishReason'] = 'expired',
        snapshot()..['id'] = '------------------------------------',
      ];
      for (final row in variants) {
        expect(() => RehearsalAttempt.fromJson(row), throwsFormatException);
      }
      expect(
        attempt.remaining(attempt.startedAt.subtract(const Duration(days: 1))),
        const Duration(minutes: 45),
      );
      time.advance(const Duration(minutes: 45));
      final finished = await repository.finish(attempt.id);
      expect(finished.finishReason, 'expired');
      expect(finished.completedAt, attempt.deadline);
    },
  );

  test('saved selection and history reject mismatched snapshot identity', () async {
    final attempt = await repository.start(1);
    final settingName =
        '${RehearsalRepository.attemptPrefix}${attempt.id.replaceAll('-', '_')}';
    final row = attempt.toJson()
      ..['id'] = '12345678-1234-4234-8234-123456789abc';
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name: settingName,
            value: jsonEncode(row),
            updatedAt: time.now,
          ),
        );
    await expectLater(repository.current(), throwsFormatException);
    expect(await repository.history(), isEmpty);
    expect((await repository.historyWithDiagnostics()).unreadableCount, 1);
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name: RehearsalRepository.currentKey,
            value: 'bad-id',
            updatedAt: time.now,
          ),
        );
    await expectLater(repository.current(), throwsFormatException);
    await repository.resetCurrentPointer();
    expect(await repository.current(), isNull);
    expect(await db.select(db.userSettings).get(), isNotEmpty);
  });

  test('blank prose cannot claim a written criterion', () async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final attempt = await repository.start(3);
    final question = attempt.written.first;
    await repository.answerWritten(attempt.id, question.id, '  \n ');
    await repository.finish(attempt.id);
    await expectLater(
      repository.selfAssess(attempt.id, question.id, {
        question.criteria.first.id,
      }),
      throwsFormatException,
    );
    expect((await repository.current())!.selfAssessment, isEmpty);
    await repository.selfAssess(attempt.id, question.id, {});
    expect((await repository.current())!.selfAssessment[question.id], isEmpty);
  });

  test('malformed history rows stay backed up without hiding readable attempts', () async {
    final valid = await repository.start(1);
    final bad = <String, String>{
      '${RehearsalRepository.attemptPrefix}12345678_1234_4234_8234_123456789ab1':
          '{invalid',
      '${RehearsalRepository.attemptPrefix}12345678_1234_4234_8234_123456789ab2':
          '[]',
      '${RehearsalRepository.attemptPrefix}12345678_1234_4234_8234_123456789abc':
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
    expect(recovered.entries.single.id, valid.id);
    expect(recovered.unreadableCount, 3);
    expect((await repository.history()).single.id, valid.id);
    final backup = await UserDataBackup(db, clock: time.clock).exportJson();
    await UserDataBackup(db, clock: time.clock).eraseAll();
    await UserDataBackup(db, clock: time.clock).import(backup);
    expect((await repository.historyWithDiagnostics()).unreadableCount, 3);
    expect((await repository.history()).single.id, valid.id);
    final raw = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    for (final entry in bad.entries) {
      expect(raw[entry.key], entry.value);
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test(
    'a failed history expiry write propagates as a database error',
    () async {
      await repository.start(1);
      time.advance(const Duration(minutes: 46));
      await db.customStatement('''CREATE TEMP TRIGGER reject_rehearsal_history
      BEFORE UPDATE ON user_settings
      WHEN NEW.name LIKE 'wset_rehearsal_attempt_v1_%'
      BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END;''');
      await expectLater(
        repository.historyWithDiagnostics(),
        throwsA(isA<SqliteException>()),
      );
      await db.customStatement('DROP TRIGGER reject_rehearsal_history');
      expect((await repository.historyWithDiagnostics()).unreadableCount, 0);
      expect((await repository.history()).single.finishReason, 'expired');
    },
  );

  test('malformed banks fail before practice can start', () {
    final duplicate = rehearsalFixtureMap();
    (duplicate['mcqs'] as List).add((duplicate['mcqs'] as List).first);
    expect(
      () => RehearsalBank.fromJson(jsonEncode(duplicate)),
      throwsFormatException,
    );
    final badBlueprint = rehearsalFixtureMap(blueprint: true);
    badBlueprint['levels'][0]['blueprint']['service'] = 5;
    expect(
      () => RehearsalBank.fromJson(jsonEncode(badBlueprint)),
      throwsFormatException,
    );
  });
}
