import 'dart:math';

import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late ReviewService reviews;
  late QuestionPresenter presenter;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(7),
    );
    presenter = QuestionPresenter(db);
  });
  tearDown(() => db.close());

  Future<PresentedQuestion> mcq({int seed = 7}) => presenter.present(
    'ki_chablis_grape',
    'qt_principal_grape_fwd_mcq',
    seed: seed,
  );
  Future<PresentedQuestion> flashcard() =>
      presenter.present('ki_champagne_soil', 'qt_soil_fwd_flashcard', seed: 1);

  Future<ReviewState> stored(String itemId) => (db.select(
    db.reviewStates,
  )..where((s) => s.knowledgeItemId.equals(itemId))).getSingle();

  test('the first review creates the memory state (FS-3)', () async {
    expect(await db.select(db.reviewStates).get(), isEmpty);
    final result = await reviews.gradeFlashcard(
      await flashcard(),
      fsrs.Rating.good,
    );
    expect(result.before, isNull);
    expect(result.after.reps, 1);
    expect(result.after.lapses, 0);
    expect(result.after.state, fsrs.State.learning.value);
    expect(result.after.lastReview, time.now);
    expect(await stored('ki_champagne_soil'), result.after);
    // Configuration version 1 is seeded on demand and recorded (FS-8).
    expect(result.event.schedulerConfigVersion, 1);
    final config = await db.select(db.schedulerConfigs).getSingle();
    expect(config.desiredRetention, 0.9);
    expect(config.enableFuzzing, isTrue);
  });

  test('stores exactly the D, S and due date the package computes', () async {
    final question = await flashcard();
    final scheduler = fsrs.Scheduler(enableFuzzing: false);
    var card = fsrs.Card(cardId: 0, due: time.now);
    for (final rating in [
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.again,
      fsrs.Rating.hard,
      fsrs.Rating.good,
      fsrs.Rating.easy,
    ]) {
      final result = await reviews.gradeFlashcard(question, rating);
      card = scheduler.reviewCard(card, rating, reviewDateTime: time.now).card;
      expect(result.after.difficulty, card.difficulty, reason: '$rating');
      expect(result.after.stability, card.stability, reason: '$rating');
      expect(result.after.due, card.due, reason: '$rating');
      expect(result.after.state, card.state.value, reason: '$rating');
      expect(result.after.step, card.step, reason: '$rating');
      expect(await stored('ki_champagne_soil'), result.after);
      time.now = card.due;
    }
  });

  test('an MCQ is graded right = Good, wrong = Again (FS-6)', () async {
    final question = await mcq();
    final right = await reviews.answerMultipleChoice(question, question.answer);
    expect(right.rating, fsrs.Rating.good);
    expect(right.isCorrect, isTrue);

    time.advance(const Duration(minutes: 1));
    final wrong = await reviews.answerMultipleChoice(
      question,
      question.options.firstWhere((o) => o != question.answer),
    );
    expect(wrong.rating, fsrs.Rating.again);
    expect(wrong.isCorrect, isFalse);
    expect(wrong.after.reps, 2);
  });

  test('an MCQ review logs its seed, the options shown and the choice '
      '(QG-7)', () async {
    final question = await mcq(seed: 123);
    final choice = question.options.last;
    final result = await reviews.answerMultipleChoice(
      question,
      choice,
      responseTime: const Duration(milliseconds: 4200),
    );
    expect(result.event.seed, 123);
    expect(result.event.selectedNodeId, choice.nodeId);
    expect(result.event.responseMs, 4200);
    expect(result.event.questionTemplateId, 'qt_principal_grape_fwd_mcq');
    final options =
        await (db.select(db.reviewEventOptions)
              ..where((o) => o.reviewEventId.equals(result.event.id))
              ..orderBy([(o) => OrderingTerm.asc(o.position)]))
            .get();
    expect(options.map((o) => o.position), [1, 2, 3, 4]);
    expect(
      options.map((o) => o.knowledgeNodeId),
      question.options.map((o) => o.nodeId),
    );
  });

  test('a flashcard review logs no options', () async {
    final result = await reviews.gradeFlashcard(
      await flashcard(),
      fsrs.Rating.hard,
    );
    expect(result.event.rating, 2);
    expect(result.event.seed, isNull);
    expect(result.event.selectedNodeId, isNull);
    expect(await db.select(db.reviewEventOptions).get(), isEmpty);
  });

  test(
    'reps count every review; a lapse is Again in Review state (FS-7)',
    () async {
      final question = await flashcard();
      Future<ReviewResult> grade(fsrs.Rating rating) async {
        final result = await reviews.gradeFlashcard(question, rating);
        time.now = result.after.due;
        return result;
      }

      // Again while learning is not a lapse: the item was never learned.
      expect((await grade(fsrs.Rating.again)).isLapse, isFalse);
      await grade(fsrs.Rating.good);
      final graduated = await grade(fsrs.Rating.good);
      expect(graduated.after.state, fsrs.State.review.value);
      expect(graduated.after.step, isNull);

      final lapse = await grade(fsrs.Rating.again);
      expect(lapse.isLapse, isTrue);
      expect(lapse.after.state, fsrs.State.relearning.value);
      expect(lapse.after.stability, lessThan(graduated.after.stability));
      expect(lapse.after.difficulty, greaterThan(graduated.after.difficulty));

      // Again while relearning is not a second lapse.
      expect((await grade(fsrs.Rating.again)).isLapse, isFalse);
      final back = await grade(fsrs.Rating.good);
      expect(back.after.state, fsrs.State.review.value);
      expect((await grade(fsrs.Rating.again)).isLapse, isTrue);

      final state = await stored('ki_champagne_soil');
      expect(state.reps, 7);
      expect(state.lapses, 2);
    },
  );

  test('review_states equals a replay of review_events (FS-4)', () async {
    final question = await flashcard();
    for (final rating in [
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.again,
      fsrs.Rating.good,
      fsrs.Rating.again,
    ]) {
      final result = await reviews.gradeFlashcard(question, rating);
      time.now = result.after.due;
    }
    final replay = await db
        .customSelect(
          '''
      SELECT e.state_after, e.step_after, e.stability_after, e.difficulty_after,
             e.due_after, e.reviewed_at,
             (SELECT count(*) FROM review_events x
               WHERE x.knowledge_item_id = e.knowledge_item_id) AS reps,
             (SELECT count(*) FROM (
                SELECT rating, lag(state_after) OVER (
                  ORDER BY reviewed_at, id) AS state_before
                FROM review_events WHERE knowledge_item_id = ?1)
              WHERE rating = 1 AND state_before = 2) AS lapses
      FROM review_events e WHERE e.knowledge_item_id = ?1
      ORDER BY e.reviewed_at DESC LIMIT 1''',
          variables: [Variable('ki_champagne_soil')],
        )
        .getSingle();
    final state = await stored('ki_champagne_soil');
    expect(replay.read<int>('state_after'), state.state);
    expect(replay.readNullable<int>('step_after'), state.step);
    expect(replay.read<double>('stability_after'), state.stability);
    expect(replay.read<double>('difficulty_after'), state.difficulty);
    expect(DateTime.parse(replay.read<String>('due_after')), state.due);
    expect(
      DateTime.parse(replay.read<String>('reviewed_at')),
      state.lastReview,
    );
    expect(replay.read<int>('reps'), state.reps);
    expect(replay.read<int>('lapses'), state.lapses);
    // Good, Good graduates; Again lapses; Good returns to Review; Again again.
    expect(state.lapses, 2);
  });

  test('a failed write leaves neither an event nor a state', () async {
    await expectLater(
      reviews.record(
        knowledgeItemId: 'ki_chablis_grape',
        questionTemplateId: 'qt_principal_grape_fwd_mcq',
        rating: fsrs.Rating.good,
        seed: 1,
        optionNodeIds: ['n_grape_chardonnay', 'n_no_such_node'],
      ),
      throwsA(anything),
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });

  test('rejects answers that were not presented', () async {
    final question = await mcq();
    await expectLater(
      reviews.answerMultipleChoice(
        question,
        const QuestionOption('n_grape_nebbiolo', 'Nebbiolo'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      reviews.gradeFlashcard(question, fsrs.Rating.good),
      throwsArgumentError,
    );
    await expectLater(
      reviews.answerMultipleChoice(await flashcard(), question.answer),
      throwsArgumentError,
    );
    await expectLater(
      reviews.record(
        knowledgeItemId: 'ki_chablis_grape',
        questionTemplateId: 'qt_soil_fwd_flashcard',
        rating: fsrs.Rating.good,
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test('event IDs are UUIDs the schema accepts', () async {
    final result = await reviews.gradeFlashcard(
      await flashcard(),
      fsrs.Rating.good,
    );
    expect(
      result.event.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
