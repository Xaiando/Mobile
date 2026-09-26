import 'package:flutter/material.dart';

import '../study_session_controller.dart';

/// The answer and the item's assertion, shown after a single-item question
/// is answered or revealed.
class AnswerFeedback extends StatelessWidget {
  const AnswerFeedback(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = turn.question;
    final result = turn.result;
    final String heading;
    if (!question.isMultipleChoice) {
      heading = question.answer.name;
    } else if (result != null && result.isCorrect) {
      heading = 'Correct: ${question.answer.name}';
    } else {
      heading = 'The answer is ${question.answer.name}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(question.explanation, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
