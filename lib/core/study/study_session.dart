import 'dart:collection';

import 'review_service.dart';
import 'study_planner.dart';

/// A study session in progress: the planned cards in order, with any card
/// left on a learning step shown again later in the session (audit FS-11).
class StudySession {
  StudySession(StudyPlan plan)
    : certificationId = plan.certificationId,
      planned = plan.cards.length,
      _queue = Queue.of(plan.cards);

  final String certificationId;

  /// Distinct items planned for the session.
  final int planned;

  final Queue<StudyCard> _queue;

  /// Answers given so far, repeats included.
  int answered = 0;

  /// Answers other than Again.
  int correct = 0;

  /// Co-items a composite exercise graded along with the card: bonus
  /// reviews, which use no session slot (question-system §9).
  int bonus = 0;

  /// The card to study now; null once the session is finished.
  StudyCard? get current => _queue.isEmpty ? null : _queue.first;

  /// Cards still to study, repeats included.
  int get remaining => _queue.length;

  /// The cards still to study, in order, the current one first.
  List<StudyCard> get queued => List.unmodifiable(_queue);

  bool get isFinished => _queue.isEmpty;

  /// Completes the current card with [result]. A card still on a learning or
  /// relearning step goes to the back of the queue: the package's steps last
  /// minutes, and the learner should not have to come back for them.
  void complete(ReviewResult result) => completeExercise([result]);

  /// Completes the current card with the results of its exercise: the
  /// card's own, and any co-items' (bonus reviews). A co-item just reviewed
  /// leaves the queue, unless it is on a learning step, when it goes to the
  /// back like any card.
  void completeExercise(List<ReviewResult> results) {
    final card = current;
    final own = [
      for (final result in results)
        if (result.after.knowledgeItemId == card?.itemId) result,
    ];
    if (card == null || own.length != 1) {
      throw StateError(
        'Answered ${[for (final r in results) r.after.knowledgeItemId]}, '
        'but the current card is ${card?.itemId}',
      );
    }
    final result = own.single;
    _queue.removeFirst();
    answered++;
    if (result.isCorrect) correct++;
    for (final co in results) {
      if (identical(co, result)) continue;
      bonus++;
      final itemId = co.after.knowledgeItemId;
      final queued = _queue.where((c) => c.itemId == itemId).firstOrNull;
      _queue.removeWhere((c) => c.itemId == itemId);
      if (queued != null && co.staysInSession) {
        _queue.addLast(
          queued.reviewed(co.after, templateId: co.event.questionTemplateId),
        );
      }
    }
    if (result.staysInSession) {
      _queue.addLast(
        card.reviewed(
          result.after,
          templateId: result.event.questionTemplateId,
        ),
      );
    }
  }
}
