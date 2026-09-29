import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

WsetScope testScope({
  List<WsetUnitScope> units = const [],
  bool complete = false,
}) => WsetScope([
  for (var level = 1; level <= 4; level++)
    WsetLevelScope(
      certificationId: 'WSET_L$level',
      title: 'WSET Level $level',
      curriculumComplete: complete,
      gaps: complete ? [] : ['Further content needed.'],
      sourceUrl: 'https://www.wsetglobal.com/',
      units: level == 4 ? units : [],
    ),
]);

void main() {
  late AppDatabase db;
  late TestClock time;
  late ReviewService reviews;
  late WsetProgressRepository progress;

  Future<WsetLevelProgress> level(int number) async =>
      (await progress.snapshot()).levels[number - 1];

  Future<void> review({
    String template = 'qt_ppg_fwd_flashcard',
    fsrs.Rating rating = fsrs.Rating.easy,
  }) async {
    await reviews.record(
      knowledgeItemId: 'ki_chablis_grape',
      questionTemplateId: template,
      rating: rating,
    );
  }

  Future<void> buildMastery() async {
    await review();
    time.advance(const Duration(days: 3));
    await review(template: 'qt_ppg_fwd_mcq');
    time.advance(const Duration(days: 4));
    await review(template: 'qt_ppg_rev_flashcard');
  }

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4','WSET',4,'WSET Level 4 Diploma','WSET_L3',NULL,1,'certification',NULL)",
        "INSERT INTO question_templates VALUES ('qt_ppg_fwd_flashcard','PERMITS_PRINCIPAL_GRAPE','forward','flashcard','en','Grape?','',NULL), ('qt_ppg_rev_flashcard','PERMITS_PRINCIPAL_GRAPE','reverse','flashcard','en','Place?','',NULL)",
        "INSERT INTO questions VALUES ('ki_chablis_grape','qt_ppg_fwd_flashcard','PERMITS_PRINCIPAL_GRAPE','Grape?'), ('ki_chablis_grape','qt_ppg_rev_flashcard','PERMITS_PRINCIPAL_GRAPE','Place?')",
      ]),
    );
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
    );
    progress = WsetProgressRepository(
      db,
      scope: testScope(),
      clock: time.clock,
    );
  });
  tearDown(() => db.close());

  test('empty level has no percentage or completed milestone', () async {
    final result = await level(1);
    expect(result.counts.mapped, 0);
    expect(result.counts.studiedFraction, isNull);
    expect(result.counts.masteredFraction, isNull);
    expect(result.counts.availableMaterialMastered, isFalse);
    expect(result.appLevelComplete, isFalse);
    progress = WsetProgressRepository(
      db,
      scope: testScope(complete: true),
      clock: time.clock,
    );
    expect((await level(1)).appLevelComplete, isFalse);
  });

  test(
    'cumulative levels share item reviews without counting formats twice',
    () async {
      await review();
      final result = await progress.snapshot();
      expect(result.levels.map((entry) => entry.counts.available), [
        0,
        1,
        2,
        2,
      ]);
      expect(result.levels.map((entry) => entry.counts.studied), [0, 1, 1, 1]);
      expect((await level(2)).counts.mastered, 0);
      expect((await level(2)).nextItems.single.reason, 'Keep practising');
    },
  );

  test(
    'core question coverage is live, cumulative and separate from mastery',
    () async {
      final initial = await progress.snapshot();
      expect(
        [for (final level in initial.levels) level.corePracticeCoverage!.core],
        [0, 1, 2, 2],
      );
      expect(
        [
          for (final level in initial.levels)
            level.corePracticeCoverage!.useful,
        ],
        [0, 0, 0, 0],
      );
      expect(initial.levels[1].counts.mastered, 0);
      expect(initial.levels[2].corePracticeCoverage!.missingUsefulPractice, 2);
      expect(initial.levels[3].corePracticeCoverage!.complete, isFalse);

      await db.writeCurriculum(
        () => runSql(db, [
          "UPDATE certification_knowledge_mappings SET minimum_depth=2 WHERE certification_id='WSET_L2' AND knowledge_item_id='ki_chablis_grape'",
        ]),
      );
      final deeper = await progress.snapshot();
      expect(
        [for (final level in deeper.levels) level.corePracticeCoverage!.useful],
        [0, 1, 1, 1],
      );
      expect(deeper.levels[1].corePracticeCoverage!.complete, isTrue);
      expect(deeper.levels[2].corePracticeCoverage!.missingUsefulPractice, 1);

      await db.writeCurriculum(
        () => runSql(db, [
          "DELETE FROM questions WHERE knowledge_item_id='ki_chablis_grape' AND question_template_id='qt_ppg_fwd_mcq'",
        ]),
      );
      final changed = await progress.snapshot();
      expect(changed.levels[1].corePracticeCoverage!.core, 1);
      expect(changed.levels[1].corePracticeCoverage!.useful, 0);
      expect(changed.levels[2].corePracticeCoverage!.missingUsefulPractice, 2);
    },
  );

  test('repeated taps on one date cannot establish lasting mastery', () async {
    for (var i = 0; i < 4; i++) {
      await review();
      time.advance(const Duration(minutes: 1));
    }
    expect((await level(2)).counts.studied, 1);
    expect((await level(2)).counts.mastered, 0);
  });

  test('three successful dates must span at least seven days', () async {
    await review();
    time.advance(const Duration(days: 1));
    await review();
    time.advance(const Duration(days: 1));
    await review();
    expect((await level(2)).counts.mastered, 0);
  });

  test(
    'spaced mixed-format successes master material but not an incomplete level',
    () async {
      await buildMastery();
      final result = await level(2);
      expect(result.counts.mastered, 1);
      expect(result.counts.availableMaterialMastered, isTrue);
      expect(result.appLevelComplete, isFalse);
      expect((await level(4)).counts.mastered, 1);
      expect((await level(4)).nextItems.single.itemId, 'ki_chablis_soil');
    },
  );

  test('a reverse failure reduces mastery and history before that lapse cannot restore it', () async {
    await buildMastery();
    expect((await level(2)).counts.mastered, 1);
    time.advance(const Duration(minutes: 1));
    await review(template: 'qt_ppg_rev_flashcard', rating: fsrs.Rating.again);
    expect((await level(2)).counts.mastered, 0);
    time.advance(const Duration(minutes: 11));
    await review();
    expect((await level(2)).counts.mastered, 0);
    expect((await level(2)).counts.studied, 1);
  });

  test('memory decay can lower mastery without a new review', () async {
    await buildMastery();
    expect((await level(2)).counts.mastered, 1);
    time.advance(const Duration(days: 1000));
    expect((await level(2)).counts.mastered, 0);
    expect((await level(2)).counts.due, 1);
  });

  test(
    'mapped facts without a usable question stay visible as coverage gaps',
    () async {
      await db.writeCurriculum(
        () => runSql(db, [
          "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L4','ki_barolo_min_ageing','core',2,NULL)",
        ]),
      );
      final result = await level(4);
      expect(result.counts.mapped, 3);
      expect(result.counts.available, 2);
      expect(result.counts.unavailable, 1);
      expect(result.counts.studiedFraction, 0);
      expect(
        result.topics
            .singleWhere((topic) => topic.title == 'Geography')
            .counts
            .unavailable,
        1,
      );
    },
  );

  test(
    'expired current facts leave the denominator while reviews remain',
    () async {
      await buildMastery();
      await db.writeCurriculum(
        () => runSql(db, [
          "UPDATE knowledge_relations SET valid_until='2026-01-08' WHERE subject_id='n_geo_chablis' AND relation_type='PERMITS_PRINCIPAL_GRAPE'",
        ]),
      );
      expect((await level(2)).counts.mapped, 0);
      expect(await db.select(db.reviewEvents).get(), hasLength(3));
      expect((await level(2)).counts.masteredFraction, isNull);
    },
  );

  test('six Diploma groups partition counts; mixed-style geography selection is selective', () async {
    progress = WsetProgressRepository(
      db,
      clock: time.clock,
      scope: testScope(
        units: [
          for (var i = 1; i <= 6; i++)
            WsetUnitScope(
              id: 'D$i',
              title: 'Unit $i',
              gap: 'Expand unit.',
              domains: i == 1
                  ? ['viticulture']
                  : i == 3
                  ? ['geography']
                  : [],
              regionRoots: i == 4 ? ['n_geo_chablis'] : [],
              geographyRoots: i == 5 ? ['n_geo_barolo'] : [],
            ),
        ],
      ),
    );
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L4','ki_barolo_min_ageing','core',2,NULL)",
      ]),
    );
    final result = await level(4);
    expect(result.units, hasLength(6));
    expect(
      result.units[3].counts.mapped,
      2,
    ); // Regional support takes precedence.
    expect(
      result.units[2].counts.mapped,
      1,
    ); // Barolo ageing is not a location fact.
    expect(result.units[4].counts.mapped, 0);
    expect(result.units[5].counts.mapped, 0);
    expect(
      result.units.fold(0, (int sum, unit) => sum + unit.counts.mapped) +
          result.unassigned.mapped,
      result.counts.mapped,
    );
  });

  test('D1 written review appears as participation, not a pass', () async {
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    final writing = DiplomaWrittenRepository(
      db,
      bank: DiplomaWrittenBank.fromJson(
        File('assets/study/diploma_written_practice.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(29),
    );
    final d1 = await writing.start('D1');
    for (final question in d1.questions) {
      await writing.answer(
        d1.id,
        question.id,
        'Reasoned ${question.id} response.',
      );
    }
    await writing.finish(d1.id);
    for (final question in d1.questions) {
      await writing.review(
        d1.id,
        question.id,
        {},
        'I would add more evidence.',
      );
    }
    progress = WsetProgressRepository(
      db,
      scope: testScope(
        units: [
          for (var unit = 1; unit <= 6; unit++)
            WsetUnitScope(
              id: 'D$unit',
              title: 'Unit $unit',
              gap: 'Further study remains.',
              domains: const [],
            ),
        ],
      ),
      clock: time.clock,
    );
    final diploma = (await progress.snapshot()).levels.last;
    expect(diploma.units[0].writtenPractices, 1);
    expect(diploma.units[1].writtenPractices, 0);
    expect(diploma.examPassed, isFalse);
    expect(diploma.appLevelComplete, isFalse);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test('D4 physical flights count only as unit participation', () async {
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO tasting_grids VALUES ('tg_structured', 'WSET_SAT', '1.0', 'Structured tasting')",
        "INSERT INTO tasting_grid_attributes VALUES ('tg_structured', 'sweetness', 'Taste', 'Sweetness', 1, 'single', 1)",
        "INSERT INTO tasting_grid_values VALUES ('tg_structured', 'sweetness', 'dry', 'Dry', 1, NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    final bank = DiplomaTastingBank.fromJson(
      File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
    );
    final flights = DiplomaTastingFlightRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(11),
    );
    final d4 = await flights.start('D4');
    await flights.start('D5');
    for (var wine = 0; wine < 3; wine++) {
      await flights.acknowledgePhysical(d4.id, wine, true);
      await flights.choose(d4.id, wine, 'sweetness', {'dry'});
      for (final prompt in d4.wines[wine].prompts) {
        await flights.saveEvidence(
          d4.id,
          wine,
          prompt.id,
          'Observed physical sparkling wine ${wine + 1}.',
        );
      }
    }
    await flights.saveReflection(d4.id, 'Compared the three real wines.');
    await flights.saveSelfReview(
      d4.id,
      'Reviewed what each observation supports.',
    );
    await flights.markSelfReviewed(d4.id);
    await flights.finish(d4.id);
    progress = WsetProgressRepository(
      db,
      scope: testScope(
        units: [
          for (var unit = 1; unit <= 6; unit++)
            WsetUnitScope(
              id: 'D$unit',
              title: 'Unit $unit',
              gap: 'Practice in progress.',
              domains: const [],
            ),
        ],
      ),
      clock: time.clock,
    );
    final snapshot = await progress.snapshot();
    final diploma = snapshot.levels.last;
    expect(diploma.units[3].physicalFlights, 1);
    expect(diploma.units[4].physicalFlights, 0, reason: 'D5 is still a draft');
    expect(await flights.current('D5'), isNotNull);
    expect(diploma.appLevelComplete, isFalse);
    expect(diploma.examPassed, isFalse);
    expect(snapshot.levels.first.units, isEmpty);
  });

  test(
    'stale region selector fails visibly instead of silently dropping facts',
    () async {
      progress = WsetProgressRepository(
        db,
        clock: time.clock,
        scope: testScope(
          units: [
            for (var i = 1; i <= 6; i++)
              WsetUnitScope(
                id: 'D$i',
                title: 'Unit $i',
                gap: '',
                regionRoots: i == 4 ? ['n_geo_missing'] : [],
              ),
          ],
        ),
      );
      await expectLater(progress.snapshot(), throwsFormatException);
    },
  );

  test('explicit product lessons override region and domain without double counting', () async {
    progress = WsetProgressRepository(
      db,
      clock: time.clock,
      scope: testScope(
        units: [
          for (var i = 1; i <= 6; i++)
            WsetUnitScope(
              id: 'D$i',
              title: 'Unit $i',
              gap: '',
              domains: i == 1
                  ? ['viticulture']
                  : i == 3
                  ? ['geography']
                  : [],
              regionRoots: i == 4 ? ['n_geo_chablis'] : [],
              itemIds: i == 5 ? ['ki_chablis_soil'] : [],
            ),
        ],
      ),
    );
    final result = await level(4);
    expect(result.units[0].counts.mapped, 0);
    expect(result.units[3].counts.mapped, 1);
    expect(result.units[4].counts.mapped, 1);
    expect(
      result.units.fold(0, (int n, u) => n + u.counts.mapped) +
          result.unassigned.mapped,
      result.counts.mapped,
    );
    await db.writeCurriculum(
      () => runSql(db, [
        "UPDATE knowledge_relations SET valid_until='2026-01-01' WHERE subject_id='n_geo_chablis' AND relation_type='HAS_SOIL'",
      ]),
    );
    // Retiring a referenced item is valid, but it no longer contributes.
    expect((await level(4)).units[4].counts.mapped, 0);
    expect((await level(4)).counts.mapped, 1);
  });

  test(
    'unknown explicit item fails visibly even when it is unmapped',
    () async {
      progress = WsetProgressRepository(
        db,
        clock: time.clock,
        scope: testScope(
          units: [
            for (var i = 1; i <= 6; i++)
              WsetUnitScope(
                id: 'D$i',
                title: 'Unit $i',
                gap: '',
                itemIds: i == 5 ? ['ki_missing'] : [],
              ),
          ],
        ),
      );
      await expectLater(progress.snapshot(), throwsFormatException);
    },
  );

  test('self-reported exam pass is independent, reversible, backed up and reset safely', () async {
    await progress.setExamPassed('WSET_L1', true);
    expect((await level(1)).examPassed, isTrue);
    expect((await level(1)).counts.mastered, 0);
    expect((await level(1)).appLevelComplete, isFalse);
    final backup = UserDataBackup(db, clock: time.clock);
    final exported = await backup.exportJson();
    await progress.setExamPassed('WSET_L1', false);
    expect((await level(1)).examPassed, isFalse);
    await backup.import(exported);
    expect((await level(1)).examPassed, isTrue);
    await backup.resetProgress();
    expect((await level(1)).examPassed, isTrue);
    await backup.eraseAll();
    expect((await level(1)).examPassed, isFalse);
    await expectLater(
      progress.setExamPassed('CMS_CERTIFIED', true),
      throwsArgumentError,
    );
  });

  test(
    'app milestone requires nonempty fully available reviewed scope',
    () async {
      progress = WsetProgressRepository(
        db,
        scope: testScope(complete: true),
        clock: time.clock,
      );
      await buildMastery();
      expect((await level(2)).appLevelComplete, isTrue);
      expect((await level(3)).appLevelComplete, isFalse);
      expect((await level(2)).examPassed, isFalse);
    },
  );

  test('bundled Levels 1–3 are reviewed; Diploma keeps six open groups', () {
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    expect(scope.levels, hasLength(4));
    expect(
      scope.levels.take(3).every((level) => level.curriculumComplete),
      isTrue,
    );
    expect(
      scope.levels
          .take(3)
          .every(
            (level) =>
                level.gaps.isEmpty &&
                level.requirements.every((requirement) => requirement.reviewed),
          ),
      isTrue,
    );
    expect(scope.levels.last.curriculumComplete, isFalse);
    expect(scope.levels.last.units.map((unit) => unit.id), [
      'D1',
      'D2',
      'D3',
      'D4',
      'D5',
      'D6',
    ]);
  });

  test(
    'scope parser rejects contradictory completion, duplicate or unknown units',
    () {
      final json = jsonDecode(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final levels = json['levels'] as List<dynamic>;
      final firstLevel = levels.first as Map<String, dynamic>;
      final firstRequirement =
          (firstLevel['requirements'] as List).first as Map<String, dynamic>;
      firstRequirement['reviewed'] = false;
      expect(() => WsetScope.fromJson(jsonEncode(json)), throwsFormatException);
      firstRequirement['reviewed'] = true;
      firstLevel['curriculumComplete'] = false;
      final units =
          (levels.last as Map<String, dynamic>)['units'] as List<dynamic>;
      (units.last as Map<String, dynamic>)['id'] = 'D1';
      expect(() => WsetScope.fromJson(jsonEncode(json)), throwsFormatException);
      (units.last as Map<String, dynamic>)['id'] = 'D7';
      expect(() => WsetScope.fromJson(jsonEncode(json)), throwsFormatException);
    },
  );

  test('scope rejects invalid and repeated item selectors across units', () {
    Map<String, dynamic> json() =>
        jsonDecode(File('assets/progress/wset_scope.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final invalid in [
      null,
      'ki_example',
      [42],
      [''],
      [' ki_example'],
      ['n_example'],
      ['ki_example', 'ki_example'],
    ]) {
      final value = json();
      final units = (value['levels'] as List).last['units'] as List;
      units.first['itemIds'] = invalid;
      expect(
        () => WsetScope.fromJson(jsonEncode(value)),
        throwsFormatException,
        reason: '$invalid',
      );
    }
    final value = json();
    final units = (value['levels'] as List).last['units'] as List;
    units.first['itemIds'] = ['ki_shared'];
    units.last['itemIds'] = ['ki_shared'];
    expect(() => WsetScope.fromJson(jsonEncode(value)), throwsFormatException);
  });
}
