import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../study_session_controller.dart';
import 'answer_feedback.dart';
import 'option_button.dart';

/// Multiple choice: four options, then the outcome of each and the
/// assertion.
class McqView extends ConsumerWidget {
  const McqView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final question = turn.question;
    final controller = ref.read(studySessionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OptionButton(
              option: option,
              outcome: !turn.isAnswered
                  ? null
                  : option == question.answer
                  ? OptionOutcome.answer
                  : option == turn.selected
                  ? OptionOutcome.wrongChoice
                  : null,
              onPressed: turn.isAnswered
                  ? null
                  : () => controller.choose(option),
            ),
          ),
        if (turn.isAnswered) ...[
          const SizedBox(height: 8),
          AnswerFeedback(turn),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: controller.next,
            child: const Text('Continue'),
          ),
        ],
      ],
    );
  }
}
