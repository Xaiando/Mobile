import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

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

/// One card on screen: the question shown and, once answered, the result.
class SessionTurn {
  const SessionTurn({
    required this.card,
    required this.question,
    required this.shownAt,
    this.selected,
    this.result,
    this.revealed = false,
  });

  final StudyCard card;
  final PresentedQuestion question;
  final DateTime shownAt;

  /// The option the learner picked in an MCQ.
  final QuestionOption? selected;

  /// Set once the answer is recorded.
  final ReviewResult? result;

  /// Whether a flashcard's answer is showing.
  final bool revealed;

  bool get isAnswered => result != null;
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

/// Runs a study session (spec TASK-007): presents each card, records the
/// answer through the review service, and moves through the queue.
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

  /// Answers the current MCQ with [option] (FS-6).
  Future<void> choose(QuestionOption option) => _answer(
    (turn, responseTime) => ref
        .read(reviewServiceProvider)
        .answerMultipleChoice(
          turn.question,
          option,
          responseTime: responseTime,
        ),
    selected: option,
  );

  /// Shows the current flashcard's answer.
  void reveal() {
    final current = state.value;
    final turn = current?.turn;
    if (current == null || turn == null || turn.question.isMultipleChoice) {
      return;
    }
    state = AsyncData(
      StudySessionState(
        session: current.session,
        turn: SessionTurn(
          card: turn.card,
          question: turn.question,
          shownAt: turn.shownAt,
          revealed: true,
        ),
      ),
    );
  }

  /// Grades the revealed flashcard and moves to the next card.
  Future<void> grade(fsrs.Rating rating) async {
    await _answer(
      (turn, responseTime) => ref
          .read(reviewServiceProvider)
          .gradeFlashcard(turn.question, rating, responseTime: responseTime),
    );
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

  Future<void> _answer(
    Future<ReviewResult> Function(SessionTurn turn, Duration responseTime)
    record, {
    QuestionOption? selected,
  }) async {
    final current = state.value;
    final turn = current?.turn;
    if (_busy || current == null || turn == null || turn.isAnswered) return;
    _busy = true;
    try {
      final responseTime = utcNow(ref.read(clockProvider))
          .difference(turn.shownAt);
      final result = await record(
        turn,
        responseTime.isNegative ? Duration.zero : responseTime,
      );
      current.session.complete(result);
      if (!_isCurrent(current.session)) return;
      state = AsyncData(
        StudySessionState(
          session: current.session,
          turn: SessionTurn(
            card: turn.card,
            question: turn.question,
            shownAt: turn.shownAt,
            selected: selected,
            result: result,
            revealed: true,
          ),
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
      question: await ref
          .read(questionPresenterProvider)
          .present(
            card.itemId,
            format.questionTemplateId,
            seed: QuestionPresenter.newSeed(random),
          ),
      shownAt: utcNow(ref.read(clockProvider)),
    );
  }
}

final studySessionProvider =
    AsyncNotifierProvider<StudySessionController, StudySessionState?>(
      StudySessionController.new,
    );
