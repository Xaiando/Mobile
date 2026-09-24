import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../questions/question_presenter.dart';
import '../time/utc_clock.dart';
import 'memory_state.dart';
import 'scheduler_config.dart';

/// What one review changed.
class ReviewResult {
  const ReviewResult({
    required this.event,
    required this.before,
    required this.after,
  });

  /// The logged review (append-only).
  final ReviewEvent event;

  /// The memory state before the review; null when the item was new (FS-3).
  final ReviewState? before;

  /// The memory state after the review, as stored in `review_states`.
  final ReviewState after;

  fsrs.Rating get rating => fsrs.Rating.fromValue(event.rating);

  /// Anything but Again counts as recalled.
  bool get isCorrect => rating != fsrs.Rating.again;

  /// An Again while the item was in Review state (FS-7).
  bool get isLapse => after.lapses > (before?.lapses ?? 0);

  /// The item is on a learning or relearning step, due again within minutes,
  /// so the session shows it again (FS-11).
  bool get staysInSession => isOnStep(after);
}

/// Grades an item and updates its memory state (spec TASK-003).
///
/// Each review appends a `review_events` row, with the options shown for an
/// MCQ, and rewrites the item's `review_states` projection, all in one
/// transaction. FSRS-6 comes from the `fsrs` package (FS-1); this class adds
/// only what the package does not track: `reps` and `lapses` (FS-7).
class ReviewService {
  ReviewService(
    this.db, {
    Clock? clock,
    this.schedulerFactory = schedulerFor,
    this.random,
  }) : _clock = clock ?? const Clock();

  final AppDatabase db;

  /// Builds the scheduler for a stored configuration. Tests replace it to fix
  /// the fuzzing (FS-10).
  final fsrs.Scheduler Function(SchedulerConfig config) schedulerFactory;

  /// Draws the event IDs; secure by default. Tests fix it.
  final Random? random;

  final Clock _clock;

  /// Grades an MCQ answer: the right option is Good, any other is Again
  /// (FS-6). The seed, the options and the choice are logged (QG-7).
  Future<ReviewResult> answerMultipleChoice(
    PresentedQuestion question,
    QuestionOption selected, {
    Duration? responseTime,
  }) async {
    if (!question.isMultipleChoice) {
      throw ArgumentError.value(
        question.questionTemplateId,
        'question',
        'is not a multiple-choice question',
      );
    }
    if (!question.options.contains(selected)) {
      throw ArgumentError.value(
        selected.nodeId,
        'selected',
        'is not one of the options shown',
      );
    }
    return record(
      knowledgeItemId: question.knowledgeItemId,
      questionTemplateId: question.questionTemplateId,
      rating: selected == question.answer
          ? fsrs.Rating.good
          : fsrs.Rating.again,
      seed: question.seed,
      optionNodeIds: [for (final option in question.options) option.nodeId],
      selectedNodeId: selected.nodeId,
      responseTime: responseTime,
    );
  }

  /// Records the learner's own grade, 1 to 4, for a revealed flashcard
  /// (FS-6, QG-8).
  Future<ReviewResult> gradeFlashcard(
    PresentedQuestion question,
    fsrs.Rating rating, {
    Duration? responseTime,
  }) async {
    if (question.isMultipleChoice) {
      throw ArgumentError.value(
        question.questionTemplateId,
        'question',
        'is a multiple-choice question; grade it with answerMultipleChoice',
      );
    }
    return record(
      knowledgeItemId: question.knowledgeItemId,
      questionTemplateId: question.questionTemplateId,
      rating: rating,
      responseTime: responseTime,
    );
  }

  /// Applies [rating] to the item at the current time.
  ///
  /// [optionNodeIds] are the MCQ options in display order, empty for a
  /// flashcard.
  Future<ReviewResult> record({
    required String knowledgeItemId,
    required String questionTemplateId,
    required fsrs.Rating rating,
    int? seed,
    List<String> optionNodeIds = const [],
    String? selectedNodeId,
    Duration? responseTime,
  }) async {
    if (responseTime != null && responseTime.isNegative) {
      throw ArgumentError.value(responseTime, 'responseTime', 'is negative');
    }
    return db.transaction(() async {
      final served =
          await (db.select(db.questions)..where(
                (q) =>
                    q.knowledgeItemId.equals(knowledgeItemId) &
                    q.questionTemplateId.equals(questionTemplateId),
              ))
              .getSingleOrNull();
      if (served == null) {
        throw ArgumentError(
          'No question $questionTemplateId for item $knowledgeItemId',
        );
      }

      final now = utcNow(_clock);
      final config = await ensureSchedulerConfig(db, clock: _clock);
      final before =
          await (db.select(db.reviewStates)
                ..where((s) => s.knowledgeItemId.equals(knowledgeItemId)))
              .getSingleOrNull();
      final card = before == null
          ? fsrs.Card(cardId: 0, due: now)
          : cardOf(before);
      final reviewed = schedulerFactory(config)
          .reviewCard(card, rating, reviewDateTime: now)
          .card;

      final isLapse =
          before?.state == fsrs.State.review.value &&
          rating == fsrs.Rating.again;
      final after = ReviewState(
        knowledgeItemId: knowledgeItemId,
        state: reviewed.state.value,
        step: reviewed.step,
        stability: reviewed.stability!,
        difficulty: reviewed.difficulty!,
        due: toStorageInstant(reviewed.due),
        lastReview: now,
        reps: (before?.reps ?? 0) + 1,
        lapses: (before?.lapses ?? 0) + (isLapse ? 1 : 0),
      );
      final event = ReviewEvent(
        id: newUuid(random),
        knowledgeItemId: knowledgeItemId,
        questionTemplateId: questionTemplateId,
        reviewedAt: now,
        rating: rating.value,
        responseMs: responseTime?.inMilliseconds,
        seed: seed,
        selectedNodeId: selectedNodeId,
        schedulerConfigVersion: config.version,
        stateAfter: after.state,
        stepAfter: after.step,
        stabilityAfter: after.stability,
        difficultyAfter: after.difficulty,
        dueAfter: after.due,
      );

      // Companions built with nullToAbsent: false write NULLs too: an upsert
      // must clear `step` when the item graduates to Review.
      await db.into(db.reviewEvents).insert(event.toCompanion(false));
      await db.batch(
        (batch) => batch.insertAll(db.reviewEventOptions, [
          for (var i = 0; i < optionNodeIds.length; i++)
            ReviewEventOptionsCompanion.insert(
              reviewEventId: event.id,
              position: i + 1,
              knowledgeNodeId: optionNodeIds[i],
            ),
        ]),
      );
      await db
          .into(db.reviewStates)
          .insertOnConflictUpdate(after.toCompanion(false));
      return ReviewResult(event: event, before: before, after: after);
    });
  }
}
