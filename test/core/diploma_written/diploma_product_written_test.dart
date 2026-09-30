import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/diploma_written/diploma_written_evidence.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

Map<String, dynamic> _document() => jsonDecode(
  File('assets/study/diploma_written_practice.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> _legacy() {
  final row = _document();
  row['version'] = '1.0.0';
  row['units'] = (row['units'] as List).take(2).toList();
  return row;
}

Future<void> _seedL4(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
  ]),
);

Future<Map<String, String>> _settings(AppDatabase db) async => {
  for (final row in await db.select(db.userSettings).get()) row.name: row.value,
};

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaWrittenBank bank;
  late DiplomaWrittenRepository repository;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await _seedL4(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    bank = DiplomaWrittenBank.fromJson(jsonEncode(_document()));
    repository = DiplomaWrittenRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(67),
    );
  });
  tearDown(() => db.close());

  test('only complete legacy or expanded banks are accepted', () {
    expect(bank.version, '1.2.0');
    expect(bank.presets.map((preset) => preset.unitId), [
      'D1',
      'D2',
      'D4',
      'D5',
      'D3',
    ]);
    expect(bank.presets.map((preset) => preset.durationSeconds), [
      5400,
      3600,
      2700,
      2700,
      3600,
    ]);
    final legacy = DiplomaWrittenBank.fromJson(jsonEncode(_legacy()));
    expect(legacy.presets.map((preset) => preset.unitId), ['D1', 'D2']);
    for (final unit in ['D1', 'D2']) {
      expect(
        bank.preset(unit).questions.map((q) => q.toJson()).toList(),
        legacy.preset(unit).questions.map((q) => q.toJson()).toList(),
      );
    }
    final units = _document()['units'] as List;
    for (final indices in <List<int>>[
      [],
      [0],
      [1],
      [0, 2],
      [0, 1, 2],
      [0, 1, 3],
      [0, 0],
      [0, 1, 2, 2],
      [0, 1, 2, 3, 3],
    ]) {
      final row = _document();
      row['units'] = [for (final index in indices) units[index]];
      expect(
        () => DiplomaWrittenBank.fromJson(jsonEncode(row)),
        throwsFormatException,
        reason: 'Partial or duplicate unit set: $indices',
      );
    }
    for (final wrongDuration in [2699, 2701, 5400]) {
      final row = _document();
      (row['units'] as List)[2]['durationSeconds'] = wrongDuration;
      expect(
        () => DiplomaWrittenBank.fromJson(jsonEncode(row)),
        throwsFormatException,
      );
    }
    final unsupported = _document();
    (unsupported['units'] as List)[2]['unitId'] = 'D6';
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(unsupported)),
      throwsFormatException,
    );
    final productQuestions = [
      ...bank.preset('D4').questions,
      ...bank.preset('D5').questions,
    ];
    expect(productQuestions.map((q) => q.id).toSet(), hasLength(6));
    expect(productQuestions.every((q) => q.criteria.length == 4), isTrue);
    expect(productQuestions.map((q) => q.prompt).toSet(), hasLength(6));
  });

  test(
    'legacy D1/D2 snapshots and pointers resume unchanged in the new bank',
    () async {
      final legacyRepository = DiplomaWrittenRepository(
        db,
        bank: DiplomaWrittenBank.fromJson(jsonEncode(_legacy())),
        clock: time.clock,
        random: Random(31),
      );
      final originals = <DiplomaWrittenAttempt>[];
      for (final unit in ['D1', 'D2']) {
        final attempt = await legacyRepository.start(unit);
        await legacyRepository.answer(
          attempt.id,
          attempt.questions.first.id,
          'A private legacy response for $unit.',
        );
        originals.add(await legacyRepository.read(attempt.id));
      }
      time.advance(const Duration(minutes: 30));
      for (final original in originals) {
        final resumed = await repository.current(original.unitId);
        expect(resumed!.toJson(), original.toJson());
        expect(resumed.bankVersion, '1.0.0');
        expect(
          resumed.remaining(time.now),
          Duration(minutes: original.unitId == 'D1' ? 60 : 30),
        );
        expect(
          (await _settings(db))[DiplomaWrittenRepository.currentKey(
            original.unitId,
          )],
          original.id,
        );
      }
      final d4 = await repository.start('D4');
      expect(d4.bankVersion, '1.2.0');
      expect(d4.deadline.difference(d4.startedAt), const Duration(minutes: 45));
      expect(
        (await repository.historyWithDiagnostics('D1')).unreadableCount,
        0,
      );
      final invalidSnapshot = d4.toJson();
      invalidSnapshot['deadline'] = d4.deadline
          .add(const Duration(seconds: 1))
          .toIso8601String();
      expect(
        () => DiplomaWrittenAttempt.fromJson(invalidSnapshot),
        throwsFormatException,
        reason:
            'The stored product-unit deadline must retain its exact duration.',
      );
      final unsupportedSnapshot = d4.toJson();
      unsupportedSnapshot['unitId'] = 'D6';
      expect(
        () => DiplomaWrittenAttempt.fromJson(unsupportedSnapshot),
        throwsFormatException,
      );
    },
  );

  test(
    'D4/D5 restart retains 45 minutes and late edits commit expiry',
    () async {
      final attempts = [
        await repository.start('D4'),
        await repository.start('D5'),
      ];
      for (final attempt in attempts) {
        await repository.answer(
          attempt.id,
          attempt.questions.first.id,
          'Original response for ${attempt.unitId}.',
        );
      }
      time.advance(const Duration(minutes: 15));
      final reopened = DiplomaWrittenRepository(
        db,
        bank: bank,
        clock: time.clock,
      );
      for (final attempt in attempts) {
        final saved = await reopened.current(attempt.unitId);
        expect(saved!.deadline, attempt.deadline);
        expect(saved.remaining(time.now), const Duration(minutes: 30));
        await expectLater(
          reopened.review(
            attempt.id,
            attempt.questions.first.id,
            {},
            'Improve comparison.',
          ),
          throwsStateError,
        );
      }
      time.advance(const Duration(minutes: 30));
      for (final attempt in attempts) {
        await expectLater(
          reopened.answer(
            attempt.id,
            attempt.questions.first.id,
            'Late replacement',
          ),
          throwsStateError,
        );
        final saved = await reopened.read(attempt.id);
        expect(saved.finishReason, 'expired');
        expect(saved.completedAt, attempt.deadline);
        expect(
          saved.prose[attempt.questions.first.id],
          startsWith('Original response'),
        );
        expect(await reopened.current(attempt.unitId), isNull);
        expect(
          (await _settings(db))
              .containsKey(DiplomaWrittenRepository.currentKey(attempt.unitId)),
          isFalse,
        );
      }
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(await db.select(db.reviewStates).get(), isEmpty);
    },
  );

  test('product-unit self-review adds participation only for three saved responses', () async {
    final projection = WsetProgressRepository(
      db,
      scope: WsetScope([
        for (var level = 1; level <= 4; level++)
          WsetLevelScope(
            certificationId: 'WSET_L$level',
            title: level == 4 ? 'Diploma' : 'Level $level',
            curriculumComplete: false,
            gaps: ['Expert review and remaining coverage are still needed.'],
            sourceUrl: 'https://www.wsetglobal.com/',
            units: level == 4
                ? [
                    for (final unit in ['D1', 'D2', 'D3', 'D4', 'D5', 'D6'])
                      WsetUnitScope(
                        id: unit,
                        title: unit,
                        gap: 'More practice needed.',
                      ),
                  ]
                : [],
          ),
      ]),
      clock: time.clock,
    );
    final prior = (await projection.snapshot()).levels.last;
    final d4 = await repository.start('D4');
    for (final question in d4.questions) {
      await repository.answer(
        d4.id,
        question.id,
        'My explanation for ${question.id}.',
      );
    }
    await repository.finish(d4.id);
    for (final question in d4.questions) {
      await repository.review(
        d4.id,
        question.id,
        {},
        'I would compare stronger evidence.',
      );
    }
    final partial = await repository.start('D5');
    final question = partial.questions.first;
    await repository.answer(
      partial.id,
      question.id,
      'One saved Port explanation.',
    );
    await repository.finish(partial.id);
    await repository.review(partial.id, question.id, {
      question.criteria.first.id,
    }, 'I need bottle evidence.');
    var evidence = DiplomaWrittenEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.forUnit('D4'), 1);
    expect(evidence.forUnit('D5'), 0);
    expect(evidence.forUnit('D1'), 0);
    expect(evidence.forUnit('D2'), 0);
    expect(evidence.forUnit('D6'), 0);

    final complete = await repository.start('D5');
    for (final question in complete.questions) {
      await repository.answer(
        complete.id,
        question.id,
        'A complete comparison for ${question.id}.',
      );
    }
    await repository.finish(complete.id);
    for (final question in complete.questions) {
      await repository.review(complete.id, question.id, {
        question.criteria.first.id,
      }, 'I would test a stated assumption.');
    }
    final abandoned = await repository.start('D4');
    await repository.answer(
      abandoned.id,
      abandoned.questions.first.id,
      'An abandoned draft.',
    );
    await repository.abandon(abandoned.id);
    await expectLater(
      repository.review(
        abandoned.id,
        abandoned.questions.first.id,
        {},
        'Add evidence.',
      ),
      throwsStateError,
    );
    evidence = DiplomaWrittenEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.d4Reviewed, 1);
    expect(evidence.d5Reviewed, 1);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(
      (await _settings(db)).keys.any((key) => key.startsWith('exam_pass_')),
      isFalse,
    );
    expect(
      (await repository.read(complete.id)).toJson().containsKey('score'),
      isFalse,
    );
    final projected = (await projection.snapshot()).levels.last;
    expect(
      projected.units.singleWhere((u) => u.scope.id == 'D4').writtenPractices,
      1,
    );
    expect(
      projected.units.singleWhere((u) => u.scope.id == 'D5').writtenPractices,
      1,
    );
    expect(projected.units.every((u) => u.physicalFlights == 0), isTrue);
    expect(projected.counts.mapped, prior.counts.mapped);
    expect(projected.counts.studied, prior.counts.studied);
    expect(projected.counts.mastered, prior.counts.mastered);
    expect(projected.examPassed, prior.examPassed);
    expect(projected.examPassed, isFalse);
    expect(projected.appLevelComplete, isFalse);
  });

  test(
    'backup retains new drafts, reviewed prose and opaque recovery data',
    () async {
      final reviewed = await repository.start('D4');
      for (final question in reviewed.questions) {
        await repository.answer(
          reviewed.id,
          question.id,
          'Private response for ${question.id}.',
        );
      }
      await repository.finish(reviewed.id);
      for (final question in reviewed.questions) {
        await repository.review(
          reviewed.id,
          question.id,
          {},
          'I would improve source comparison.',
        );
      }
      final draft = await repository.start('D5');
      await repository.answer(
        draft.id,
        draft.questions.first.id,
        'Private ongoing Port response.',
      );
      const recoveryKey =
          '${DiplomaWrittenRepository.attemptPrefix}opaque_recovery';
      const opaqueValue =
          'An unreadable legacy snapshot retained for recovery.';
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: recoveryKey,
              value: opaqueValue,
              updatedAt: time.now,
            ),
          );
      final backup = UserDataBackup(db, clock: time.clock);
      final document = await backup.exportJson();
      await backup.resetProgress();
      expect(
        DiplomaWrittenEvidenceReader.read(
          await _settings(db),
          now: time.now,
        ).d4Reviewed,
        1,
      );

      final restored = openTestDatabase();
      try {
        await seedCurriculum(restored);
        await _seedL4(restored);
        final copy = UserDataBackup(restored, clock: time.clock);
        await copy.import(document);
        final reopened = DiplomaWrittenRepository(
          restored,
          bank: bank,
          clock: time.clock,
        );
        expect(
          (await reopened.current('D5'))!.toJson(),
          (await repository.read(draft.id)).toJson(),
        );
        expect((await reopened.read(reviewed.id)).isReviewed, isTrue);
        expect((await _settings(restored))[recoveryKey], opaqueValue);
        final evidence = DiplomaWrittenEvidenceReader.read(
          await _settings(restored),
          now: time.now,
        );
        expect(evidence.d4Reviewed, 1);
        expect(evidence.d5Reviewed, 0);
        expect(evidence.unreadableCount, 1);
        final history = await reopened.historyWithDiagnostics('D4');
        expect(history.entries, hasLength(1));
        expect(history.unreadableCount, 1);
        expect(await restored.select(restored.reviewEvents).get(), isEmpty);
        await copy.eraseAll();
        expect((await _settings(restored)).containsKey(recoveryKey), isFalse);
        expect(
          DiplomaWrittenEvidenceReader.read(
            await _settings(restored),
            now: time.now,
          ).d4Reviewed,
          0,
        );
      } finally {
        await restored.close();
      }
    },
  );
}
