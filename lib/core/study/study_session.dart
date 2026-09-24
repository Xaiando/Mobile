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

  /// The card to study now; null once the session is finished.
  StudyCard? get current => _queue.isEmpty ? null : _queue.first;

  /// Cards still to study, repeats included.
  int get remaining => _queue.length;

  bool get isFinished => _queue.isEmpty;

  /// Completes the current card with [result]. A card still on a learning or
  /// relearning step goes to the back of the queue: the package's steps last
  /// minutes, and the learner should not have to come back for them.
  void complete(ReviewResult result) {
    final card = current;
    if (card == null || card.itemId != result.after.knowledgeItemId) {
      throw StateError(
        'Answered ${result.after.knowledgeItemId}, '
        'but the current card is ${card?.itemId}',
      );
    }
    _queue.removeFirst();
    answered++;
    if (result.isCorrect) correct++;
    if (result.staysInSession) _queue.addLast(card.reviewed(result.after));
  }
}
