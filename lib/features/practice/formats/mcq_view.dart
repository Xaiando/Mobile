import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/question_presenter.dart';
import '../study_session_controller.dart';
import 'answer_feedback.dart';

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
            child: _OptionButton(
              option: option,
              outcome: !turn.isAnswered
                  ? null
                  : option == question.answer
                  ? _Outcome.answer
                  : option == turn.selected
                  ? _Outcome.wrongChoice
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

/// How an option turned out once the MCQ is answered.
enum _Outcome { answer, wrongChoice }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.option,
    required this.outcome,
    required this.onPressed,
  });

  final QuestionOption option;
  final _Outcome? outcome;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // An icon as well as a colour, so the outcome never rests on colour alone.
    final (background, foreground, border, icon, label) = switch (outcome) {
      _Outcome.answer => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        colors.primary,
        Icons.check_circle,
        'Correct answer',
      ),
      _Outcome.wrongChoice => (
        colors.errorContainer,
        colors.onErrorContainer,
        colors.error,
        Icons.cancel,
        'Your answer',
      ),
      null => (null, null, null, null, null),
    };
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        side: border == null ? null : BorderSide(color: border, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(child: Text(option.name)),
          if (icon != null)
            Icon(icon, size: 20, color: foreground, semanticLabel: label),
        ],
      ),
    );
  }
}
