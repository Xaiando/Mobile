import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_evidence.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/tasting_pair/tasting_pair.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
import '../tasting_guidance/guided_tasting_fixture.dart';

import 'package:sommelier/core/diploma_tasting/d3_tasting_paper.dart';

Future<void> seedPaper(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO tasting_grids VALUES ('tg_structured', 'WSET_SAT', '1.0', 'Structured tasting')",
    "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', 'tg_structured', 1, 'certification', NULL)",
    "INSERT INTO tasting_grid_attributes VALUES ('tg_structured', 'sweetness', 'Taste', 'Sweetness', 1, 'single', 1), ('tg_structured', 'aromas', 'Smell', 'Aromas', 2, 'multi', 0)",
    "INSERT INTO tasting_grid_values VALUES ('tg_structured', 'sweetness', 'dry', 'Dry', 1, NULL), ('tg_structured', 'sweetness', 'sweet', 'Sweet', 2, NULL), ('tg_structured', 'aromas', 'citrus', 'Citrus', 1, NULL), ('tg_structured', 'aromas', 'bready', 'Bread', 2, NULL)",
  ]),
);
Future<Map<String, String>> settings(AppDatabase db) async => {
  for (final s in await db.select(db.userSettings).get()) s.name: s.value,
};
Future<void> completeWines(
  D3TastingPaperRepository r,
  D3TastingPaper paper,
) async {
  for (var i = 0; i < 6; i++) {
    await r.markTasted(paper.id, i, true);
    await r.observation(paper.id, i, 'sweetness', {'dry'});
    for (final p in paper.wines[i].prompts) {
      await r.answer(
        paper.id,
        i,
        p.id,
        'Wine ${i + 1}: distinct observed evidence for ${p.id}.',
      );
    }
  }
  for (var i = 0; i < paper.groupComparisons.length; i++) {
    await r.comparison(
      paper.id,
      i,
      'Comparison ${i + 1}: evidence differs; blind identity remains conditional.',
    );
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaTastingBank bank;
  late D3TastingPaperRepository repository;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedPaper(db);
    bank = DiplomaTastingBank.fromJson(
      File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
    );
    repository = D3TastingPaperRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(74),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
  });
  tearDown(() => db.close());

  test('grouped and mixed papers independently have six physical wines and absolute 90 minutes', () async {
    final grouped = await repository.start(D3TastingPaperKind.grouped);
    expect(grouped.wines, hasLength(6));
    expect(grouped.comparisonPrompts, hasLength(2));
    expect(grouped.deadline, t0.add(const Duration(minutes: 90)));
    expect(grouped.remaining(t0), const Duration(minutes: 90));
    expect(
      grouped.wines.every((w) => !w.physicallyTasted && !w.isComplete),
      isTrue,
    );
    expect(grouped.isReviewed, isFalse);
    await expectLater(
      repository.start(D3TastingPaperKind.mixed),
      throwsStateError,
    );
    await repository.abandon(grouped.id);
    final mixed = await repository.start(D3TastingPaperKind.mixed);
    expect(mixed.wines, hasLength(6));
    expect(mixed.groupComparisons, ['']);
    expect(mixed.comparisonPrompts.single, contains('without assuming'));
    expect(
      mixed.deadline.difference(mixed.startedAt),
      const Duration(minutes: 90),
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(await db.select(db.tastingSessions).get(), isEmpty);
  });
  test(
    'all repository access is gated to the selected Level 4 track',
    () async {
      final paper = await repository.start(D3TastingPaperKind.mixed);
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      for (final action in <Future<dynamic> Function()>[
        () => repository.start(D3TastingPaperKind.grouped),
        () => repository.current(),
        () => repository.read(paper.id),
        () => repository.resume(paper.id),
        () => repository.answer(
          paper.id,
          0,
          'description',
          'Hidden lower-track write',
        ),
        () => repository.finish(paper.id),
        () => repository.review(paper.id, 'Not allowed'),
        () => repository.historyWithDiagnostics(),
        () => repository.resetCurrentPointer(),
      ]) {
        await expectLater(action(), throwsStateError);
      }
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
      expect((await repository.current())!.toJson(), paper.toJson());
    },
  );
  test('all six distinct prose values, vocabulary and prompts survive later bank and grid changes', () async {
    final paper = await repository.start(D3TastingPaperKind.grouped);
    await completeWines(repository, paper);
    await repository.answer(
      paper.id,
      5,
      'description',
      'Latest private sixth wine response.',
    );
    await repository.observation(paper.id, 3, 'aromas', {'bready', 'citrus'});
    final snapshot = await repository.read(paper.id);
    final raw = jsonDecode(
      File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    raw['version'] = 'later.test';
    (raw['units'] as List).singleWhere(
          (u) => u['unitId'] == 'D3',
        )['evidencePrompts'][0]['prompt'] =
        'Later prompt does not rewrite history.';
    await db.writeCurriculum(
      () => runSql(db, [
        "UPDATE tasting_grid_attributes SET label = 'Later sweetness' WHERE tasting_grid_id = 'tg_structured' AND attribute_key = 'sweetness'",
        "DELETE FROM tasting_grid_values WHERE tasting_grid_id = 'tg_structured' AND attribute_key = 'aromas' AND value_key = 'citrus'",
      ]),
    );
    final later = D3TastingPaperRepository(
      db,
      bank: DiplomaTastingBank.fromJson(jsonEncode(raw)),
      clock: time.clock,
    );
    time.advance(const Duration(minutes: 7));
    expect((await later.current())!.toJson(), snapshot.toJson());
    expect((await later.resume(paper.id)).deadline, paper.deadline);
    expect(
      (await later.read(paper.id)).remaining(time.now),
      const Duration(minutes: 83),
    );
    expect(
      snapshot.wines[5].evidence['description'],
      'Latest private sixth wine response.',
    );
    await later.observation(paper.id, 3, 'aromas', {'citrus'});
    await later.answer(
      paper.id,
      0,
      'description',
      'Still uses the original saved prompt.',
    );
    expect(
      (await later.read(paper.id)).wines.first.prompts.first.prompt,
      paper.wines.first.prompts.first.prompt,
    );
  });
  test(
    'snapshots and serialized maps cannot mutate stored paper collections',
    () async {
      final paper = await repository.start(D3TastingPaperKind.grouped);
      expect(() => paper.wines.clear(), throwsUnsupportedError);
      expect(
        () => paper.wines.first.evidence['description'] = 'Injected',
        throwsUnsupportedError,
      );
      expect(
        () => paper.wines.first.attributes.first.values.clear(),
        throwsUnsupportedError,
      );
      expect(() => paper.comparisonPrompts.clear(), throwsUnsupportedError);
      await repository.observation(paper.id, 0, 'sweetness', {'dry'});
      final chosen = await repository.read(paper.id);
      expect(
        () => chosen.wines.first.observations['sweetness']!.add('sweet'),
        throwsUnsupportedError,
      );
      final row = chosen.toJson();
      (row['wines'] as List).first['evidence']['description'] =
          'Only a serialized copy';
      expect(chosen.wines.first.evidence, isEmpty);
      expect((await repository.read(paper.id)).wines.first.evidence, isEmpty);
    },
  );
  test('one millisecond before deadline accepts evidence and exact deadline rejects while committing expiry', () async {
    final paper = await repository.start(D3TastingPaperKind.mixed);
    time.advance(const Duration(minutes: 90) - const Duration(milliseconds: 1));
    await repository.answer(
      paper.id,
      0,
      'description',
      'Durable before deadline.',
    );
    time.advance(const Duration(milliseconds: 1));
    await expectLater(
      repository.answer(
        paper.id,
        0,
        'description',
        'Rejected at exact deadline.',
      ),
      throwsStateError,
    );
    final ended = await repository.read(paper.id);
    expect(ended.finishReason, 'expired');
    expect(ended.endedAt, paper.deadline);
    expect(
      ended.wines.first.evidence['description'],
      'Durable before deadline.',
    );
    expect(ended.isReviewed, isFalse);
    expect(ended.remaining(time.now), Duration.zero);
    expect(await repository.current(), isNull);
    final row = jsonDecode(
      (await settings(db))[D3TastingPaperRepository.keyFor(paper.id)]!,
    );
    expect(row['finishReason'], 'expired');
    expect(
      row['wines'][0]['evidence']['description'],
      'Durable before deadline.',
    );
  });
  test('late observations, physical declarations and comparisons never bypass expiry', () async {
    for (final mutation in <Future<D3TastingPaper> Function(String)>[
      (id) => repository.observation(id, 0, 'sweetness', {'dry'}),
      (id) => repository.markTasted(id, 0, true),
      (id) => repository.comparison(id, 0, 'Late comparison'),
    ]) {
      final paper = await repository.start(D3TastingPaperKind.mixed);
      time.advance(const Duration(minutes: 91));
      await expectLater(mutation(paper.id), throwsStateError);
      final ended = await repository.read(paper.id);
      expect(ended.finishReason, 'expired');
      expect(ended.wines.first.observations, isEmpty);
      expect(ended.wines.first.physicallyTasted, isFalse);
      expect(ended.groupComparisons, ['']);
    }
  });
  test('complete finished papers permit self-review only after timing ends; incomplete papers never count', () async {
    final paper = await repository.start(D3TastingPaperKind.grouped);
    await completeWines(repository, paper);
    await expectLater(
      repository.review(paper.id, 'Early review'),
      throwsStateError,
    );
    final ended = await repository.finish(paper.id);
    expect(ended.readyToReview, isTrue);
    expect(ended.isReviewed, isFalse);
    final reviewed = await repository.review(
      paper.id,
      'Actual tutor discussion exposed an uncertain identity and one next comparison task.',
    );
    expect(reviewed.isReviewed, isTrue);
    expect(reviewed.reviewedAt, time.now);
    expect((await repository.finish(paper.id)).toJson(), reviewed.toJson());
    await expectLater(
      repository.answer(paper.id, 0, 'quality', 'Change after ending'),
      throwsStateError,
    );
    final incomplete = await repository.start(D3TastingPaperKind.mixed);
    final partial = await repository.finish(incomplete.id);
    expect(partial.readyToReview, isFalse);
    await expectLater(
      repository.review(incomplete.id, 'Cannot count this incomplete paper.'),
      throwsStateError,
    );
    final evidence = D3TastingPaperEvidenceReader.read(
      await settings(db),
      now: time.now,
    );
    expect(evidence.reviewedGrouped, 1);
    expect(evidence.reviewedMixed, 0);
    expect(
      DiplomaTastingEvidenceReader.read(
        await settings(db),
        now: time.now,
      ).d3Flights,
      0,
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });
  test('complete expired paper can be reviewed; missing physical wine or comparison blocks participation', () async {
    final complete = await repository.start(D3TastingPaperKind.mixed);
    await completeWines(repository, complete);
    time.advance(const Duration(minutes: 90));
    final ended = await repository.read(complete.id);
    expect(ended.finishReason, 'expired');
    expect(
      (await repository.review(
        ended.id,
        'Private review after time expiry.',
      )).isReviewed,
      isTrue,
    );
    final incomplete = await repository.start(D3TastingPaperKind.grouped);
    await completeWines(repository, incomplete);
    await repository.markTasted(incomplete.id, 5, false);
    await repository.comparison(incomplete.id, 1, '');
    time.advance(const Duration(minutes: 90));
    await expectLater(
      repository.review(
        incomplete.id,
        'An expired partial paper cannot count.',
      ),
      throwsStateError,
    );
    expect((await repository.read(incomplete.id)).finishReason, 'expired');
    expect(
      D3TastingPaperEvidenceReader.read(
        await settings(db),
        now: time.now,
      ).totalReviewed,
      1,
    );
  });
  test(
    'abandoned and empty-review papers cannot produce participation',
    () async {
      final paper = await repository.start(D3TastingPaperKind.grouped);
      await completeWines(repository, paper);
      await repository.abandon(paper.id);
      await expectLater(
        repository.review(paper.id, 'Otherwise complete but abandoned'),
        throwsStateError,
      );
      expect((await repository.finish(paper.id)).finishReason, 'abandoned');
      final second = await repository.start(D3TastingPaperKind.mixed);
      await completeWines(repository, second);
      await repository.finish(second.id);
      await expectLater(repository.review(second.id, '   '), throwsStateError);
      expect(
        D3TastingPaperEvidenceReader.read(
          await settings(db),
          now: time.now,
        ).totalReviewed,
        0,
      );
    },
  );
  test('saved keys and values reject unknown prompts, values, index and oversized prose without writing', () async {
    final paper = await repository.start(D3TastingPaperKind.grouped);
    for (final invalid in <Future<dynamic> Function()>[
      () => repository.answer(paper.id, 0, 'unknown', 'Wrong prompt'),
      () => repository.answer(paper.id, 0, 'description', 'x' * 4001),
      () => repository.observation(paper.id, 0, 'missing', {}),
      () => repository.observation(paper.id, 0, 'sweetness', {'unknown'}),
      () => repository.observation(paper.id, 0, 'sweetness', {'dry', 'sweet'}),
      () => repository.answer(paper.id, 6, 'description', 'Invalid wine'),
      () => repository.comparison(paper.id, 2, 'Invalid group'),
    ]) {
      await expectLater(invalid(), throwsA(anything));
    }
    expect((await repository.read(paper.id)).toJson(), paper.toJson());
    await repository.observation(paper.id, 0, 'sweetness', {'dry'});
    await repository.observation(paper.id, 0, 'sweetness', {});
    await repository.answer(paper.id, 0, 'description', '');
    expect((await repository.read(paper.id)).wines.first.observations, isEmpty);
    expect(
      (await repository.read(paper.id)).wines.first.evidence['description'],
      '',
    );
  });
  test('repairing an active pointer preserves history and never lets an old finish orphan the new paper', () async {
    final old = await repository.start(D3TastingPaperKind.grouped);
    await repository.resetCurrentPointer();
    final newer = await repository.start(D3TastingPaperKind.mixed);
    await expectLater(repository.resume(old.id), throwsStateError);
    await repository.finish(old.id);
    expect((await repository.current())!.id, newer.id);
    expect(
      (await repository.historyWithDiagnostics()).entries
          .map((p) => p.id)
          .toSet(),
      {old.id, newer.id},
    );
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name: D3TastingPaperRepository.currentSetting,
            value: 'not_uuid',
            updatedAt: time.now,
          ),
        );
    await expectLater(repository.current(), throwsFormatException);
    await expectLater(
      repository.start(D3TastingPaperKind.mixed),
      throwsFormatException,
    );
    await repository.resetCurrentPointer();
    expect((await repository.resume(newer.id)).id, newer.id);
  });
  test('corrupt, wrong-key and future records are diagnosed, never counted, and a query failure propagates', () async {
    final paper = await repository.start(D3TastingPaperKind.mixed);
    await completeWines(repository, paper);
    await repository.finish(paper.id);
    final valid = await repository.review(
      paper.id,
      'A private physical-practice reflection.',
    );
    const corrupt = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const wrong = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const futureId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    final future = valid.toJson()..['id'] = futureId;
    for (final name in [
      'startedAt',
      'deadline',
      'updatedAt',
      'endedAt',
      'reviewedAt',
    ]) {
      future[name] = DateTime.parse(future[name] as String)
          .add(const Duration(days: 1))
          .toIso8601String();
    }
    for (final entry in {
      D3TastingPaperRepository.keyFor(corrupt): '{broken',
      D3TastingPaperRepository.keyFor(wrong): jsonEncode(valid.toJson()),
      D3TastingPaperRepository.keyFor(futureId): jsonEncode(future),
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
    final h = await repository.historyWithDiagnostics();
    expect(h.entries, hasLength(1));
    expect(h.unreadableCount, 3);
    final e = D3TastingPaperEvidenceReader.read(
      await settings(db),
      now: time.now,
    );
    expect(e.reviewedMixed, 1);
    expect(e.unreadableCount, 3);
    await expectLater(repository.read(futureId), throwsFormatException);
    await expectLater(repository.read(wrong), throwsFormatException);
    await db.customStatement('DROP TABLE user_settings');
    await expectLater(
      repository.historyWithDiagnostics(),
      throwsA(isA<SqliteException>()),
    );
  });
  test('invalid persisted snapshots cannot fabricate wine completion, review or altered timing', () async {
    final paper = await repository.start(D3TastingPaperKind.mixed);
    final edits = <void Function(Map<String, dynamic>)>[
      (r) => r['deadline'] = paper.deadline
          .add(const Duration(minutes: 1))
          .toIso8601String(),
      (r) => r['wines'] = (r['wines'] as List).sublist(0, 5),
      (r) => r['groupComparisons'] = ['', 'extra'],
      (r) => r['startedAt'] = '2026-01-01T09:00:00Z',
      (r) => r['updatedAt'] = '2026-01-01T09:00:00.000001Z',
      (r) => r['endedAt'] = paper.deadline.toIso8601String(),
      (r) {
        r['endedAt'] = paper.startedAt.toIso8601String();
        r['finishReason'] = 'submitted';
        r['reviewedAt'] = paper.startedAt.toIso8601String();
        r['selfReview'] = 'Fabricated review of incomplete wines';
      },
      (r) {
        r['endedAt'] = paper.startedAt.toIso8601String();
        r['finishReason'] = 'expired';
      },
      (r) => r['wines'][0]['observations']['sweetness'] = ['dry', 'dry'],
      (r) =>
          r['wines'][1]['prompts'][0]['prompt'] = 'Inconsistent wine snapshot',
    ];
    for (final edit in edits) {
      final row = paper.toJson();
      edit(row);
      expect(() => D3TastingPaper.fromJson(row), throwsA(anything));
    }
  });
  test('new six-wine paper and finished history survive actual backup export import and reset without lost prose', () async {
    final finished = await repository.start(D3TastingPaperKind.grouped);
    await completeWines(repository, finished);
    await repository.finish(finished.id);
    final reviewed = await repository.review(
      finished.id,
      'Saved physical comparison review.',
    );
    final active = await repository.start(D3TastingPaperKind.mixed);
    for (var i = 0; i < 6; i++) {
      await repository.answer(
        active.id,
        i,
        'description',
        'Private active wine ${i + 1}.',
      );
    }
    final snapshot = await repository.read(active.id);
    final backup = UserDataBackup(db, clock: time.clock);
    final text = await backup.exportJson();
    await backup.resetProgress();
    expect((await repository.current())!.toJson(), snapshot.toJson());
    final restored = openTestDatabase();
    try {
      await seedCurriculum(restored);
      await seedPaper(restored);
      await UserDataBackup(restored, clock: time.clock).import(text);
      final r = D3TastingPaperRepository(
        restored,
        bank: bank,
        clock: time.clock,
      );
      expect((await r.current())!.toJson(), snapshot.toJson());
      expect((await r.read(finished.id)).toJson(), reviewed.toJson());
      expect((await r.historyWithDiagnostics()).entries, hasLength(2));
      expect(
        D3TastingPaperEvidenceReader.read(
          await settings(restored),
          now: time.now,
        ).reviewedGrouped,
        1,
      );
      expect((await r.current())!.deadline, active.deadline);
    } finally {
      await restored.close();
    }
  });
  test('untimed three-wine flights and real Level 3 pairs retain separate keys, times and data', () async {
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final paired = TastingPairRepository(
      db,
      guidance: GuidedTastingRepository(
        db,
        bank: guidedTastingFixtureBank(),
        clock: time.clock,
      ),
      clock: time.clock,
    );
    final pair = await paired.start();
    expect(pair.wines, hasLength(2));
    expect(pair.level, 3);
    expect(
      pair.deadline.difference(pair.startedAt),
      const Duration(minutes: 30),
    );
    final pairSettings = (await settings(db)).entries
        .where(
          (e) =>
              e.key.startsWith(TastingPairRepository.attemptPrefix) ||
              e.key == TastingPairRepository.currentKey,
        )
        .toList();
    final sessions = (await db.select(db.tastingSessions).get())
        .map((s) => s.toJson())
        .toList();
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    final flights = DiplomaTastingFlightRepository(
      db,
      bank: bank,
      clock: time.clock,
    );
    final flight = await flights.start('D3');
    await flights.saveEvidence(
      flight.id,
      0,
      'description',
      'Original untimed flight retained.',
    );
    final flightSnapshot = await flights.read(flight.id);
    final paper = await repository.start(D3TastingPaperKind.mixed);
    await repository.answer(
      paper.id,
      5,
      'description',
      'New six-wine paper only.',
    );
    await repository.finish(paper.id);
    expect((await flights.current('D3'))!.toJson(), flightSnapshot.toJson());
    expect((await paired.read(pair.id)).toJson(), pair.toJson());
    expect(
      (await db.select(db.tastingSessions).get())
          .map((s) => s.toJson())
          .toList(),
      sessions,
    );
    final after = await settings(db);
    for (final e in pairSettings) {
      expect(after[e.key], e.value);
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });
}
