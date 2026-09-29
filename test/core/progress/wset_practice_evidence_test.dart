import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/progress/wset_practice_evidence.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/tasting_pair/tasting_pair.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
import '../rehearsal/rehearsal_fixture.dart';
import '../tasting_guidance/guided_tasting_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late GuidedTastingRepository guidance;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L1');
    guidance = GuidedTastingRepository(
      db,
      bank: guidedTastingFixtureBank(),
      clock: time.clock,
    );
  });
  tearDown(() => db.close());
  Future<WsetPracticeEvidence> evidence(
    int level, {
    bool available = true,
  }) async => WsetPracticeEvidenceReader(db).read(
    level,
    {for (final s in await db.select(db.userSettings).get()) s.name: s.value},
    now: time.clock.now(),
    currentItems: available ? {'ki_chablis_grape'} : {},
    mappedItems: {'ki_chablis_grape'},
  );
  Future<void> completeGuided(GuidedTastingRecord record) async {
    await guidance.choose(record.sessionId, 'sweetness', {'dry'});
    for (final prompt in record.level.evidencePrompts) {
      await guidance.evidence(
        record.sessionId,
        prompt.id,
        'Specific observed evidence.',
      );
    }
    await guidance.finish(record.sessionId);
  }

  test(
    'fact mastery alone cannot complete a milestone with missing activities',
    () {
      const mastered = ProgressCounts(
        mapped: 1,
        available: 1,
        studied: 1,
        mastered: 1,
        due: 0,
      );
      const level = WsetLevelProgress(
        scope: WsetLevelScope(
          certificationId: 'WSET_L1',
          title: 'Level 1',
          curriculumComplete: true,
          gaps: [],
          sourceUrl: 'https://www.wsetglobal.com/',
          practice: WsetPracticeRequirements(
            rehearsal: true,
            calibrationCases: 3,
            physicalWines: 1,
          ),
        ),
        counts: mastered,
        selectable: true,
        examPassed: false,
        topics: [],
        nextItems: [],
        units: [],
        unassigned: mastered,
      );
      expect(level.appLevelComplete, isFalse);
      expect(
        const WsetPracticeEvidence(
          rehearsals: 1,
          calibrationCases: 3,
          physicalWines: 1,
        ).satisfies(level.scope.practice),
        isTrue,
      );
      expect(
        const WsetPracticeRequirements(calibrationCases: -1).validate,
        throwsFormatException,
      );
    },
  );
  test(
    'original rehearsal participation requires all answers and current links',
    () async {
      final rehearsal = RehearsalRepository(
        db,
        bank: rehearsalFixtureBank(),
        clock: time.clock,
        random: Random(1),
      );
      final attempt = await rehearsal.start(1);
      await rehearsal.answerMcq(
        attempt.id,
        attempt.mcqs.first.id,
        attempt.mcqs.first.correctOptionId,
      );
      expect((await evidence(1)).rehearsals, 0);
      for (final q in attempt.mcqs.skip(1)) {
        await rehearsal.answerMcq(attempt.id, q.id, q.correctOptionId);
      }
      await rehearsal.finish(attempt.id);
      expect((await evidence(1)).rehearsals, 1);
      expect((await evidence(2)).rehearsals, 0);
      expect((await evidence(1, available: false)).rehearsals, 0);
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: '${RehearsalRepository.attemptPrefix}broken',
              value: 'corrupt',
              updatedAt: time.clock.now(),
            ),
          );
      final recovered = await evidence(1);
      expect(recovered.rehearsals, 1);
      expect(recovered.unreadableRecords, 1);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );
  test('written participation requires saved prose and explicit review of all responses', () async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final rehearsal = RehearsalRepository(
      db,
      bank: rehearsalFixtureBank(),
      clock: time.clock,
      random: Random(2),
    );
    final attempt = await rehearsal.start(3);
    for (final q in attempt.written) {
      await rehearsal.answerWritten(
        attempt.id,
        q.id,
        'Original explanation with specific evidence.',
      );
    }
    await rehearsal.finish(attempt.id);
    expect((await evidence(3)).writtenReviews, 0);
    for (final q in attempt.written) {
      await rehearsal.selfAssess(attempt.id, q.id, {});
    }
    expect(
      (await evidence(3)).writtenReviews,
      1,
      reason: 'Honest review may identify no supported criteria; it does not award a pass.',
    );
    expect((await evidence(3)).rehearsals, 0);
  });
  test('calibration counts distinct cases while physical wines retain actual evidence', () async {
    final first = await guidance.start(1, caseId: 'case_l1');
    await completeGuided(first);
    await guidance.leaveCurrent();
    final repeated = await guidance.start(1, caseId: 'case_l1');
    await completeGuided(repeated);
    await guidance.leaveCurrent();
    final physical = await guidance.start(1);
    await completeGuided(physical);
    expect((await evidence(1)).calibrationCases, 1);
    expect((await evidence(1)).physicalWines, 1);
    expect((await evidence(1, available: false)).calibrationCases, 0);
    await TastingPractice(
      db,
      clock: time.clock,
    ).choose(physical.sessionId, 'sweetness', {'off_dry'});
    expect(
      (await evidence(1)).physicalWines,
      0,
      reason: 'Legacy edits must not retain stale guided completion evidence.',
    );
  });
  test('invalid saved reference vocabulary earns no calibration participation', () async {
    final corrupt = <String, String>{};
    for (final invalidAttribute in [true, false]) {
      final record = await guidance.start(1, caseId: 'case_l1');
      await completeGuided(record);
      final row = (await guidance.read(record.sessionId)).toJson();
      await guidance.leaveCurrent();
      final reference =
          (row['calibration']['referenceObservations'] as List).first
              as Map<String, dynamic>;
      if (invalidAttribute) {
        reference['attributeKey'] = 'missing_attribute';
      } else {
        reference['valueKeys'] = ['missing_value'];
      }
      final key =
          '${GuidedTastingRepository.recordPrefix}${record.sessionId.replaceAll('-', '_')}';
      corrupt[key] = jsonEncode(row);
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(name: key, value: corrupt[key]!, updatedAt: time.now),
          );
    }
    final physical = await guidance.start(1);
    await completeGuided(physical);
    final recovered = await evidence(1);
    expect(recovered.calibrationCases, 0);
    expect(recovered.physicalWines, 1);
    expect(recovered.unreadableRecords, 2);
    await guidance.leaveCurrent();
    await completeGuided(await guidance.start(1, caseId: 'case_l1'));
    expect((await evidence(1)).calibrationCases, 1);
    final raw = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    for (final entry in corrupt.entries) {
      expect(raw[entry.key], entry.value);
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });
  test('paired participation requires both wines; legacy edits cannot rewrite its snapshot', () async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final pairs = TastingPairRepository(
      db,
      guidance: guidance,
      clock: time.clock,
      random: Random(3),
    );
    final first = await pairs.start();
    await pairs.finish(first.id);
    expect((await evidence(3)).pairedTastings, 0);
    final sameColour = await pairs.start();
    for (final wine in sameColour.wines) {
      await pairs.choose(sameColour.id, wine.sessionId, 'sweetness', {'dry'});
      await pairs.choose(sameColour.id, wine.sessionId, 'colour', {'white'});
      for (final prompt in wine.level.evidencePrompts) {
        await pairs.evidence(
          sameColour.id,
          wine.sessionId,
          prompt.id,
          'Observed structural and flavour evidence.',
        );
      }
    }
    final savedSameColour = await pairs.finish(sameColour.id);
    expect(savedSameColour.completeWineCount, 2);
    expect(savedSameColour.hasWhiteAndRedWines, isFalse);
    expect((await evidence(3)).pairedTastings, 0);
    final complete = await pairs.start();
    for (var index = 0; index < complete.wines.length; index++) {
      final wine = complete.wines[index];
      await pairs.choose(complete.id, wine.sessionId, 'sweetness', {'dry'});
      await pairs.choose(complete.id, wine.sessionId, 'colour', {
        index == 0 ? 'white' : 'red',
      });
      for (final prompt in wine.level.evidencePrompts) {
        await pairs.evidence(
          complete.id,
          wine.sessionId,
          prompt.id,
          'Observed structural and flavour evidence.',
        );
      }
    }
    final savedComplete = await pairs.finish(complete.id);
    expect(savedComplete.hasWhiteAndRedWines, isTrue);
    expect(
      TastingPairAttempt.fromJson({
        ...savedComplete.toJson(),
        'wines': [
          for (final wine in savedComplete.wines.reversed) wine.toJson(),
        ],
      }).hasWhiteAndRedWines,
      isTrue,
      reason: 'The white and red glasses may be tasted in either order.',
    );
    expect((await evidence(3)).pairedTastings, 1);
    expect(
      (await evidence(3)).physicalWines,
      0,
      reason:
          'Linked guidance stays draft; this avoids double counting activity.',
    );
    await TastingPractice(
      db,
      clock: time.clock,
    ).choose(complete.wines.first.sessionId, 'sweetness', {'off_dry'});
    expect((await evidence(3)).pairedTastings, 1);
  });

  test('database read failures propagate without discarding malformed snapshots', () async {
    final physical = await guidance.start(1);
    await completeGuided(physical);
    final saved = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    // Read damaged imported data first: it must not mask the later SQL error.
    final settings = {
      '${GuidedTastingRepository.recordPrefix}broken': 'corrupt',
      ...saved,
    };
    Future<WsetPracticeEvidence> read() => WsetPracticeEvidenceReader(db).read(
      1,
      settings,
      now: time.clock.now(),
      currentItems: {'ki_chablis_grape'},
      mappedItems: {'ki_chablis_grape'},
    );
    final before = await read();
    expect(before.physicalWines, 1);
    expect(before.unreadableRecords, 1);

    // This isolated in-memory database simulates an unavailable observation
    // table; the reader must surface the actual SQLite failure to progress UI.
    await db.customStatement(
      'ALTER TABLE tasting_descriptors RENAME TO evidence_descriptors_unavailable',
    );
    try {
      await expectLater(read(), throwsA(isA<SqliteException>()));
    } finally {
      await db.customStatement(
        'ALTER TABLE evidence_descriptors_unavailable RENAME TO tasting_descriptors',
      );
    }

    final recovered = await read();
    expect(recovered.physicalWines, 1);
    expect(recovered.unreadableRecords, 1);
    expect(
      settings['${GuidedTastingRepository.recordPrefix}broken'],
      'corrupt',
    );
    expect(
      {
        for (final row in await db.select(db.userSettings).get())
          row.name: row.value,
      },
      saved,
      reason: 'Reading progress must not rewrite practice snapshots.',
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test(
    'a legacy tasting edit immediately refreshes watched activity progress',
    () async {
      await db.writeCurriculum(
        () => runSql(db, [
          "INSERT INTO certifications VALUES ('WSET_L4','WSET',4,'WSET Level 4 Diploma','WSET_L3',NULL,1,'certification',NULL)",
        ]),
      );
      final physical = await guidance.start(1);
      await completeGuided(physical);
      final scope = WsetScope([
        for (var level = 1; level <= 4; level++)
          WsetLevelScope(
            certificationId: 'WSET_L$level',
            title: 'Level $level',
            curriculumComplete: false,
            gaps: [],
            sourceUrl: 'https://www.wsetglobal.com/',
          ),
      ]);
      final progress = WsetProgressRepository(
        db,
        scope: scope,
        clock: time.clock,
      );
      final first = Completer<WsetProgressSnapshot>();
      final changed = Completer<WsetProgressSnapshot>();
      final subscription = progress.watch().listen((snapshot) {
        if (!first.isCompleted) {
          first.complete(snapshot);
        } else if (snapshot.levels.first.practiceEvidence.physicalWines == 0 &&
            !changed.isCompleted) {
          changed.complete(snapshot);
        }
      });
      addTearDown(subscription.cancel);
      expect(
        (await first.future.timeout(const Duration(seconds: 5)))
            .levels
            .first
            .practiceEvidence
            .physicalWines,
        1,
      );
      await TastingPractice(
        db,
        clock: time.clock,
      ).choose(physical.sessionId, 'sweetness', {'off_dry'});
      expect(
        (await changed.future.timeout(const Duration(seconds: 5)))
            .levels
            .first
            .practiceEvidence
            .physicalWines,
        0,
      );
    },
  );
}
