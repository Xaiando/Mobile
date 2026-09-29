import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/mcq/mcq_format.dart';
import 'package:sommelier/core/questions/question_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/curriculum_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

class _GatedExercisePresenter extends ExercisePresenter {
  _GatedExercisePresenter(super.db, TestClock time, FormatRegistry formats)
    : super(clock: time.clock, formats: formats);

  Completer<void>? gate;
  int calls = 0;

  @override
  Future<Exercise> present(
    String itemId,
    String questionTemplateId, {
    required int seed,
    String? certificationId,
  }) async {
    calls++;
    if (gate case final held?) await held.future;
    return super.present(
      itemId,
      questionTemplateId,
      seed: seed,
      certificationId: certificationId,
    );
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late ProviderContainer container;
  late _GatedExercisePresenter presenter;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final formats = FormatRegistry(const [McqFormat()]);
    presenter = _GatedExercisePresenter(db, time, formats);
    container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(time.clock),
        studyRandomProvider.overrideWithValue(Random(1)),
        // These tests exercise choose(), which only accepts MCQ answers.
        formatRegistryProvider.overrideWithValue(formats),
        exercisePresenterProvider.overrideWithValue(presenter),
      ],
    );
  });
  tearDown(() => db.close());

  StudySessionController controller() =>
      container.read(studySessionProvider.notifier);
  StudySessionState? current() => container.read(studySessionProvider).value;

  test('an answer records a review with its response time', () async {
    await controller().start();
    final turn = current()!.turn!;
    time.advance(const Duration(seconds: 7));
    await controller().choose(turn.question.answer);

    final answered = current()!.turn!;
    expect(answered.isAnswered, isTrue);
    expect(answered.result!.isCorrect, isTrue);
    final event = await db.select(db.reviewEvents).getSingle();
    expect(event.responseMs, 7000);
    expect(current()!.session.answered, 1);

    await controller().next();
    expect(current()!.turn!.card.itemId, isNot(turn.card.itemId));
  });

  test(
    'ending a session while an answer is saved does not bring it back',
    () async {
      await controller().start();
      final question = current()!.turn!.question;

      final answering = controller().choose(question.answer);
      controller().end();
      await answering;

      expect(current(), isNull);
      // The answer itself is kept.
      expect(await db.select(db.reviewEvents).get(), hasLength(1));
    },
  );

  test('a second tap on an answered question is ignored', () async {
    await controller().start();
    final question = current()!.turn!.question;
    await controller().choose(question.answer);
    await controller().choose(question.answer);
    expect(await db.select(db.reviewEvents).get(), hasLength(1));
  });

  test('a double Continue tap presents the next card only once', () async {
    await controller().start();
    final firstTurn = current()!.turn!;
    await controller().choose(firstTurn.question.answer);
    final answeredTurn = current()!.turn!;

    presenter.gate = Completer<void>();
    final firstNext = controller().next();
    final secondNext = controller().next();
    try {
      expect(presenter.calls, 2, reason: 'start and one next presentation');
      expect(
        current()!.turn,
        same(answeredTurn),
        reason: 'presentation is held',
      );
    } finally {
      presenter.gate!.complete();
      await Future.wait([firstNext, secondNext]);
    }
    final secondTurn = current()!.turn!;
    expect(secondTurn.card.itemId, isNot(firstTurn.card.itemId));
    await controller().choose(secondTurn.question.answer);
    expect(container.read(studySessionProvider).hasError, isFalse);
    expect(current()!.session.answered, 2);
    expect(await db.select(db.reviewEvents).get(), hasLength(2));
  });

  test('without a track there is no session', () async {
    await db.delete(db.userProfiles).go();
    await controller().start();
    expect(container.read(studySessionProvider).hasError, isFalse);
    expect(current(), isNull);
  });
}
