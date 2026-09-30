import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

Map<String, dynamic> _document() => jsonDecode(
  File('assets/study/diploma_written_practice.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> _previousBank(int count, String version) {
  final row = _document();
  row['version'] = version;
  row['units'] = (row['units'] as List).take(count).toList();
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

Future<DiplomaWrittenAttempt> _reviewedD3(
  DiplomaWrittenRepository repository,
) async {
  final attempt = await repository.start('D3');
  for (final question in attempt.questions) {
    await repository.answer(
      attempt.id,
      question.id,
      'A saved regional explanation for ${question.id}.',
    );
  }
  await repository.finish(attempt.id);
  for (final question in attempt.questions) {
    await repository.review(
      attempt.id,
      question.id,
      {},
      'I will test a regional assumption for ${question.id}.',
    );
  }
  return repository.read(attempt.id);
}

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
      random: Random(83),
    );
  });
  tearDown(() => db.close());

  test('D3 app bank accepts only complete legacy, product and regional sets', () {
    expect(bank.version, '1.2.0');
    expect(bank.presets.map((p) => p.unitId), ['D1', 'D2', 'D4', 'D5', 'D3']);
    final regional = bank.preset('D3');
    expect(regional.durationSeconds, 3600);
    expect(regional.questions.map((q) => q.id), [
      'd3_bairrada_rain',
      'd3_ribeira_offer',
      'd3_otago_frost',
    ]);
    expect(regional.questions.every((q) => q.criteria.length == 4), isTrue);
    expect(regional.questions.map((q) => q.prompt).toSet(), hasLength(3));
    expect(
      regional.questions.every((q) => q.prompt.startsWith('A fictional ')),
      isTrue,
    );
    expect(
      DiplomaWrittenBank.fromJson(jsonEncode(_previousBank(2, '1.0.0'))).presets
          .map((p) => p.unitId),
      ['D1', 'D2'],
    );
    final previous = _previousBank(4, '1.1.0');
    expect(
      DiplomaWrittenBank.fromJson(jsonEncode(previous)).presets
          .map((p) => p.unitId),
      ['D1', 'D2', 'D4', 'D5'],
    );
    // Pin the parsed four-unit bank from the frozen 0.24.63 release candidate.
    // Formatting can change; the old prompts, criteria and durations cannot.
    expect(
      sha256.convert(utf8.encode(jsonEncode(previous['units']))).toString(),
      'feecdecf651cd0831b73b144d5aaaa07d3a6585c3918d63444dbb6374f17da59',
    );
    final units = _document()['units'] as List;
    for (final indices in <List<int>>[
      [4],
      [0, 1, 4],
      [0, 1, 2, 4],
      [0, 1, 3, 4],
      [0, 1, 2, 3, 4, 4],
      [0, 1, 2, 2, 4],
    ]) {
      final row = _document();
      row['units'] = [for (final index in indices) units[index]];
      expect(
        () => DiplomaWrittenBank.fromJson(jsonEncode(row)),
        throwsFormatException,
        reason: 'Incomplete or duplicate unit set: $indices',
      );
    }
    for (final invalidSeconds in [3599, 3601, 2700, 12000]) {
      final row = _document();
      (row['units'] as List).last['durationSeconds'] = invalidSeconds;
      expect(
        () => DiplomaWrittenBank.fromJson(jsonEncode(row)),
        throwsFormatException,
      );
    }
    final unsupported = _document();
    (unsupported['units'] as List).last['unitId'] = 'D6';
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(unsupported)),
      throwsFormatException,
    );
  });

  test(
    'all four earlier unit snapshots resume unchanged under bank 1.2.0',
    () async {
      final earlier = DiplomaWrittenRepository(
        db,
        bank: DiplomaWrittenBank.fromJson(
          jsonEncode(_previousBank(4, '1.1.0')),
        ),
        clock: time.clock,
        random: Random(19),
      );
      final snapshots = <DiplomaWrittenAttempt>[];
      for (final unit in ['D1', 'D2', 'D4', 'D5']) {
        final started = await earlier.start(unit);
        snapshots.add(
          await earlier.answer(
            started.id,
            started.questions.first.id,
            'A retained 1.1.0 response for $unit.',
          ),
        );
      }
      final savedBefore = await _settings(db);
      time.advance(const Duration(minutes: 10));
      for (final snapshot in snapshots) {
        final resumed = await repository.resume(snapshot.id);
        expect(resumed.toJson(), snapshot.toJson());
        expect(resumed.bankVersion, '1.1.0');
        expect(
          resumed.remaining(time.now),
          snapshot.deadline.difference(time.now),
        );
        expect(
          (await repository.current(snapshot.unitId))!.toJson(),
          snapshot.toJson(),
        );
      }
      expect(await _settings(db), savedBefore);
      final d3 = await repository.start('D3');
      expect(d3.bankVersion, '1.2.0');
      expect(d3.deadline.difference(d3.startedAt), const Duration(minutes: 60));
      expect(d3.toJson()['schemaVersion'], 1);
      expect(
        (await _settings(db)).keys.where(
          (key) => key.startsWith(DiplomaWrittenRepository.currentPrefix),
        ),
        hasLength(5),
      );
    },
  );

  test('D3 concurrent starts have one winner and no orphan snapshot', () async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    await expectLater(repository.start('D3'), throwsStateError);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    Future<Object> startOrError() async {
      try {
        return await repository.start('D3');
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait([startOrError(), startOrError()]);
    final attempts = results.whereType<DiplomaWrittenAttempt>().toList();
    expect(attempts, hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
    final settings = await _settings(db);
    expect(
      settings.keys.where(
        (k) => k.startsWith(DiplomaWrittenRepository.attemptPrefix),
      ),
      hasLength(1),
    );
    expect(
      settings.keys.where(
        (k) => k.startsWith(DiplomaWrittenRepository.currentPrefix),
      ),
      hasLength(1),
    );
    expect(
      settings[DiplomaWrittenRepository.currentKey('D3')],
      attempts.single.id,
    );
    expect(
      jsonDecode(
        settings[DiplomaWrittenRepository.keyFor(attempts.single.id)]!,
      ),
      attempts.single.toJson(),
    );
  });

  test(
    'D3 saved prose resumes and rejected late edits persist exact expiry',
    () async {
      final started = await repository.start('D3');
      final question = started.questions.first;
      final draft = await repository.answer(
        started.id,
        question.id,
        'I would sample B again after the forecast rain.',
      );
      time.advance(const Duration(minutes: 15));
      final reopened = DiplomaWrittenRepository(
        db,
        bank: bank,
        clock: time.clock,
      );
      final resumed = await reopened.resume(draft.id);
      expect(resumed.toJson(), draft.toJson());
      expect(resumed.remaining(time.now), const Duration(minutes: 45));
      await expectLater(
        reopened.review(
          draft.id,
          question.id,
          {},
          'I need a fruit-health check.',
        ),
        throwsStateError,
      );
      time.advance(const Duration(minutes: 45));
      await expectLater(
        reopened.answer(draft.id, question.id, 'Late replacement'),
        throwsStateError,
      );
      final settings = await _settings(db);
      final persisted = jsonDecode(
        settings[DiplomaWrittenRepository.keyFor(draft.id)]!,
      ) as Map<String, dynamic>;
      expect(persisted['finishReason'], 'expired');
      expect(persisted['completedAt'], draft.deadline.toIso8601String());
      expect(
        settings.containsKey(DiplomaWrittenRepository.currentKey('D3')),
        isFalse,
      );
      final expired = await reopened.read(draft.id);
      expect(expired.prose, draft.prose);
      expect(
        expired.questions.map((q) => q.toJson()).toList(),
        draft.questions.map((q) => q.toJson()).toList(),
      );
      expect(expired.isReviewed, isFalse);
      expect(await reopened.current('D3'), isNull);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );

  test('a detached D3 draft cannot displace another live draft', () async {
    final first = await repository.start('D3');
    final detached = await repository.answer(
      first.id,
      first.questions.first.id,
      'Private first regional draft.',
    );
    await repository.resetCurrentPointer('D3');
    final second = await repository.start('D3');
    final active = await repository.answer(
      second.id,
      second.questions.first.id,
      'Private second regional draft.',
    );
    final before = await _settings(db);
    await expectLater(repository.resume(detached.id), throwsStateError);
    expect(await _settings(db), before);
    expect((await repository.read(detached.id)).toJson(), detached.toJson());
    expect((await repository.read(active.id)).toJson(), active.toJson());
    expect((await repository.current('D3'))!.id, active.id);
  });

  test('D3 participation requires three saved responses and improvement-led reviews', () async {
    final partial = await repository.start('D3');
    await repository.answer(
      partial.id,
      partial.questions.first.id,
      'One regional explanation.',
    );
    await repository.finish(partial.id);
    await repository.review(
      partial.id,
      partial.questions.first.id,
      {},
      'Add health evidence.',
    );
    expect(
      DiplomaWrittenEvidenceReader.read(
        await _settings(db),
        now: time.now,
      ).d3Reviewed,
      0,
    );
    final complete = await repository.start('D3');
    for (final question in complete.questions) {
      await repository.answer(
        complete.id,
        question.id,
        'My regional comparison for ${question.id}.',
      );
    }
    await repository.finish(complete.id);
    await expectLater(
      repository.review(complete.id, complete.questions.first.id, {
        'unknown',
      }, 'Improve the comparison.'),
      throwsFormatException,
    );
    await expectLater(
      repository.review(complete.id, complete.questions.first.id, {}, '   '),
      throwsFormatException,
    );
    for (final question in complete.questions.take(2)) {
      await repository.review(
        complete.id,
        question.id,
        {},
        'I would add specific source evidence.',
      );
    }
    expect(
      DiplomaWrittenEvidenceReader.read(
        await _settings(db),
        now: time.now,
      ).d3Reviewed,
      0,
    );
    await repository.review(
      complete.id,
      complete.questions.last.id,
      {},
      'My argument needs a comparison of site and season.',
    );
    final reviewed = await repository.read(complete.id);
    expect(reviewed.isReviewed, isTrue);
    expect(
      reviewed.reviews.values.every(
        (review) => review.selectedCriteria.isEmpty,
      ),
      isTrue,
      reason: 'An honest review with no selected criteria is participation, not a score.',
    );
    final abandoned = await repository.start('D3');
    for (final question in abandoned.questions) {
      await repository.answer(
        abandoned.id,
        question.id,
        'A discarded regional draft.',
      );
    }
    await repository.abandon(abandoned.id);
    await expectLater(
      repository.review(
        abandoned.id,
        abandoned.questions.first.id,
        {},
        'A discarded review.',
      ),
      throwsStateError,
    );
    final evidence = DiplomaWrittenEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.d3Reviewed, 1);
    expect(evidence.forUnit('D3'), 1);
    expect(evidence.forUnit('D6'), 0);
    expect(
      [
        evidence.d1Reviewed,
        evidence.d2Reviewed,
        evidence.d4Reviewed,
        evidence.d5Reviewed,
      ],
      [0, 0, 0, 0],
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(
      (await _settings(db)).keys.any((key) => key.startsWith('exam_pass_')),
      isFalse,
    );
    expect(reviewed.toJson().containsKey('score'), isFalse);
    expect(reviewed.toJson().containsKey('correctAnswer'), isFalse);
  });

  test(
    'D3 future, corrupt and mismatched records cannot grant participation',
    () async {
      final original = await _reviewedD3(repository);
      const futureId = '11111111-1111-4111-8111-111111111111';
      const mismatchId = '22222222-2222-4222-8222-222222222222';
      const corruptId = '33333333-3333-4333-8333-333333333333';
      final futureTime = time.now.add(const Duration(minutes: 2));
      final futureRow =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      futureRow['id'] = futureId;
      futureRow['startedAt'] = futureTime.toIso8601String();
      futureRow['deadline'] = futureTime
          .add(const Duration(hours: 1))
          .toIso8601String();
      futureRow['completedAt'] = futureTime.toIso8601String();
      for (final review in (futureRow['reviews'] as Map).values) {
        (review as Map<String, dynamic>)['reviewedAt'] = futureTime
            .toIso8601String();
      }
      expect(DiplomaWrittenAttempt.fromJson(futureRow).isReviewed, isTrue);
      for (final entry in {
        DiplomaWrittenRepository.keyFor(futureId): jsonEncode(futureRow),
        DiplomaWrittenRepository.keyFor(mismatchId): jsonEncode(
          original.toJson(),
        ),
        DiplomaWrittenRepository.keyFor(corruptId): '{"broken":',
      }.entries) {
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
      var evidence = DiplomaWrittenEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(evidence.d3Reviewed, 1);
      expect(evidence.unreadableCount, 3);
      final history = await repository.historyWithDiagnostics('D3');
      expect(history.entries.map((entry) => entry.id), [original.id]);
      expect(history.unreadableCount, 3);
      final rows = await _settings(db);
      time.advance(const Duration(minutes: 2));
      evidence = DiplomaWrittenEvidenceReader.read(rows, now: time.now);
      expect(evidence.d3Reviewed, 2);
      expect(evidence.unreadableCount, 2);
      time.advance(const Duration(minutes: -2));
      evidence = DiplomaWrittenEvidenceReader.read(rows, now: time.now);
      expect(evidence.d3Reviewed, 1);
      expect(evidence.unreadableCount, 3);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );

  test(
    'D3 backup retains reviewed work, a live draft and opaque recovery bytes',
    () async {
      final reviewed = await _reviewedD3(repository);
      final started = await repository.start('D3');
      final draft = await repository.answer(
        started.id,
        started.questions.first.id,
        'A private regional explanation still in progress.',
      );
      const recoveryKey = 'diploma_written_attempt_v1_opaque_d3_recovery';
      const opaque = 'Unreadable D3 bytes retained for recovery.';
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(name: recoveryKey, value: opaque, updatedAt: time.now),
          );
      final backup = UserDataBackup(db, clock: time.clock);
      final exported = await backup.exportJson();
      expect(
        jsonDecode(exported)['format_version'],
        UserDataBackup.formatVersion,
      );
      await backup.resetProgress();
      expect(
        DiplomaWrittenEvidenceReader.read(
          await _settings(db),
          now: time.now,
        ).d3Reviewed,
        1,
      );
      final restored = openTestDatabase();
      try {
        await seedCurriculum(restored);
        await _seedL4(restored);
        final copy = UserDataBackup(restored, clock: time.clock);
        await copy.import(exported);
        final reopened = DiplomaWrittenRepository(
          restored,
          bank: bank,
          clock: time.clock,
        );
        expect((await reopened.read(reviewed.id)).toJson(), reviewed.toJson());
        expect((await reopened.current('D3'))!.toJson(), draft.toJson());
        final rows = await _settings(restored);
        expect(rows[recoveryKey], opaque);
        expect(rows[DiplomaWrittenRepository.currentKey('D3')], draft.id);
        var evidence = DiplomaWrittenEvidenceReader.read(rows, now: time.now);
        expect(evidence.d3Reviewed, 1);
        expect(evidence.unreadableCount, 1);
        expect(await restored.select(restored.reviewEvents).get(), isEmpty);
        expect(await restored.select(restored.reviewStates).get(), isEmpty);
        expect(rows.keys.any((key) => key.startsWith('exam_pass_')), isFalse);
        await copy.eraseAll();
        final erased = await _settings(restored);
        expect(
          erased.keys.where(
            (key) => key.startsWith(DiplomaWrittenRepository.attemptPrefix),
          ),
          isEmpty,
        );
        expect(
          erased.containsKey(DiplomaWrittenRepository.currentKey('D3')),
          isFalse,
        );
        evidence = DiplomaWrittenEvidenceReader.read(erased, now: time.now);
        expect(evidence.d3Reviewed, 0);
        expect(evidence.unreadableCount, 0);
      } finally {
        await restored.close();
      }
    },
  );
}
