import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/curriculum_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late ProviderContainer container;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(time.clock),
        studyRandomProvider.overrideWithValue(Random(1)),
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

  test('without a track there is no session', () async {
    await db.delete(db.userProfiles).go();
    await controller().start();
    expect(container.read(studySessionProvider).hasError, isFalse);
    expect(current(), isNull);
  });
}
