import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/memory_state.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

/// Phase 3 acceptance (spec §O): "Flashcard answers correctly update DSR
/// variables and reorder the study queue."
void main() {
  late AppDatabase db;
  late TestClock time;
  late StudyPlanner planner;
  late ReviewService reviews;
  late QuestionPresenter presenter;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    planner = StudyPlanner(db, clock: time.clock);
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
    );
    presenter = QuestionPresenter(db);
  });
  tearDown(() => db.close());

  /// Answers the item's forward flashcard with [rating].
  Future<ReviewResult> flashcard(String itemId, fsrs.Rating rating) async {
    final templateId = switch (itemId) {
      'ki_barolo_location' => 'qt_located_in_fwd_flashcard',
      'ki_chablis_soil' => 'qt_soil_fwd_flashcard',
      'ki_barolo_min_ageing' => 'qt_min_ageing_fwd_flashcard',
      _ => 'qt_principal_grape_fwd_flashcard',
    };
    final shown = await presenter.present(itemId, templateId, seed: 1);
    expect(shown.isMultipleChoice, isFalse);
    return reviews.gradeFlashcard(shown, rating);
  }

  Future<List<String>> dueQueue() async => [
    for (final card in (await planner.plan())!.cards)
      if (!card.isNew) card.itemId,
  ];

  Future<ReviewState> stateOf(String itemId) => (db.select(
    db.reviewStates,
  )..where((s) => s.knowledgeItemId.equals(itemId))).getSingle();

  test(
    'flashcard answers update D, S and R and reorder the study queue',
    () async {
      // Fifty days ago the learner learned Cornas's grape; thirty days ago,
      // the Barolo chain (location -> grape -> minimum ageing) and a soil.
      await flashcard('ki_cornas_grape', fsrs.Rating.easy);
      time.advance(const Duration(days: 20));
      for (final itemId in [
        'ki_barolo_location',
        'ki_barolo_grape',
        'ki_barolo_min_ageing',
        'ki_chablis_soil',
      ]) {
        await flashcard(itemId, fsrs.Rating.easy);
      }
      time.advance(const Duration(days: 30));

      final queueBefore = await dueQueue();
      expect(queueBefore, [
        'ki_cornas_grape', // the most overdue
        'ki_barolo_grape',
        'ki_barolo_location',
        'ki_barolo_min_ageing',
        'ki_chablis_soil', // secondary: C = 0.5
      ]);

      // 1. The answer updates D, S and R exactly as FSRS-6 computes them.
      final before = await stateOf('ki_barolo_min_ageing');
      final scheduler = fsrs.Scheduler(enableFuzzing: false);
      expect(
        retrievabilityOf(before, scheduler, time.now),
        lessThan(0.9),
        reason: 'overdue: below the desired retention',
      );
      final expected = scheduler
          .reviewCard(
            cardOf(before),
            fsrs.Rating.again,
            reviewDateTime: time.now,
          )
          .card;

      final forgotten = await flashcard(
        'ki_barolo_min_ageing',
        fsrs.Rating.again,
      );

      final after = await stateOf('ki_barolo_min_ageing');
      expect(after, forgotten.after);
      expect(after.difficulty, expected.difficulty);
      expect(after.difficulty, greaterThan(before.difficulty));
      expect(after.stability, expected.stability);
      expect(after.stability, lessThan(before.stability));
      expect(after.due, expected.due);
      expect(after.state, fsrs.State.relearning.value);
      expect(after.lapses, 1);
      expect(after.reps, 2);
      expect(retrievabilityOf(after, scheduler, time.now), 1);
      expect(
        retrievabilityOf(
          after,
          scheduler,
          time.now.add(const Duration(days: 30)),
        ),
        lessThan(retrievabilityOf(before, scheduler, time.now)),
        reason:
            'the lower stability fades faster: 30 days after this review, R '
            'is lower than 30 days after the previous one',
      );

      // 2. The queue reorders: the forgotten item waits for its relearning
      // step, and its prerequisites overtake the item that led the queue
      // (the prerequisite factor P, A-4).
      final queueAfter = await dueQueue();
      expect(queueAfter, [
        'ki_barolo_grape', // P = 2: its direct dependent was forgotten
        'ki_barolo_location', // P = 1.5: two steps away
        'ki_cornas_grape',
        'ki_chablis_soil',
      ]);

      // 3. Once the relearning step is due, the item leads the queue (FS-11).
      time.advance(const Duration(minutes: 10));
      expect((await dueQueue()).first, 'ki_barolo_min_ageing');

      // 4. A Good answer raises stability and moves the item out of the queue.
      final cornasBefore = await stateOf('ki_cornas_grape');
      final recalled = await flashcard('ki_cornas_grape', fsrs.Rating.good);
      expect(recalled.after.stability, greaterThan(cornasBefore.stability));
      expect(
        recalled.after.due.isAfter(time.now.add(const Duration(days: 30))),
        isTrue,
      );
      expect(await dueQueue(), isNot(contains('ki_cornas_grape')));
    },
  );
}
