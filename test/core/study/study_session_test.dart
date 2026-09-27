import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/study_session.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

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

  /// Answers the session's current card with a forward flashcard.
  Future<ReviewResult> answer(StudySession session, fsrs.Rating rating) async {
    final card = session.current!;
    final format = card.formats.firstWhere(
      (f) => !f.isMultipleChoice && !f.isReverse,
    );
    final result = await reviews.gradeFlashcard(
      await presenter.present(card.itemId, format.questionTemplateId, seed: 1),
      rating,
    );
    session.complete(result);
    time.advance(const Duration(seconds: 20));
    return result;
  }

  test(
    'a card on a learning step comes back later in the session (FS-11)',
    () async {
      final session = StudySession((await planner.plan())!);
      expect(session.planned, 5);
      final first = session.current!.itemId;

      final result = await answer(session, fsrs.Rating.good);
      expect(result.staysInSession, isTrue, reason: 'step 1 of 2');
      expect(session.remaining, 5);
      expect(session.current!.itemId, isNot(first));

      for (var i = 0; i < 4; i++) {
        await answer(session, fsrs.Rating.good);
      }
      // The first card is back, now reviewed once.
      expect(session.current!.itemId, first);
      expect(session.current!.isNew, isFalse);

      final graduated = await answer(session, fsrs.Rating.good);
      expect(graduated.staysInSession, isFalse);
      expect(graduated.after.state, fsrs.State.review.value);
    },
  );

  test('the session ends when no card is left on a step', () async {
    final session = StudySession((await planner.plan())!);
    while (!session.isFinished) {
      await answer(session, fsrs.Rating.easy);
    }
    expect(session.answered, 5);
    expect(session.correct, 5);
    expect(session.current, isNull);
  });

  test(
    'Again keeps a card in the session; the score counts it wrong',
    () async {
      final session = StudySession((await planner.plan())!);
      final first = session.current!.itemId;
      await answer(session, fsrs.Rating.again);
      for (var i = 0; i < 4; i++) {
        await answer(session, fsrs.Rating.easy);
      }
      expect(session.current!.itemId, first);
      await answer(session, fsrs.Rating.easy);
      expect(session.isFinished, isTrue);
      expect(session.answered, 6);
      expect(session.correct, 5);
    },
  );

  test('a result for another card is refused', () async {
    final session = StudySession((await planner.plan())!);
    final other = (await planner.cards('WSET_L3'))
        .firstWhere((c) => c.itemId != session.current!.itemId);
    final format = other.formats.firstWhere((f) => !f.isMultipleChoice);
    final result = await reviews.gradeFlashcard(
      await presenter.present(other.itemId, format.questionTemplateId, seed: 1),
      fsrs.Rating.good,
    );
    expect(() => session.complete(result), throwsStateError);
    expect(session.answered, 0);
  });

  test('a new card starts with its easiest format; the ladder chooses the '
      'next (F4)', () async {
    final card = await planner
        .cards('WSET_L3')
        .then(
          (all) => all.firstWhere((c) => c.itemId == 'ki_barolo_min_ageing'),
        );
    expect(card.formats.length, greaterThan(1));
    expect(card.chooseFormat(_FixedRandom(3)), card.formats.first);
    expect(card.formats.first.mode, 'mcq');

    final mcq = await presenter.present(
      card.itemId,
      card.formats.first.questionTemplateId,
      seed: 1,
    );
    final result = await reviews.answerMultipleChoice(mcq, mcq.answer);
    final reviewed = card.reviewed(
      result.after,
      templateId: result.event.questionTemplateId,
    );
    expect(reviewed.lastTemplateId, card.formats.first.questionTemplateId);
    expect(
      reviewed.chooseFormat(_FixedRandom(3)).mode,
      isNot('mcq'),
      reason: 'not the last format again (QF-7)',
    );
  });
}

/// Always draws [value], clamped to the range asked for.
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value < max ? value : max - 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
