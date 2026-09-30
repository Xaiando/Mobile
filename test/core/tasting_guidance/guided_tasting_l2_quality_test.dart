import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
import 'guided_tasting_fixture.dart';

void main() {
  final bankText = File('assets/study/guided_tasting.json').readAsStringSync();
  final bank = GuidedTastingBank.fromJson(bankText);
  late AppDatabase db;
  late TestClock time;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L2');
  });
  tearDown(() => db.close());

  test('new Level 2 guidance teaches a conditional quality conclusion', () {
    final level = bank.levels.singleWhere((row) => row.level == 2);
    expect(level.gridId, 'tg_guided_wine_l2_v1');
    expect(level.evidencePrompts.map((row) => row.id), [
      'description',
      'quality',
    ]);
    expect(level.evidencePrompts.last.prompt, contains('quality judgement'));
    expect(level.evidencePrompts.last.prompt, contains('strength'));
    expect(level.evidencePrompts.last.prompt, contains('limitation'));
    expect(bank.cases.where((row) => row.level == 2), hasLength(3));
    for (final calibration in bank.cases.where((row) => row.level == 2)) {
      expect(
        calibration.criteria.map((row) => row.id),
        contains('quality'),
        reason: calibration.id,
      );
      expect(
        calibration.criteria.singleWhere((row) => row.id == 'quality').text,
        contains('tentative'),
        reason: calibration.id,
      );
      expect(calibration.feedback, contains('not marks'));
      expect(calibration.feedback, contains('quality argument'));
      expect(calibration.feedback, contains('personal liking'));
      expect(calibration.referenceObservations, hasLength(17));
      expect(
        calibration.referenceObservations.map((row) => row.attributeKey),
        isNot(contains('quality')),
      );
    }
  });

  test(
    'new Level 2 session needs written quality evidence to finish',
    () async {
      final repository = GuidedTastingRepository(
        db,
        bank: bank,
        clock: time.clock,
      );
      final record = await repository.start(2);
      expect(record.bankVersion, '1.1.0');
      expect(record.level.evidencePrompts.map((row) => row.id), [
        'description',
        'quality',
      ]);
      await repository.choose(record.sessionId, 'sweetness', {'dry'});
      await repository.evidence(
        record.sessionId,
        'description',
        'The scenario appears clear and has a dry, citrus-led palate.',
      );
      await expectLater(repository.finish(record.sessionId), throwsStateError);
      await repository.evidence(record.sessionId, 'quality', '   ');
      await expectLater(repository.finish(record.sessionId), throwsStateError);
      await repository.evidence(
        record.sessionId,
        'quality',
        'Tentatively sound: refreshing acidity supports the fruit; the narrow flavour range limits complexity. My liking is separate from this judgement.',
      );
      final finished = await repository.finish(record.sessionId);
      expect(finished.isFinished, isTrue);
      expect(finished.evidence['quality'], contains('limits complexity'));
      expect(
        (await repository.session(record.sessionId)).completedAt,
        isNotNull,
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      await expectLater(
        repository.selfAssess(record.sessionId, {'quality'}),
        throwsStateError,
      );
    },
  );

  test('Level 2 calibration quality criteria remain self-assessed in backups', () async {
    // Keep the small database fixture's vocabulary and knowledge links, while
    // exercising the actual new Level 2 prompt and authored quality criterion.
    final fixture = guidedTastingFixtureMap();
    fixture['version'] = bank.version;
    fixture['levels'] = bank.levels.map((level) => level.toJson()).toList();
    final calibration = (fixture['cases'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['level'] == 2);
    final quality = bank.cases
        .firstWhere((row) => row.level == 2)
        .criteria
        .singleWhere((row) => row.id == 'quality');
    (calibration['criteria'] as List).add({
      'id': quality.id,
      'text': quality.text,
    });
    final repository = GuidedTastingRepository(
      db,
      bank: GuidedTastingBank.fromJson(jsonEncode(fixture)),
      clock: time.clock,
    );
    final record = await repository.start(2, caseId: 'case_l2');
    await repository.choose(record.sessionId, 'sweetness', {'dry'});
    await repository.evidence(
      record.sessionId,
      'description',
      'The stated palate is dry and the aromas are citrus.',
    );
    await expectLater(repository.finish(record.sessionId), throwsStateError);
    await expectLater(
      repository.selfAssess(record.sessionId, {'quality'}),
      throwsStateError,
    );
    await repository.evidence(
      record.sessionId,
      'quality',
      'A tentative judgement needs balance and persistence evidence; the short note does not provide enough to decide confidently.',
    );
    final finished = await repository.finish(record.sessionId);
    expect(finished.selfAssessment, isEmpty);
    final assessed = await repository.selfAssess(record.sessionId, {'quality'});
    expect(assessed.selfAssessment, {'quality'});

    final backup = UserDataBackup(db, clock: time.clock);
    final exported = await backup.exportJson();
    await backup.eraseAll();
    await backup.import(exported);
    fixture['version'] = 'future.2';
    calibration['criteria'] = [
      {'id': 'replacement', 'text': 'Future criterion'},
    ];
    final newer = GuidedTastingRepository(
      db,
      bank: GuidedTastingBank.fromJson(jsonEncode(fixture)),
      clock: time.clock,
    );
    expect((await newer.read(record.sessionId)).toJson(), assessed.toJson());
    expect((await newer.current())!.toJson(), assessed.toJson());
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(
      (await db.select(db.userSettings).get()).any(
        (row) => row.name.startsWith('exam_pass_'),
      ),
      isFalse,
    );
  });

  test(
    'older Level 2 drafts and completions keep their saved contract',
    () async {
      final oldJson = jsonDecode(bankText) as Map<String, dynamic>;
      oldJson['version'] = '1.0.0';
      final oldLevel = (oldJson['levels'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['level'] == 2);
      oldLevel['evidencePrompts'] = [
        (oldLevel['evidencePrompts'] as List).first,
      ];
      final legacy = GuidedTastingRepository(
        db,
        bank: GuidedTastingBank.fromJson(jsonEncode(oldJson)),
        clock: time.clock,
      );
      final updated = GuidedTastingRepository(
        db,
        bank: bank,
        clock: time.clock,
      );

      final draft = await legacy.start(2);
      await legacy.choose(draft.sessionId, 'sweetness', {'dry'});
      await legacy.evidence(
        draft.sessionId,
        'description',
        'A saved description from the older Level 2 practice.',
      );
      final resumed = await updated.read(draft.sessionId);
      expect(resumed.bankVersion, '1.0.0');
      expect(resumed.level.evidencePrompts.map((row) => row.id), [
        'description',
      ]);
      expect(resumed.evidence, isNot(contains('quality')));
      final migratedFinish = await updated.finish(draft.sessionId);
      expect(migratedFinish.isFinished, isTrue);
      expect(migratedFinish.evidence, isNot(contains('quality')));

      final oldCompletion = await legacy.start(2);
      await legacy.choose(oldCompletion.sessionId, 'sweetness', {'off_dry'});
      await legacy.evidence(
        oldCompletion.sessionId,
        'description',
        'A second saved description from the older practice.',
      );
      final completed = await legacy.finish(oldCompletion.sessionId);
      expect(
        (await updated.read(completed.sessionId)).toJson(),
        completed.toJson(),
      );
      final history = await updated.history();
      expect(history.map((row) => row.sessionId).toSet(), {
        draft.sessionId,
        completed.sessionId,
      });
      expect(history.every((row) => row.isFinished), isTrue);
      expect(history.every((row) => row.bankVersion == '1.0.0'), isTrue);

      final newRecord = await updated.start(2);
      expect(newRecord.bankVersion, '1.1.0');
      expect(newRecord.level.evidencePrompts.map((row) => row.id), [
        'description',
        'quality',
      ]);
      expect((await updated.history()).map((row) => row.sessionId).toSet(), {
        draft.sessionId,
        completed.sessionId,
        newRecord.sessionId,
      });

      final beforeBackup = {
        for (final saved in await updated.history())
          saved.sessionId: saved.toJson(),
      };
      final backup = UserDataBackup(db, clock: time.clock);
      final exported = await backup.exportJson();
      await backup.eraseAll();
      await backup.import(exported);
      expect({
        for (final saved in await updated.history())
          saved.sessionId: saved.toJson(),
      }, beforeBackup);
      expect(
        (await updated.read(draft.sessionId)).level.evidencePrompts
            .map((prompt) => prompt.id),
        ['description'],
      );
      expect(
        (await updated.read(newRecord.sessionId)).level.evidencePrompts
            .map((prompt) => prompt.id),
        ['description', 'quality'],
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );
}
