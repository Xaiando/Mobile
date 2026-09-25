import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/study_session.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/pair_format.dart';
import '../../support/study_fixture.dart';

/// Backlog F3: composite exercises, end to end, with the test-only pair
/// format: pools, presentation, one event per item, rollback, co-items.
void main() {
  late AppDatabase db;
  late TestClock time;
  late GenerationReport generated;
  late ReviewService reviews;
  late ExercisePresenter presenter;

  const grapes = 'qt_permits_principal_grape_fwd_test_pair';

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    db = openTestDatabase();
    generated = await CurriculumIngester(
      db,
      clock: time.clock,
      formats: pairFormats,
    ).ingest(datasetOf(datasetWithPairs()));
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(3),
    );
    presenter = ExercisePresenter(db, formats: pairFormats, clock: time.clock);
  });
  tearDown(() => db.close());

  Future<PairExercise> pair(String itemId, {int seed = 7}) async =>
      await presenter.present(itemId, grapes, seed: seed) as PairExercise;

  test('a pooled format generates its pools at ingestion (QF-10)', () async {
    expect(generated.pools, greaterThan(0));
    final pools = await db.select(db.exercisePools).get();
    expect(pools, hasLength(generated.pools));
    for (final pool in pools) {
      final items = await (db.select(
        db.exercisePoolItems,
      )..where((i) => i.exercisePoolId.equals(pool.id))).get();
      expect(items.length, greaterThanOrEqualTo(2), reason: '${pool.id}');
    }
    expect(generated.multipleChoice, greaterThan(0), reason: 'MCQs as before');
  });

  test('writes one event per item with a shared exercise ID (QF-3)', () async {
    final exercise = await pair('ki_chablis_grape');
    expect(exercise.itemIds.first, 'ki_chablis_grape');
    final co = exercise.coItemId;
    final results = await reviews.recordExercise(
      exercise,
      presenter.grade(exercise, {'ki_chablis_grape'}),
      responseTime: const Duration(seconds: 4),
    );
    expect(
      [for (final r in results) r.after.knowledgeItemId],
      ['ki_chablis_grape', co],
    );

    final events = await db.select(db.reviewEvents).get();
    expect(
      [
        for (final e in events)
          (e.knowledgeItemId, e.rating, e.answerPayload, e.seed, e.responseMs),
      ],
      [
        ('ki_chablis_grape', 3, '{"known":true}', 7, 4000),
        (co, 1, '{"known":false}', 7, 4000),
      ],
    );
    expect(events.first.exerciseId, isNotNull);
    expect(events.last.exerciseId, events.first.exerciseId);
    expect(await db.select(db.reviewStates).get(), hasLength(2));
  });

  test('a failure in one grade writes nothing', () async {
    // The pool of the grape template does not hold a soil item.
    const exercise = PairExercise(
      primaryItemId: 'ki_chablis_grape',
      coItemId: 'ki_champagne_soil',
      questionTemplateId: grapes,
      prompt: 'Which of these did you know?',
      seed: 1,
      statements: {},
    );
    await expectLater(
      reviews.recordExercise(
        exercise,
        presenter.grade(exercise, {'ki_chablis_grape', 'ki_champagne_soil'}),
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });

  test('refuses to grade an item twice, or one it does not practise', () async {
    final exercise = await pair('ki_chablis_grape');
    await expectLater(
      reviews.recordExercise(exercise, [
        ItemGrade('ki_chablis_grape', fsrs.Rating.good),
        ItemGrade('ki_chablis_grape', fsrs.Rating.again),
      ]),
      throwsArgumentError,
    );
    await expectLater(
      reviews.recordExercise(exercise, [
        ItemGrade('ki_barolo_grape', fsrs.Rating.good),
      ]),
      throwsArgumentError,
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test('a single-item exercise keeps no exercise ID, as before', () async {
    final mcq = await presenter.present(
      'ki_chablis_grape',
      'qt_principal_grape_fwd_mcq',
      seed: 7,
    );
    await reviews.recordExercise(
      mcq,
      presenter.grade(mcq, (mcq as dynamic).answer as Object),
    );
    final event = (await db.select(db.reviewEvents).get()).single;
    expect((event.exerciseId, event.answerPayload), (null, null));
    expect(await db.select(db.reviewEventOptions).get(), hasLength(4));
  });

  test('draws a due co-item before a new one', () async {
    // Review Barolo's grape, then wait until it is due.
    final barolo = await pair('ki_barolo_grape');
    final result = (await reviews.recordExercise(barolo, [
      ItemGrade('ki_barolo_grape', fsrs.Rating.good),
    ])).single;
    time.now = result.after.due;
    for (var seed = 1; seed <= 12; seed++) {
      expect(
        (await pair('ki_chablis_grape', seed: seed)).coItemId,
        'ki_barolo_grape',
        reason: 'seed $seed',
      );
    }
  });

  group('a session', () {
    late StudySession session;

    bool servesGrapes(StudyCard card) =>
        card.formats.any((f) => f.questionTemplateId == grapes);

    setUp(() async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final plan = (await StudyPlanner(
        db,
        clock: time.clock,
        formats: pairFormats,
      ).plan(sessionSize: 30, newItems: 30))!;
      // Grape items first, so the turn's pool has planned neighbours.
      session = StudySession(
        StudyPlan(
          certificationId: plan.certificationId,
          cards: [
            ...plan.cards.where(servesGrapes),
            ...plan.cards.where((c) => !servesGrapes(c)),
          ],
          dueCount: plan.dueCount,
          newAvailable: plan.newAvailable,
        ),
      );
    });

    /// A pair of the current card and a card planned later that shares its
    /// pool.
    Future<(PairExercise, String)> pairWithPlannedCoItem() async {
      final first = session.current!;
      final exercise = await pair(first.itemId);
      final pool = exercise.statements.keys.toSet();
      final rows = await db
          .customSelect(
            'SELECT i.knowledge_item_id AS id FROM exercise_pool_items i '
            'JOIN exercise_pools p ON p.id = i.exercise_pool_id '
            "WHERE p.question_template_id = '$grapes'",
          )
          .get();
      pool.addAll([for (final r in rows) r.read<String>('id')]);
      final planned = [
        for (final card in session.queued)
          if (card.itemId != first.itemId && pool.contains(card.itemId))
            card.itemId,
      ];
      return (
        PairExercise(
          primaryItemId: first.itemId,
          coItemId: planned.first,
          questionTemplateId: grapes,
          prompt: exercise.prompt,
          seed: exercise.seed,
          statements: const {},
        ),
        planned.first,
      );
    }

    test('offers the pair format to the items its pools hold', () async {
      final formats = {
        for (final card in session.queued)
          for (final format in card.formats) format.mode,
      };
      expect(formats, containsAll(['mcq', 'flashcard', 'test_pair']));
    });

    test('counts co-items as bonus reviews, using no slot', () async {
      final remaining = session.remaining;
      final (exercise, co) = await pairWithPlannedCoItem();
      // Easy graduates both at once, so neither stays on a learning step.
      final results = await reviews.recordExercise(exercise, [
        ItemGrade(exercise.primaryItemId, fsrs.Rating.easy),
        ItemGrade(co, fsrs.Rating.easy),
      ]);
      session.completeExercise(results);
      expect((session.answered, session.bonus), (1, 1));
      expect(
        session.queued.map((c) => c.itemId),
        isNot(contains(co)),
        reason: 'reviewed as a co-item, it needs no slot of its own',
      );
      expect(session.remaining, remaining - 2);
    });

    test('a co-item left on a learning step comes back later', () async {
      final (exercise, co) = await pairWithPlannedCoItem();
      final results = await reviews.recordExercise(
        exercise,
        presenter.grade(exercise, {exercise.primaryItemId}),
      );
      expect(results.last.staysInSession, isTrue, reason: 'Again, as new');
      session.completeExercise(results);
      final ids = [for (final card in session.queued) card.itemId];
      expect(ids.where((id) => id == co), hasLength(1));
      expect(ids.sublist(ids.length - 2), [co, exercise.primaryItemId]);
    });

    test('refuses results without the card of the turn', () async {
      final other = session.queued[1].itemId;
      final exercise = await pair(other);
      final results = await reviews.recordExercise(exercise, [
        ItemGrade(other, fsrs.Rating.good),
      ]);
      expect(() => session.completeExercise(results), throwsStateError);
    });
  });
}
