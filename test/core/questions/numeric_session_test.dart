import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/numeric/numeric_format.dart';
import 'package:sommelier/core/questions/question_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
// This imports only the test-only fixture builder, not the other test's main.
import 'numeric_format_test.dart' show numericTestDataset;

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
    ).ingest(numericTestDataset());
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L2');
    container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(time.clock),
        studyRandomProvider.overrideWithValue(Random(1)),
        formatRegistryProvider.overrideWithValue(
          FormatRegistry(const [NumericFormat()]),
        ),
      ],
    );
  });
  tearDown(() => db.close());

  StudySessionController controller() =>
      container.read(studySessionProvider.notifier);
  StudySessionState? current() => container.read(studySessionProvider).value;

  test('controller submits numeric input once, including concurrent duplicate taps', () async {
    await controller().start();
    expect(container.read(studySessionProvider).hasError, isFalse);
    final turn = current()!.turn!;
    expect(turn.question, same(turn.exercise));
    final question = turn.question as NumericQuestion;
    expect(question.mode, 'numeric');
    expect(turn.isAnswered, isFalse);
    controller().reveal();
    expect(
      current()!.turn!.revealed,
      isFalse,
      reason: 'objective answers stay hidden until submitted',
    );
    time.advance(const Duration(milliseconds: 1850));
    final answer = NumericAnswer.scalar(
      question.displayMinimum,
      unit: question.displayUnit,
    );
    await Future.wait([
      controller().submit(answer),
      controller().submit(answer),
    ]);
    await controller().submit(answer);
    expect(container.read(studySessionProvider).hasError, isFalse);
    final answered = current()!.turn!;
    expect(answered.isAnswered, isTrue);
    expect(answered.answer, answer);
    expect(answered.results, hasLength(1));
    expect(answered.result!.rating, fsrs.Rating.good);
    expect(answered.result!.after.reps, 1);
    expect(current()!.session.answered, 1);
    final event = await db.select(db.reviewEvents).getSingle();
    expect(
      (event.knowledgeItemId, event.questionTemplateId, event.seed),
      (question.primaryItemId, question.questionTemplateId, question.seed),
    );
    expect(event.responseMs, 1850);
    expect(jsonDecode(event.answerPayload!), containsPair('outcome', 'exact'));
    expect(await db.select(db.reviewStates).get(), hasLength(1));
    expect(await db.select(db.reviewEventOptions).get(), isEmpty);
  });

  test('invalid numeric text records Again with safe payload through the controller', () async {
    await controller().start();
    await controller().submit('Infinity');
    expect(container.read(studySessionProvider).hasError, isFalse);
    expect(current()!.turn!.isAnswered, isTrue);
    expect(current()!.turn!.result!.rating, fsrs.Rating.again);
    final event = await db.select(db.reviewEvents).getSingle();
    expect(jsonDecode(event.answerPayload!), containsPair('outcome', 'wrong'));
    expect((await db.select(db.reviewStates).getSingle()).reps, 1);
  });
}
