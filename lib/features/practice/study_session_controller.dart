import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../core/questions/exercise.dart';
import '../../core/questions/exercise_presenter.dart';
import '../../core/questions/question_presenter.dart';
import '../../core/questions/question_providers.dart';
import '../../core/study/review_service.dart';
import '../../core/study/study_planner.dart';
import '../../core/study/study_providers.dart';
import '../../core/study/study_session.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';

/// Draws question formats and presentation seeds. Tests fix it.
final studyRandomProvider = Provider<Random>((ref) => Random());

/// One card on screen: the exercise shown and, once answered, the results.
class SessionTurn {
  const SessionTurn({
    required this.card,
    required this.format,
    required this.exercise,
    required this.shownAt,
    this.answer,
    this.results,
    this.revealed = false,
  });

  final StudyCard card;

  /// The template chosen for the card.
  final QuestionFormat format;

  final Exercise exercise;
  final DateTime shownAt;

  /// The learner's answer, as the format takes it: an MCQ's option, a
  /// flashcard's grade.
  final Object? answer;

  /// Each graded item's review, the card's own first; null until answered.
  final List<ReviewResult>? results;

  /// Whether the answer is showing, before a self-graded format is graded.
  final bool revealed;

  bool get isAnswered => results != null;

  /// The card's own review, once answered.
  ReviewResult? get result => results?.first;

  /// The single-item question of an MCQ or a flashcard.
  PresentedQuestion get question => exercise as PresentedQuestion;

  /// The option the learner picked in an MCQ.
  QuestionOption? get selected => switch (answer) {
    final QuestionOption option => option,
    _ => null,
  };

  SessionTurn copyWith({
    Object? answer,
    List<ReviewResult>? results,
    bool? revealed,
  }) => SessionTurn(
    card: card,
    format: format,
    exercise: exercise,
    shownAt: shownAt,
    answer: answer ?? this.answer,
    results: results ?? this.results,
    revealed: revealed ?? this.revealed,
  );
}

/// The session on the Practice screen.
class StudySessionState {
  const StudySessionState({required this.session, required this.turn});

  final StudySession session;

  /// Null once every card is done.
  final SessionTurn? turn;

  bool get isFinished => turn == null;

  /// Share of the session done, counting repeats still queued.
  double get progress {
    final total = session.answered + session.remaining;
    return total == 0 ? 1 : session.answered / total;
  }
}

/// Runs a study session (spec TASK-007): presents each card in its format,
/// has the format grade the answer, records the grades through the review
/// service, and moves through the queue.
///
/// The state is null when no session is running.
class StudySessionController extends AsyncNotifier<StudySessionState?> {
  var _busy = false;

  @override
  Future<StudySessionState?> build() async => null;

  /// Plans a session for the active track and shows its first card.
  Future<void> start() async {
    state = const AsyncLoading();
    final started = await AsyncValue.guard(() async {
      final plan = await ref.read(studyPlannerProvider).plan();
      if (plan == null) return null;
      final session = StudySession(plan);
      return StudySessionState(session: session, turn: await _turn(session));
    });
    if (ref.mounted) state = started;
  }

  /// Answers the current exercise with [answer], as its format takes it.
  Future<void> submit(Object answer) => _answer(answer);

  /// Answers the current MCQ with [option] (FS-6).
  Future<void> choose(QuestionOption option) => submit(option);

  /// Shows the answer of a self-graded exercise, such as a flashcard. An
  /// objective format grades the learner's answer instead, so its answer
  /// stays hidden until then.
  void reveal() {
    final current = state.value;
    final turn = current?.turn;
    if (current == null || turn == null || turn.revealed) return;
    final format = ref.read(formatRegistryProvider)[turn.exercise.formatId];
    if (format == null || format.isObjective) return;
    state = AsyncData(
      StudySessionState(
        session: current.session,
        turn: turn.copyWith(revealed: true),
      ),
    );
  }

  /// Grades the revealed flashcard and moves to the next card.
  Future<void> grade(fsrs.Rating rating) async {
    await submit(rating);
    await next();
  }

  /// Moves to the next card after an answer.
  Future<void> next() async {
    if (state.hasError) return;
    final current = state.value;
    if (current == null || !(current.turn?.isAnswered ?? true)) return;
    final moved = await AsyncValue.guard(
      () async => StudySessionState(
        session: current.session,
        turn: await _turn(current.session),
      ),
    );
    if (_isCurrent(current.session)) state = moved;
  }

  /// Leaves the session. Answers already given are saved.
  void end() => state = const AsyncData(null);

  /// Whether [session] is still on screen after an await: the learner may
  /// have ended it meanwhile, and it must not come back.
  bool _isCurrent(StudySession session) =>
      ref.mounted && identical(state.value?.session, session);

  Future<void> _answer(Object answer) async {
    final current = state.value;
    final turn = current?.turn;
    if (_busy || current == null || turn == null || turn.isAnswered) return;
    _busy = true;
    try {
      final responseTime = utcNow(ref.read(clockProvider))
          .difference(turn.shownAt);
      final exercise = turn.exercise;
      final grades = ref
          .read(exercisePresenterProvider)
          .grade(exercise, answer);
      final results = await ref
          .read(reviewServiceProvider)
          .recordExercise(
            exercise,
            grades,
            responseTime: responseTime.isNegative
                ? Duration.zero
                : responseTime,
          );
      // The card's own review first, then the co-items'.
      bool own(ReviewResult r) =>
          r.after.knowledgeItemId == exercise.primaryItemId;
      final ordered = [...results.where(own), ...results.where((r) => !own(r))];
      current.session.completeExercise(ordered);
      if (!_isCurrent(current.session)) return;
      state = AsyncData(
        StudySessionState(
          session: current.session,
          turn: turn.copyWith(answer: answer, results: ordered, revealed: true),
        ),
      );
    } catch (error, stackTrace) {
      if (_isCurrent(current.session)) state = AsyncError(error, stackTrace);
    } finally {
      _busy = false;
    }
  }

  Future<SessionTurn?> _turn(StudySession session) async {
    final card = session.current;
    if (card == null) return null;
    final random = ref.read(studyRandomProvider);
    final format = card.chooseFormat(random);
    return SessionTurn(
      card: card,
      format: format,
      exercise: await ref
          .read(exercisePresenterProvider)
          .present(
            card.itemId,
            format.questionTemplateId,
            seed: ExercisePresenter.newSeed(random),
          ),
      shownAt: utcNow(ref.read(clockProvider)),
    );
  }
}

final studySessionProvider =
    AsyncNotifierProvider<StudySessionController, StudySessionState?>(
      StudySessionController.new,
    );
