import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/reasoning/reasoning_format.dart';
import '../../../core/questions/question_presenter.dart';
import '../study_session_controller.dart';
import 'option_button.dart';

/// A bounded consequence choice, followed by its cited reasoning chain.
class ReasoningView extends ConsumerWidget {
  const ReasoningView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = turn.exercise as ReasoningExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final selected = turn.answer is QuestionOption
        ? turn.answer as QuestionOption
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in exercise.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OptionButton(
              option: option,
              outcome: !turn.isAnswered
                  ? null
                  : option == exercise.answer
                  ? OptionOutcome.answer
                  : option == selected
                  ? OptionOutcome.wrongChoice
                  : null,
              onPressed: turn.isAnswered
                  ? null
                  : () => controller.submit(option),
            ),
          ),
        if (turn.isAnswered) ...[
          const SizedBox(height: 8),
          ReasoningFeedback(turn),
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

/// Explanation-only evidence never appears as an independently graded point.
class ReasoningFeedback extends StatelessWidget {
  const ReasoningFeedback(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context) {
    if (!turn.isAnswered) return const SizedBox.shrink();
    final exercise = turn.exercise as ReasoningExercise;
    final theme = Theme.of(context);
    final correct = turn.result!.isCorrect;
    final assessed = {
      for (final result in turn.results!) result.after.knowledgeItemId,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct ? Icons.check_circle : Icons.cancel_outlined,
                  color: correct
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    correct
                        ? 'Correct: ${exercise.answer.name}'
                        : 'The supported answer is ${exercise.answer.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              correct
                  ? 'All ${assessed.length} learning points were reviewed as '
                        'recalled.'
                  : 'The final learning point needs another review. '
                        'Supporting points were not graded.',
            ),
            const SizedBox(height: 16),
            Text('The reasoning chain', style: theme.textTheme.titleSmall),
            for (var index = 0; index < exercise.chainEvidence.length; index++)
              _Evidence(
                exercise.chainEvidence[index],
                key: ValueKey(
                  'reasoning-chain-${exercise.chainEvidence[index].itemId}',
                ),
                label:
                    '${index + 1}. '
                    '${exercise.chainEvidence[index].itemId == exercise.primaryItemId ? 'Final learning point' : 'Supporting point'}'
                    '${assessed.contains(exercise.chainEvidence[index].itemId) ? '' : ' · not graded'}',
              ),
            if (exercise.contrasts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Why the other choices do not fit',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'These sources explain the alternatives. No extra learning '
                'points are reviewed for these explanations.',
              ),
              for (final contrast in exercise.contrasts) ...[
                const SizedBox(height: 16),
                Text(contrast.option.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(contrast.statement),
                for (final evidence in contrast.evidence)
                  _Evidence(evidence, label: 'Explanation only'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence(this.evidence, {required this.label, super.key});

  final ReasoningEvidence evidence;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(evidence.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(evidence.statement),
          for (final source in evidence.sources) ...[
            const SizedBox(height: 8),
            Text(source.title, style: theme.textTheme.labelLarge),
            Text([source.publisher, ?source.locator].join(' · ')),
            if (source.url case final url?)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: SelectableText(url),
              ),
          ],
        ],
      ),
    );
  }
}
