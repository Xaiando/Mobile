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
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

String _bankText() =>
    File('assets/study/diploma_written_practice.json').readAsStringSync();

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
    bank = DiplomaWrittenBank.fromJson(_bankText());
    repository = DiplomaWrittenRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(13),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
  });
  tearDown(() => db.close());

  test(
    'original D1 and D2 presets have independent 90/60 minute writing',
    () async {
      expect(bank.presets.map((p) => p.unitId), ['D1', 'D2']);
      expect(bank.preset('D1').durationSeconds, 5400);
      expect(bank.preset('D2').durationSeconds, 3600);
      expect(bank.presets.every((p) => p.questions.length == 3), isTrue);
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      await expectLater(repository.start('D1'), throwsStateError);
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
      final d1 = await repository.start('D1');
      final d2 = await repository.start('D2');
      expect(d1.deadline.difference(d1.startedAt), const Duration(minutes: 90));
      expect(d2.deadline.difference(d2.startedAt), const Duration(minutes: 60));
      expect(d1.toJson().containsKey('correctAnswer'), isFalse);
      expect(d1.toJson().containsKey('score'), isFalse);
      expect((await repository.current('D1'))!.id, d1.id);
      expect((await repository.current('D2'))!.id, d2.id);
      await expectLater(repository.start('D1'), throwsStateError);
    },
  );

  test(
    'prose resumes, deadline persists and review waits until writing ends',
    () async {
      final started = await repository.start('D1');
      final question = started.questions.first;
      await repository.answer(
        started.id,
        question.id,
        'A cool slope may delay ripening.',
      );
      final reopened = DiplomaWrittenRepository(
        db,
        bank: bank,
        clock: time.clock,
      );
      expect(
        (await reopened.current('D1'))!.prose[question.id],
        contains('cool slope'),
      );
      await expectLater(
        reopened.review(started.id, question.id, {}, 'I need more site data.'),
        throwsStateError,
      );
      time.advance(const Duration(minutes: 90));
      await expectLater(
        repository.answer(started.id, question.id, 'Late rewrite'),
        throwsStateError,
      );
      final expired = await repository.read(started.id);
      expect(expired.finishReason, 'expired');
      expect(expired.completedAt, expired.deadline);
      expect(expired.prose[question.id], contains('cool slope'));
      expect(await repository.current('D1'), isNull);
      expect(expired.remaining(time.now), Duration.zero);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );

  test(
    'criterion-led review counts participation only after all three responses',
    () async {
      final d1 = await repository.start('D1');
      for (final question in d1.questions) {
        await repository.answer(
          d1.id,
          question.id,
          'My reasoned response for ${question.id}.',
        );
      }
      final finished = await repository.finish(d1.id);
      expect(finished.finishReason, 'submitted');
      expect(finished.isReviewed, isFalse);
      await expectLater(
        repository.answer(d1.id, d1.questions.first.id, 'Late'),
        throwsStateError,
      );
      await expectLater(
        repository.review(d1.id, d1.questions.first.id, {
          'unknown',
        }, 'Improve evidence.'),
        throwsFormatException,
      );
      for (final question in d1.questions) {
        await repository.review(d1.id, question.id, {
          question.criteria.first.id,
        }, 'I should test the assumption in ${question.id}.');
      }
      final reviewed = await repository.read(d1.id);
      expect(reviewed.isReviewed, isTrue);
      expect(reviewed.reviews, hasLength(3));
      var evidence = DiplomaWrittenEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(evidence.d1Reviewed, 1);
      expect(evidence.d2Reviewed, 0);
      final d2 = await repository.start('D2');
      await repository.answer(
        d2.id,
        d2.questions.first.id,
        'A partial business answer.',
      );
      await repository.finish(d2.id);
      evidence = DiplomaWrittenEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(
        evidence.d2Reviewed,
        0,
        reason: 'partial prose is not reviewed participation',
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(
        (await _settings(db)).keys.any((key) => key.startsWith('exam_pass_')),
        isFalse,
      );
    },
  );

  test(
    'settings backup preserves reviewed prose without a schema change',
    () async {
      final d2 = await repository.start('D2');
      for (final question in d2.questions) {
        await repository.answer(
          d2.id,
          question.id,
          'A complete response for ${question.id}.',
        );
      }
      await repository.finish(d2.id);
      for (final question in d2.questions) {
        await repository.review(
          d2.id,
          question.id,
          {},
          'I would add stronger evidence.',
        );
      }
      final backup = UserDataBackup(db, clock: time.clock);
      final json = await backup.exportJson();
      expect(jsonDecode(json)['format_version'], UserDataBackup.formatVersion);
      await backup.resetProgress();
      expect(
        DiplomaWrittenEvidenceReader.read(
          await _settings(db),
          now: time.now,
        ).d2Reviewed,
        1,
      );
      final restored = openTestDatabase();
      try {
        await seedCurriculum(restored);
        await _seedL4(restored);
        final copy = UserDataBackup(restored, clock: time.clock);
        await copy.import(json);
        expect(
          DiplomaWrittenEvidenceReader.read(
            await _settings(restored),
            now: time.now,
          ).d2Reviewed,
          1,
        );
        expect(
          (await DiplomaWrittenRepository(
            restored,
            bank: bank,
            clock: time.clock,
          ).read(d2.id)).prose,
          hasLength(3),
        );
        await copy.eraseAll();
        expect(
          DiplomaWrittenEvidenceReader.read(
            await _settings(restored),
            now: time.now,
          ).d2Reviewed,
          0,
        );
      } finally {
        await restored.close();
      }
    },
  );
}
