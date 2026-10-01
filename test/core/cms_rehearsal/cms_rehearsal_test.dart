import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_evidence.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

String _bankText() =>
    File('assets/study/cms_certified_rehearsal.json').readAsStringSync();
Map<String, dynamic> _bankRow() =>
    Map<String, dynamic>.from(jsonDecode(_bankText()) as Map);
// Repository contracts use a small source-linked DB fixture. The real bundled
// bank's fact IDs and source eligibility are checked separately against ingestion.
CmsRehearsalBank _fixtureBank({
  String linked = 'ki_chablis_grape',
  String version = '1.0.0',
}) {
  final row = _bankRow();
  row['version'] = version;
  for (final q in row['mcqs'] as List) {
    q['itemIds'] = [linked];
  }
  for (final q in row['written'] as List) {
    for (final c in q['criteria'] as List) {
      c['itemIds'] = [linked];
    }
  }
  return CmsRehearsalBank.fromJson(jsonEncode(row));
}

const _keys = [
  'clarity',
  'brightness',
  'hue',
  'concentration',
  'rim',
  'fruit_state',
  'fruit',
  'non_fruit',
  'wood',
  'intensity',
  'dryness',
  'body',
  'acid',
  'alcohol',
  'tannin',
  'complexity',
  'finish',
  'climate',
  'style',
  'age',
];
Future<void> _seedGrid(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO tasting_grids VALUES ('tg_deductive','CMS_DTM','1','Original deductive practice')",
    for (final (index, key) in _keys.indexed)
      "INSERT INTO tasting_grid_attributes VALUES ('tg_deductive', '$key', 'observation', '$key', ${index + 1}, '${{'fruit', 'non_fruit'}.contains(key) ? 'multi' : 'single'}', ${{'fruit', 'non_fruit'}.contains(key) ? '0' : '1'})",
    for (final key in _keys)
      "INSERT INTO tasting_grid_values VALUES ('tg_deductive', '$key', 'first', 'First observation', 1, NULL), ('tg_deductive', '$key', 'second', 'Different observation', 2, NULL)",
  ]),
);
Future<Map<String, String>> _settings(AppDatabase db) async => {
  for (final r in await db.select(db.userSettings).get()) r.name: r.value,
};
Future<void> _put(AppDatabase db, String key, String value, DateTime now) => db
    .into(db.userSettings)
    .insertOnConflictUpdate(
      UserSetting(name: key, value: value, updatedAt: now),
    );
Future<void> _delete(AppDatabase db, String key) async {
  await (db.delete(db.userSettings)..where((r) => r.name.equals(key))).go();
}

Future<void> _expectExpiredBytes(
  AppDatabase db,
  CmsRehearsalAttempt original,
) async {
  // Inspect storage before any repository read can repair expiry itself.
  final settings = await _settings(db);
  final saved =
      jsonDecode(settings[CmsRehearsalRepository.keyFor(original.id)]!) as Map;
  expect(saved['completedAt'], original.deadline.toIso8601String());
  expect(saved['finishReason'], 'expired');
  expect(settings.containsKey(CmsRehearsalRepository.currentKey), isFalse);
}

Future<CmsRehearsalAttempt> _fillWritten(
  CmsRehearsalRepository r,
  CmsRehearsalAttempt a,
) async {
  for (final q in a.mcqs) {
    a = await r.answerMcq(a.id, q.id, q.correctOptionId);
  }
  for (final q in a.written) {
    a = await r.answerWritten(
      a.id,
      q.id,
      'My own evidence, conditional reasoning, limitation and proposed action.',
    );
  }
  return a;
}

