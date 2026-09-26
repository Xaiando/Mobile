import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../study_session_controller.dart';
import 'answer_feedback.dart';

/// A flashcard: reveal the answer, then grade the recall from Again to
/// Easy (FS-6).
class FlashcardView extends ConsumerWidget {
  const FlashcardView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(studySessionProvider.notifier);
    if (!turn.revealed) {
      return FilledButton.tonal(
        onPressed: controller.reveal,
        child: const Text('Show answer'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnswerFeedback(turn),
        const SizedBox(height: 16),
        Text(
          'How well did you recall it?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (rating, label) in const [
              (fsrs.Rating.again, 'Again'),
              (fsrs.Rating.hard, 'Hard'),
              (fsrs.Rating.good, 'Good'),
              (fsrs.Rating.easy, 'Easy'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: rating == fsrs.Rating.good
                      ? FilledButton(
                          onPressed: () => controller.grade(rating),
                          child: Text(label),
                        )
                      : OutlinedButton(
                          onPressed: () => controller.grade(rating),
                          child: Text(label),
                        ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
