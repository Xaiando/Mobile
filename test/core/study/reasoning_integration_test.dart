import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/reasoning/reasoning_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late ReviewService reviews;
  late ExercisePresenter presenter;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(db, clock: time.clock).ingest(bundledDataset());
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(71),
    );
    presenter = ExercisePresenter(db, clock: time.clock);
  });
  tearDown(() => db.close());

  Future<List<QueryRow>> targets() => db.customSelect('''
    SELECT p.id, p.question_template_id, i.knowledge_item_id
    FROM exercise_pools p
    JOIN question_templates t ON t.id = p.question_template_id
    JOIN exercise_pool_items i ON i.exercise_pool_id = p.id
    WHERE t.mode = 'reasoning' AND ${ReasoningFormat.scheduledPoolMemberSql()}
    ORDER BY p.id''').get();

  Future<List<String>> chain(QueryRow pool) async => [
    for (final row
        in await db
            .customSelect(
              '''
      SELECT knowledge_item_id FROM exercise_pool_items
      WHERE exercise_pool_id = ? ORDER BY rank''',
              variables: [Variable(pool.read<int>('id'))],
            )
            .get())
      row.read<String>('knowledge_item_id'),
  ];

  Future<void> studySupports(QueryRow pool) async {
    final ids = await chain(pool);
    for (final id in ids.take(ids.length - 1)) {
      final row = await db
          .customSelect(
            '''
        SELECT q.question_template_id FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        WHERE q.knowledge_item_id = ? AND t.mode = 'flashcard'
        ORDER BY q.question_template_id LIMIT 1''',
            variables: [Variable(id)],
          )
          .getSingle();
      await reviews.record(
        knowledgeItemId: id,
        questionTemplateId: row.read<String>('question_template_id'),
        rating: fsrs.Rating.good,
      );
    }
  }

  Future<ReasoningExercise> present(QueryRow pool) async =>
      await presenter.present(
        pool.read<String>('knowledge_item_id'),
        pool.read<String>('question_template_id'),
        seed: 71,
        certificationId: 'WSET_L4',
      ) as ReasoningExercise;

  test('only final targets get reasoning availability and supports must be studied', () async {
    final pools = await targets();
    expect(pools, hasLength(10));
    final planner = StudyPlanner(db, clock: time.clock);
    final before = await planner.cards('WSET_L4');
    expect(
      before.every((c) => c.formats.every((f) => f.mode != 'reasoning')),
      isTrue,
    );
    for (final pool in pools) {
      await expectLater(present(pool), throwsStateError);
      await studySupports(pool);
    }
    final after = await planner.cards('WSET_L4');
    final reasoned = after
        .where((c) => c.formats.any((f) => f.mode == 'reasoning'))
        .toList();
    expect(
      reasoned.map((c) => c.itemId).toSet(),
      pools.map((p) => p.read<String>('knowledge_item_id')).toSet(),
    );
    for (final pool in pools) {
      final ids = await chain(pool);
      expect((await present(pool)).itemIds.toSet(), ids.toSet());
      for (final support in ids.take(ids.length - 1)) {
        expect(
          after
              .singleWhere((c) => c.itemId == support)
              .formats
              .any((f) => f.mode == 'reasoning'),
          isFalse,
        );
        await expectLater(
          presenter.present(
            support,
            pool.read<String>('question_template_id'),
            seed: 1,
          ),
          throwsArgumentError,
        );
      }
    }
    const sharedTargets = {
      'ki_wset_reason_frost_clusters',
      'ki_wset_reason_ferment_ethanol',
    };
    for (final track in ['WSET_L2', 'WSET_L3']) {
      final trackCards = await planner.cards(track);
      expect(
        trackCards
            .where((c) => c.formats.any((f) => f.mode == 'reasoning'))
            .map((c) => c.itemId)
            .toSet(),
        sharedTargets,
      );
      for (final pool in pools.where(
        (p) => sharedTargets.contains(p.read<String>('knowledge_item_id')),
      )) {
        final exercise = await presenter.present(
          pool.read<String>('knowledge_item_id'),
          pool.read<String>('question_template_id'),
          seed: 71,
          certificationId: track,
        ) as ReasoningExercise;
        expect(exercise.itemIds.toSet(), (await chain(pool)).toSet());
      }
    }
    for (final track in ['CMS_CERTIFIED']) {
      expect(
        (await planner.cards(track))
            .every((c) => c.formats.every((f) => f.mode != 'reasoning')),
        isTrue,
      );
      await expectLater(
        presenter.present(
          pools.first.read<String>('knowledge_item_id'),
          pools.first.read<String>('question_template_id'),
          seed: 71,
          certificationId: track,
        ),
        throwsArgumentError,
      );
    }
  });

  test('coverage counts only ten depth-4 targets without counting support membership', () async {
    final checker = CoverageChecker(
      db,
      CoveragePolicy.parse(
        File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
      ),
    );
    final coverage = await checker.check('WSET_L4', on: '2026-10-01');
    final reasoned = coverage.items
        .where((i) => i.servedFormats.contains('reasoning'))
        .toList();
    expect(reasoned, hasLength(10));
    expect(
      reasoned.where((i) => i.item.domainId == 'viticulture'),
      hasLength(7),
    );
    expect(
      reasoned.where((i) => i.item.domainId == 'winemaking'),
      hasLength(3),
    );
    final pools = await targets();
    for (final pool in pools) {
      final ids = await chain(pool);
      for (final support in ids.take(ids.length - 1)) {
        expect(
          coverage.items
              .singleWhere((i) => i.id == support)
              .generated
              .any((f) => f.mode == 'reasoning'),
          isFalse,
        );
      }
    }
  });

  test(
    'depth 3 cannot serve reasoning even as the only available fallback',
    () async {
      final pool = (await targets()).first;
      await studySupports(pool);
      final target = pool.read<String>('knowledge_item_id');
      final card = (await StudyPlanner(db, clock: time.clock).cards('WSET_L4'))
          .singleWhere((c) => c.itemId == target);
      final reasoning = card.formats.singleWhere((f) => f.mode == 'reasoning');
      expect(StudyPlanner.servedFormats([reasoning], 3), isEmpty);
      expect(StudyPlanner.servedFormats([reasoning], 4), [reasoning]);
      await db.writeCurriculum(
        () => db.customStatement(
          '''
      UPDATE certification_knowledge_mappings SET minimum_depth = 3
      WHERE knowledge_item_id = ? AND certification_id = 'WSET_L4' ''',
          [target],
        ),
      );
      final changed = (await StudyPlanner(
        db,
        clock: time.clock,
      ).cards('WSET_L4')).singleWhere((c) => c.itemId == target);
      expect(changed.formats.any((f) => f.mode == 'reasoning'), isFalse);
      await expectLater(present(pool), throwsArgumentError);
    },
  );

  for (final correct in [true, false]) {
    test(
      '${correct ? 'successful chain' : 'wrong target only'} reviews and answers survive backup',
      () async {
        final pool = (await targets()).first;
        await studySupports(pool);
        final exercise = await present(pool);
        final before = {
          for (final state in await db.select(db.reviewStates).get())
            state.knowledgeItemId: state,
        };
        final answer = correct
            ? exercise.answer
            : exercise.options.firstWhere((o) => o != exercise.answer);
        final grades = presenter.grade(exercise, answer);
        expect(
          grades.map((g) => g.itemId).toSet(),
          correct ? exercise.itemIds.toSet() : {exercise.primaryItemId},
        );
        final results = await reviews.recordExercise(exercise, grades);
        for (final result in results) {
          expect(result.rating, correct ? fsrs.Rating.good : fsrs.Rating.again);
          expect(result.event.seed, 71);
          expect(result.event.selectedNodeId, answer.nodeId);
          expect(
            jsonDecode(result.event.answerPayload!),
            isA<Map<String, dynamic>>(),
          );
        }
        if (!correct) {
          for (final id in exercise.itemIds.where(
            (id) => id != exercise.primaryItemId,
          )) {
            expect(
              await (db.select(
                db.reviewStates,
              )..where((s) => s.knowledgeItemId.equals(id))).getSingle(),
              before[id],
            );
          }
        } else {
          expect(results.map((r) => r.event.exerciseId).toSet(), hasLength(1));
          expect(results.first.event.exerciseId, isNotNull);
        }
        final saved = await UserDataBackup(db, clock: time.clock).export();
        final restored = openTestDatabase();
        addTearDown(restored.close);
        await CurriculumIngester(
          restored,
          clock: time.clock,
        ).ingest(bundledDataset());
        await UserDataBackup(
          restored,
          clock: time.clock,
        ).import(jsonEncode(saved));
        final after = await UserDataBackup(
          restored,
          clock: time.clock,
        ).export();
        expect(after['tables'], saved['tables']);
      },
    );
  }

  test(
    'expired negative evidence removes reasoning from planning and coverage',
    () async {
      final pool = (await targets()).first;
      await studySupports(pool);
      final exercise = await present(pool);
      final negativeId = exercise.contrasts.first.evidence.first.itemId;
      final item = await (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.equals(negativeId))).getSingle();
      await db.writeCurriculum(
        () =>
            (db.update(db.knowledgeRelations)..where(
                  (r) =>
                      r.subjectId.equals(item.subjectId) &
                      r.relationType.equals(item.relationType) &
                      r.objectId.equals(item.objectId),
                ))
                .write(
                  const KnowledgeRelationsCompanion(
                    validUntil: Value('2026-10-01'),
                  ),
                ),
      );
      final card = (await StudyPlanner(db, clock: time.clock).cards('WSET_L4'))
          .singleWhere((c) => c.itemId == exercise.primaryItemId);
      expect(card.formats.any((f) => f.mode == 'reasoning'), isFalse);
      final coverage = await CoverageChecker(
        db,
        CoveragePolicy.parse(
          File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
        ),
      ).check('WSET_L4', on: '2026-10-01');
      expect(
        coverage.items
            .singleWhere((i) => i.id == exercise.primaryItemId)
            .servedFormats,
        isNot(contains('reasoning')),
      );
      await expectLater(present(pool), throwsStateError);
    },
  );

  test(
    'a studied support outside the track removes target reasoning availability',
    () async {
      final pool = (await targets()).first;
      await studySupports(pool);
      final ids = await chain(pool);
      await db.writeCurriculum(
        () => db.customStatement(
          '''
      DELETE FROM certification_knowledge_mappings
      WHERE knowledge_item_id = ? AND certification_id = 'WSET_L4' ''',
          [ids.first],
        ),
      );
      final card = (await StudyPlanner(db, clock: time.clock).cards('WSET_L4'))
          .singleWhere((c) => c.itemId == ids.last);
      expect(card.formats.any((f) => f.mode == 'reasoning'), isFalse);
      final coverage = await CoverageChecker(
        db,
        CoveragePolicy.parse(
          File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
        ),
      ).check('WSET_L4', on: '2026-10-01');
      expect(
        coverage.items.singleWhere((i) => i.id == ids.last).servedFormats,
        isNot(contains('reasoning')),
      );
      await expectLater(present(pool), throwsStateError);
    },
  );

  test(
    'a failed final write rolls back every chain review and memory projection',
    () async {
      final pool = (await targets()).first;
      await studySupports(pool);
      final exercise = await present(pool);
      final grades = presenter.grade(exercise, exercise.answer);
      expect(grades.length, greaterThan(1));
      final before = (await UserDataBackup(
        db,
        clock: time.clock,
      ).export())['tables'];
      await db.customStatement('''CREATE TEMP TRIGGER reject_reasoning_fixture
      BEFORE INSERT ON review_events WHEN NEW.knowledge_item_id = '${grades.last.itemId}'
      BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END;''');
      await expectLater(
        reviews.recordExercise(exercise, grades),
        throwsA(anything),
      );
      expect(
        (await UserDataBackup(db, clock: time.clock).export())['tables'],
        before,
      );
    },
  );
}