Future<CmsRehearsalAttempt> _fillTasting(
  CmsRehearsalRepository r,
  CmsRehearsalAttempt a,
) async {
  a = await _fillWritten(r, a);
  for (var wine = 0; wine < 2; wine++) {
    for (final key in _keys) {
      a = await r.chooseObservation(a.id, wine, key, {
        wine == 0 ? 'first' : 'second',
      });
    }
    for (final p in a.wineEvidencePrompts) {
      a = await r.writeWineEvidence(
        a.id,
        wine,
        p.id,
        'Wine ${wine + 1} observed evidence; hypothesis is tentative.',
      );
    }
  }
  return r.acknowledgePhysical(a.id, true);
}

Future<CmsRehearsalAttempt> _review(
  CmsRehearsalRepository r,
  CmsRehearsalAttempt a,
) async {
  a = await r.finish(a.id);
  for (final q in a.written) {
    a = await r.selfAssess(
      a.id,
      q.id,
      {},
      improvement: 'I need clearer observation-linked evidence and a more precise limitation.',
    );
  }
  return r.review(a.id);
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late CmsRehearsalBank bank;
  late CmsRehearsalRepository repository;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await _seedGrid(db);
    bank = _fixtureBank();
    repository = CmsRehearsalRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(17),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
  });
  tearDown(() => db.close());

  test(
    'independent app presets preserve WSET profile and opaque saved bytes',
    () async {
      const wsetPointer = 'wset_rehearsal_current_v1';
      const wsetKey = 'wset_rehearsal_attempt_v1_saved';
      const wsetBytes = 'Existing WSET recovery bytes stay exact.';
      await _put(db, wsetPointer, 'saved', time.now);
      await _put(db, wsetKey, wsetBytes, time.now);
      for (final section in CmsRehearsalSection.values) {
        final a = await repository.start(section);
        expect(
          a.deadline.difference(a.startedAt),
          Duration(seconds: section.durationSeconds),
        );
        expect(a.section, section);
        expect(a.toJson()['trackId'], 'CMS_CERTIFIED');
        expect(
          a.mcqs,
          hasLength(section == CmsRehearsalSection.theory ? 10 : 0),
        );
        expect(
          a.written,
          hasLength(
            section == CmsRehearsalSection.theory
                ? 10
                : section == CmsRehearsalSection.service
                ? 3
                : 1,
          ),
        );
        expect(
          a.wines,
          hasLength(section == CmsRehearsalSection.tasting ? 2 : 0),
        );
        await repository.discardCurrent(expectedId: a.id);
      }
      final rows = await _settings(db);
      expect(rows[wsetPointer], 'saved');
      expect(rows[wsetKey], wsetBytes);
      final profile = await db.select(db.userProfiles).getSingle();
      expect(profile.activeCertificationId, 'WSET_L3');
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(await db.select(db.reviewStates).get(), isEmpty);
      expect(rows.keys.any((k) => k.startsWith('exam_pass_')), isFalse);
    },
  );

  test(
    'concurrent starts have one winner, one rejection and no orphan snapshot',
    () async {
      Future<Object> startOrError() async {
        try {
          return await repository.start(CmsRehearsalSection.theory);
        } catch (e) {
          return e;
        }
      }

      final outcomes = await Future.wait([startOrError(), startOrError()]);
      final winner = outcomes.whereType<CmsRehearsalAttempt>().single;
      expect(outcomes.whereType<StateError>(), hasLength(1));
      final rows = await _settings(db);
      expect(
        rows.keys.where(
          (k) => k.startsWith(CmsRehearsalRepository.attemptPrefix),
        ),
        hasLength(1),
      );
      expect(rows[CmsRehearsalRepository.currentKey], winner.id);
      expect(
        jsonDecode(rows[CmsRehearsalRepository.keyFor(winner.id)]!),
        winner.toJson(),
      );
      expect((await repository.current())!.id, winner.id);
    },
  );

  test(
    'saved snapshot resumes with its original bank, prose and deadline',
    () async {
      final started = await repository.start(CmsRehearsalSection.service);
      final saved = await repository.answerWritten(
        started.id,
        started.written.first.id,
        'An original saved decision.',
      );
      final before = await _settings(db);
      time.advance(const Duration(minutes: 4));
      final changedBankRow = _bankRow();
      changedBankRow['version'] = '9.9.9';
      for (final q in changedBankRow['mcqs'] as List) {
        q['itemIds'] = ['ki_chablis_grape'];
        q['prompt'] = 'A changed current-bank prompt.';
      }
      for (final q in changedBankRow['written'] as List) {
        q['prompt'] = 'A changed current-bank prompt.';
        for (final c in q['criteria'] as List) {
          c['itemIds'] = ['ki_chablis_grape'];
        }
      }
      final reopened = CmsRehearsalRepository(
        db,
        bank: CmsRehearsalBank.fromJson(jsonEncode(changedBankRow)),
        clock: time.clock,
      );
      final resumed = await reopened.resume(saved.id);
      expect(resumed.toJson(), saved.toJson());
      expect(resumed.bankVersion, '1.0.0');
      expect(resumed.remaining(time.now), const Duration(minutes: 11));
      expect(await _settings(db), before);
    },
  );

  test('finished history and rejected detached resume cannot steal the live pointer', () async {
    final first = await repository.start(CmsRehearsalSection.service);
    final completed = await repository.finish(first.id);
    final second = await repository.start(CmsRehearsalSection.tasting);
    expect((await repository.read(completed.id)).toJson(), completed.toJson());
    expect(
      (await repository.resume(completed.id)).toJson(),
      completed.toJson(),
    );
    expect((await repository.leaveFinished(completed.id))!.id, second.id);
    expect(await repository.currentPointer(), second.id);
    // Simulate a restored detached draft without discarding either saved row.
    await _delete(db, CmsRehearsalRepository.currentKey);
    final third = await repository.start(CmsRehearsalSection.theory);
    final before = await _settings(db);
    await expectLater(repository.resume(second.id), throwsStateError);
    expect(await _settings(db), before);
    expect((await repository.read(second.id)).toJson(), second.toJson());
    expect((await repository.current())!.id, third.id);
    await expectLater(
      repository.discardCurrent(expectedId: second.id),
      throwsStateError,
    );
    expect(await _settings(db), before);
  });

  test(
    'expiry persists before incomplete review and invalid self-review reject',
    () async {
      final draft = await repository.start(CmsRehearsalSection.service);
      time.advance(const Duration(minutes: 16));
      await expectLater(repository.review(draft.id), throwsStateError);
      await _expectExpiredBytes(db, draft);
      final expired = await repository.read(draft.id);
      expect(expired.completedAt, draft.deadline);
      expect(expired.finishReason, 'expired');
      expect(await repository.currentPointer(), isNull);
      final second = await repository.start(CmsRehearsalSection.service);
      await repository.answerWritten(
        second.id,
        second.written.first.id,
        'A saved response before the timer expires.',
      );
      time.advance(const Duration(minutes: 16));
      await expectLater(
        repository.selfAssess(second.id, second.written.first.id, {
          'unknown',
        }, improvement: 'I need to improve this specific answer.'),
        throwsFormatException,
      );
      await _expectExpiredBytes(db, second);
      final rejected = await repository.read(second.id);
      expect(rejected.completedAt, second.deadline);
      expect(rejected.finishReason, 'expired');
      expect(rejected.selfAssessment, isEmpty);
      expect(rejected.reviewNotes, isEmpty);
      expect(await repository.currentPointer(), isNull);
    },
  );

  test(
    'late oversized edits commit expiry and do not overwrite saved response',
    () async {
      final draft = await repository.start(CmsRehearsalSection.service);
      final saved = await repository.answerWritten(
        draft.id,
        draft.written.first.id,
        'Preserved before expiry.',
      );
      time.advance(const Duration(minutes: 16));
      await expectLater(
        repository.answerWritten(saved.id, saved.written.first.id, 'x' * 4001),
        throwsStateError,
      );
      await _expectExpiredBytes(db, saved);
      final expired = await repository.read(saved.id);
      expect(expired.completedAt, saved.deadline);
      expect(expired.prose, saved.prose);
      expect(await repository.currentPointer(), isNull);
      await expectLater(
        repository.selfAssess(
          saved.id,
          saved.written.first.id,
          {},
          improvement: 'x' * 4001,
        ),
        throwsArgumentError,
      );
      expect((await repository.read(saved.id)).toJson(), expired.toJson());
    },
  );

  test(
    'an insufficient new pool still commits the previous draft expiry',
    () async {
      final saved = await repository.start(CmsRehearsalSection.service);
      time.advance(const Duration(minutes: 16));
      final unavailable = CmsRehearsalRepository(
        db,
        bank: _fixtureBank(linked: 'ki_not_mapped'),
        clock: time.clock,
      );
      await expectLater(
        unavailable.start(CmsRehearsalSection.service),
        throwsStateError,
      );
      await _expectExpiredBytes(db, saved);
      final ended = await repository.read(saved.id);
      expect(ended.finishReason, 'expired');
      expect(ended.completedAt, saved.deadline);
      expect(await repository.currentPointer(), isNull);
      expect(
        (await _settings(db)).keys
            .where((k) => k.startsWith(CmsRehearsalRepository.attemptPrefix)),
        hasLength(1),
      );
    },
  );

  test(
    'invalid answers are atomic, and a partial finished packet earns no review',
    () async {
      final a = await repository.start(CmsRehearsalSection.theory);
      final before = await _settings(db);
      await expectLater(
        repository.answerMcq(a.id, a.mcqs.first.id, 'invalid'),
        throwsFormatException,
      );
      await expectLater(
        repository.answerWritten(a.id, 'unknown', 'An unrelated answer.'),
        throwsFormatException,
      );
      await expectLater(
        repository.answerWritten(a.id, a.written.first.id, 'x' * 4001),
        throwsArgumentError,
      );
      await expectLater(
        repository.selfAssess(
          a.id,
          a.written.first.id,
          {},
          improvement: 'This is premature.',
        ),
        throwsStateError,
      );
      expect(await _settings(db), before);
      final finished = await repository.finish(a.id);
      expect(finished.isComplete, isFalse);
      expect(await repository.currentPointer(), isNull);
      await expectLater(repository.review(a.id), throwsStateError);
      await expectLater(
        repository.answerMcq(
          a.id,
          a.mcqs.first.id,
          a.mcqs.first.correctOptionId,
        ),
        throwsStateError,
      );
      expect(
        CmsRehearsalEvidenceReader.read(
          await _settings(db),
          now: time.now,
        ).theoryReviewed,
        0,
      );
    },
  );

  test('zero checked criteria plus explicit improvement can record completed participation', () async {
    var a = await repository.start(CmsRehearsalSection.theory);
    a = await _fillWritten(repository, a);
    a = await repository.finish(a.id);
    expect(a.mcqCorrect, 10);
    await expectLater(repository.review(a.id), throwsStateError);
    for (final q in a.written) {
      a = await repository.selfAssess(
        a.id,
        q.id,
        {},
        improvement: 'I should give a clearer source-linked explanation.',
      );
    }
    a = await repository.review(a.id);
    expect(a.isReviewed, isTrue);
    expect(a.selfAssessment.values.every((v) => v.isEmpty), isTrue);
    expect(a.reviewNotes, hasLength(10));
    expect(a.toJson().containsKey('pass'), isFalse);
    expect(a.toJson().containsKey('writtenScore'), isFalse);
    final bytes = (await _settings(db))[CmsRehearsalRepository.keyFor(a.id)];
    await expectLater(
      repository.selfAssess(
        a.id,
        a.written.first.id,
        {},
        improvement: 'Another edit after final review.',
      ),
      throwsStateError,
    );
    await expectLater(repository.review(a.id), throwsStateError);
    expect((await _settings(db))[CmsRehearsalRepository.keyFor(a.id)], bytes);
    final evidence = CmsRehearsalEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.theoryReviewed, 1);
    expect(evidence.serviceReviewed, 0);
    expect(evidence.tastingReviewed, 0);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });

  test('two actual wines retain independent observations, physical acknowledgement and evidence', () async {
    var a = await repository.start(CmsRehearsalSection.tasting);
    final before = await _settings(db);
    await expectLater(
      repository.chooseObservation(a.id, 2, 'acid', {'first'}),
      throwsArgumentError,
    );
    await expectLater(
      repository.chooseObservation(a.id, 0, 'acid', {'first', 'second'}),
      throwsFormatException,
    );
    await expectLater(
      repository.chooseObservation(a.id, 0, 'unknown', {'first'}),
      throwsFormatException,
    );
    await expectLater(
      repository.writeWineEvidence(a.id, 0, 'unknown', 'Evidence'),
      throwsFormatException,
    );
    expect(await _settings(db), before);
    a = await _fillTasting(repository, a);
    expect(a.isComplete, isTrue);
    expect(a.wines[0].observations['acid'], {'first'});
    expect(a.wines[1].observations['acid'], {'second'});
    final reopened = CmsRehearsalRepository(
      db,
      bank: _fixtureBank(version: '2.0.0'),
      clock: time.clock,
    );
    expect((await reopened.resume(a.id)).toJson(), a.toJson());
    a = await _review(reopened, a);
    expect(a.isReviewed, isTrue);
    expect(a.wines.every((w) => w.isComplete), isTrue);
    expect(
      CmsRehearsalEvidenceReader.read(
        await _settings(db),
        now: time.now,
      ).tastingReviewed,
      1,
    );
    await expectLater(
      reopened.chooseObservation(a.id, 0, 'acid', {'second'}),
      throwsStateError,
    );
    await expectLater(
      reopened.acknowledgePhysical(a.id, false),
      throwsStateError,
    );
    expect(
      await db.select(db.tastingSessions).get(),
      isEmpty,
      reason: 'This saved snapshot must not write an unrelated tasting-session record.',
    );
  });

  test(
    'physical acknowledgement cannot substitute for missing wine evidence',
    () async {
      var a = await repository.start(CmsRehearsalSection.tasting);
      a = await _fillWritten(repository, a);
      a = await repository.acknowledgePhysical(a.id, true);
      a = await repository.finish(a.id);
      for (final q in a.written) {
        a = await repository.selfAssess(
          a.id,
          q.id,
          {},
          improvement: 'Add the actual wine observations.',
        );
      }
      expect(a.missingReasons, hasLength(2));
      await expectLater(repository.review(a.id), throwsStateError);
      expect(
        CmsRehearsalEvidenceReader.read(
          await _settings(db),
          now: time.now,
        ).tastingReviewed,
        0,
      );
    },
  );

  test(
    'guarded pointer recovery preserves malformed and absent-row bytes',
    () async {
      const raw = 'opaque invalid UUID pointer';
      const recoveryKey = 'cms_rehearsal_attempt_v1_recovery';
      const opaque = '{ private undecodable recovery bytes';
      await _put(db, CmsRehearsalRepository.currentKey, raw, time.now);
      await _put(db, recoveryKey, opaque, time.now);
      await expectLater(repository.current(), throwsFormatException);
      expect(await repository.currentPointer(), raw);
      await repository.resetCurrentPointer(expectedId: raw);
      expect(await repository.currentPointer(), isNull);
      expect((await _settings(db))[recoveryKey], opaque);
      final a = await repository.start(CmsRehearsalSection.service);
      await _delete(db, CmsRehearsalRepository.keyFor(a.id));
      await expectLater(repository.current(), throwsStateError);
      await repository.resetCurrentPointer(expectedId: a.id);
      expect(await repository.currentPointer(), isNull);
      expect((await _settings(db))[recoveryKey], opaque);
    },
  );

  test('stale recovery token and newly readable future record refuse pointer release', () async {
    const raw = 'broken-selection';
    await _put(db, CmsRehearsalRepository.currentKey, raw, time.now);
    await _delete(db, CmsRehearsalRepository.currentKey);
    final valid = await repository.start(CmsRehearsalSection.service);
    final before = await _settings(db);
    await expectLater(
      repository.resetCurrentPointer(expectedId: raw),
      throwsStateError,
    );
    expect(await _settings(db), before);
    await expectLater(
      repository.resetCurrentPointer(expectedId: valid.id),
      throwsStateError,
    );
    expect(await _settings(db), before);
    final future = valid.toJson();
    future['startedAt'] = time.now
        .add(const Duration(hours: 1))
        .toIso8601String();
    future['deadline'] = time.now
        .add(const Duration(hours: 1, minutes: 15))
        .toIso8601String();
    await _put(
      db,
      CmsRehearsalRepository.keyFor(valid.id),
      jsonEncode(future),
      time.now,
    );
    await expectLater(repository.current(), throwsFormatException);
    final futureBytes = (await _settings(
      db,
    ))[CmsRehearsalRepository.keyFor(valid.id)];
    time.advance(const Duration(hours: 1));
    await expectLater(
      repository.resetCurrentPointer(expectedId: valid.id),
      throwsStateError,
    );
    expect(await repository.currentPointer(), valid.id);
    expect(
      (await _settings(db))[CmsRehearsalRepository.keyFor(valid.id)],
      futureBytes,
    );
    expect((await repository.current())!.startedAt, time.now);
  });

  test('still-future recovery releases only pointer and retains undecodable history', () async {
    final a = await repository.start(CmsRehearsalSection.service);
    final row = a.toJson();
    row['startedAt'] = time.now.add(const Duration(hours: 2)).toIso8601String();
    row['deadline'] = time.now
        .add(const Duration(hours: 2, minutes: 15))
        .toIso8601String();
    final bytes = jsonEncode(row);
    await _put(db, CmsRehearsalRepository.keyFor(a.id), bytes, time.now);
    await repository.resetCurrentPointer(expectedId: a.id);
    expect(await repository.currentPointer(), isNull);
    expect((await _settings(db))[CmsRehearsalRepository.keyFor(a.id)], bytes);
    final history = await repository.historyWithDiagnostics();
    expect(history.entries, isEmpty);
    expect(history.unreadableCount, 1);
  });

  test('storage failure rolls back expiry and cannot be treated as damaged-record recovery', () async {
    final a = await repository.start(CmsRehearsalSection.service);
    time.advance(const Duration(minutes: 16));
    final before = await _settings(db);
    await db.customStatement(
      "CREATE TRIGGER cms_block_expiry BEFORE UPDATE ON user_settings WHEN OLD.name = '${CmsRehearsalRepository.keyFor(a.id)}' BEGIN SELECT RAISE(ABORT, 'injected CMS storage failure'); END",
    );
    Object? error;
    try {
      await repository.review(a.id);
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(error, isNot(isA<StateError>()));
    expect(error, isNot(isA<FormatException>()));
    expect(await _settings(db), before);
    await db.customStatement('DROP TRIGGER cms_block_expiry');
    expect((await repository.read(a.id)).finishReason, 'expired');
    const raw = 'broken-pointer';
    await _put(db, CmsRehearsalRepository.currentKey, raw, time.now);
    await db.customStatement(
      "CREATE TRIGGER cms_block_recovery BEFORE DELETE ON user_settings WHEN OLD.name = 'cms_rehearsal_current_v1' BEGIN SELECT RAISE(ABORT, 'injected CMS pointer deletion failure'); END",
    );
    error = null;
    try {
      await repository.resetCurrentPointer(expectedId: raw);
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(error, isNot(isA<StateError>()));
    expect(await repository.currentPointer(), raw);
    await db.customStatement('DROP TRIGGER cms_block_recovery');
    await repository.resetCurrentPointer(expectedId: raw);
    expect(await repository.currentPointer(), isNull);
  });

  test('snapshot guards enforce all dimensions, ordinal identity, vocabulary and review pairing', () async {
    final a = await repository.start(CmsRehearsalSection.tasting);
    Map<String, dynamic> fresh() =>
        Map<String, dynamic>.from(jsonDecode(jsonEncode(a.toJson())) as Map);
    final mutants = <Map<String, dynamic>>[];
    var row = fresh();
    row['schemaVersion'] = 2;
    mutants.add(row);
    row = fresh();
    row['id'] = '11111111-1111-1111-8111-111111111111';
    mutants.add(row);
    row = fresh();
    row['startedAt'] = '2026-01-01T09:00:00Z';
    mutants.add(row);
    row = fresh();
    row['trackId'] = 'WSET_L3';
    mutants.add(row);
    row = fresh();
    row['kind'] = 'wset_rehearsal';
    mutants.add(row);
    row = fresh();
    row['scopeUrl'] = 'https://example.invalid/other';
    mutants.add(row);
    row = fresh();
    row['deadline'] = a.deadline
        .add(const Duration(seconds: 1))
        .toIso8601String();
    mutants.add(row);
    row = fresh();
    row['startedAt'] = '2026-01-01T10:00:00.000+01:00';
    mutants.add(row);
    row = fresh();
    row['wines'][1]['ordinal'] = 0;
    mutants.add(row);
    row = fresh();
    row['wines'][0]['attributes'].removeLast();
    mutants.add(row);
    row = fresh();
    for (final w in row['wines'] as List<dynamic>) {
      for (final attribute in w['attributes'] as List<dynamic>) {
        attribute['isRequired'] = false;
      }
    }
    mutants.add(row);
    row = fresh();
    row['wines'][0]['observations'] = {
      'acid': ['not_in_vocabulary'],
    };
    mutants.add(row);
    row = fresh();
    row['wines'][0]['observations'] = {
      'fruit': ['first', 'first'],
    };
    mutants.add(row);
    row = fresh();
    row['wines'][1]['attributes'][0]['values'][0]['label'] =
        'Changed second wine vocabulary';
    mutants.add(row);
    row = fresh();
    row['wineEvidencePrompts'].removeLast();
    mutants.add(row);
    row = fresh();
    row['physicalAcknowledged'] = true;
    row['completedAt'] = a.startedAt.toIso8601String();
    row['finishReason'] = 'submitted';
    row['reviewedAt'] = a.startedAt.toIso8601String();
    mutants.add(row);
    for (final mutant in mutants) {
      expect(
        () => CmsRehearsalAttempt.fromJson(mutant),
        throwsA(
          anyOf(isA<FormatException>(), isA<TypeError>(), isA<StateError>()),
        ),
      );
    }
    final service = await repository.finish(a.id);
    expect(service.isReviewed, isFalse);
    final b = await repository.start(CmsRehearsalSection.service);
    final unpaired = b.toJson();
    unpaired['reviewNotes'] = {
      b.written.first.id: 'A note without a completed assessment.',
    };
    expect(() => CmsRehearsalAttempt.fromJson(unpaired), throwsFormatException);
    final invalidReviewed = b.toJson();
    invalidReviewed['reviewedAt'] = time.now.toIso8601String();
    expect(
      () => CmsRehearsalAttempt.fromJson(invalidReviewed),
      throwsFormatException,
    );
    expect(() => b.prose['x'] = 'Mutable?', throwsUnsupportedError);
    expect(() => b.written.add(b.written.first), throwsUnsupportedError);
    expect(() => a.wines[0].attributes.clear(), throwsUnsupportedError);
  });

  test('future, corrupt and mismatched identity cannot fabricate reviewed evidence', () async {
    var a = await repository.start(CmsRehearsalSection.service);
    a = await _fillWritten(repository, a);
    a = await _review(repository, a);
    final valid = await _settings(db);
    final key = CmsRehearsalRepository.keyFor(a.id);
    expect(
      CmsRehearsalEvidenceReader.read(valid, now: time.now).serviceReviewed,
      1,
    );
    final future = a.toJson();
    future['reviewedAt'] = time.now
        .add(const Duration(seconds: 1))
        .toIso8601String();
    var evidence = CmsRehearsalEvidenceReader.read({
      ...valid,
      key: jsonEncode(future),
    }, now: time.now);
    expect(evidence.serviceReviewed, 0);
    expect(evidence.unreadableCount, 1);
    evidence = CmsRehearsalEvidenceReader.read({
      ...valid,
      key: '{corrupt',
    }, now: time.now);
    expect(evidence.serviceReviewed, 0);
    expect(evidence.unreadableCount, 1);
    final otherKey = CmsRehearsalRepository.keyFor(
      '11111111-1111-4111-8111-111111111111',
    );
    evidence = CmsRehearsalEvidenceReader.read({
      otherKey: valid[key]!,
      'wset_rehearsal_attempt_v1_other': valid[key]!,
    }, now: time.now);
    expect(evidence.serviceReviewed, 0);
    expect(
      evidence.unreadableCount,
      1,
      reason: 'WSET namespaces are not consumed as CMS evidence.',
    );
    await _put(db, key, '{corrupt', time.now);
    final history = await repository.historyWithDiagnostics();
    expect(history.entries, isEmpty);
    expect(history.unreadableCount, 1);
    await expectLater(repository.read(a.id), throwsFormatException);
  });

  test('backup, memory reset, restore and erase preserve independent participation semantics', () async {
    var completed = await repository.start(CmsRehearsalSection.service);
    completed = await _fillWritten(repository, completed);
    completed = await _review(repository, completed);
    var draft = await repository.start(CmsRehearsalSection.theory);
    draft = await repository.answerWritten(
      draft.id,
      draft.written.first.id,
      'Private saved draft.',
    );
    const recoveryKey = 'cms_rehearsal_attempt_v1_recovery';
    const opaque = '{ original opaque imported recovery bytes';
    await _put(db, recoveryKey, opaque, time.now);
    final backup = UserDataBackup(db, clock: time.clock);
    final exported = await backup.exportJson();
    await backup.resetProgress();
    var evidence = CmsRehearsalEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.serviceReviewed, 1);
    expect(evidence.unreadableCount, 1);
    final restored = openTestDatabase();
    try {
      await seedCurriculum(restored);
      await _seedGrid(restored);
      final copy = UserDataBackup(restored, clock: time.clock);
      await copy.import(exported);
      final reopened = CmsRehearsalRepository(
        restored,
        bank: _fixtureBank(version: '3.0.0'),
        clock: time.clock,
      );
      expect((await reopened.read(completed.id)).toJson(), completed.toJson());
      expect((await reopened.current())!.toJson(), draft.toJson());
      final rows = await _settings(restored);
      expect(rows[recoveryKey], opaque);
      expect(rows[CmsRehearsalRepository.currentKey], draft.id);
      expect(await restored.select(restored.reviewEvents).get(), isEmpty);
      expect(await restored.select(restored.reviewStates).get(), isEmpty);
      expect(rows.keys.any((k) => k.startsWith('exam_pass_')), isFalse);
      await copy.eraseAll();
      final erased = await _settings(restored);
      expect(
        erased.keys.where(
          (k) => k.startsWith(CmsRehearsalRepository.attemptPrefix),
        ),
        isEmpty,
      );
      expect(erased.containsKey(CmsRehearsalRepository.currentKey), isFalse);
      evidence = CmsRehearsalEvidenceReader.read(erased, now: time.now);
      expect(evidence.serviceReviewed, 0);
      expect(evidence.unreadableCount, 0);
    } finally {
      await restored.close();
    }
  });
}
