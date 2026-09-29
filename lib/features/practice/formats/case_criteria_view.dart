import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/case_criteria/case_criteria_format.dart';
import '../study_session_controller.dart';

/// Select the four cited criteria from six scenario-specific statements.
class CaseCriteriaView extends ConsumerStatefulWidget {
  const CaseCriteriaView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<CaseCriteriaView> createState() => _CaseCriteriaViewState();
}

class _CaseCriteriaViewState extends ConsumerState<CaseCriteriaView> {
  final _assignments = <String, String>{};

  @override
  void didUpdateWidget(covariant CaseCriteriaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turn.exercise.primaryItemId !=
            widget.turn.exercise.primaryItemId ||
        oldWidget.turn.exercise.seed != widget.turn.exercise.seed) {
      _assignments.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final exercise = turn.exercise as CaseCriteriaExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final theme = Theme.of(context);
    final answer = turn.answer as CaseCriteriaResponse?;
    final assigned = answer?.assignments ?? _assignments;
    final byRole = {for (final c in exercise.criteria) c.role: c};
    final letters = {
      for (final (index, option) in exercise.options.indexed)
        option.id: String.fromCharCode(65 + index),
    };
    final complete =
        assigned.length == 4 && assigned.values.toSet().length == 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Match each response statement to the role it plays in the case.',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final option in exercise.options)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${letters[option.id]}. ${option.summary}'),
            ),
          ),
        const SizedBox(height: 12),
        for (final role in caseCriterionRoles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    caseCriterionLabels[role]!,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!turn.isAnswered)
                  DropdownButton<String>(
                    value: assigned[role],
                    hint: const Text('Choose A–F'),
                    items: [
                      for (final option in exercise.options)
                        DropdownMenuItem(
                          value: option.id,
                          child: Text(letters[option.id]!),
                        ),
                    ],
                    onChanged: (itemId) => setState(() {
                      if (itemId == null) {
                        _assignments.remove(role);
                      } else {
                        _assignments[role] = itemId;
                      }
                    }),
                  )
                else
                  Expanded(
                    child: Text(
                      '${letters[assigned[role]] ?? '—'}'
                      '${assigned[role] == byRole[role]!.itemId ? ' ✓' : ' → ${letters[byRole[role]!.itemId]}'}',
                    ),
                  ),
              ],
            ),
          ),
        if (!turn.isAnswered) ...[
          const Text('Use each statement once.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: complete
                ? () => controller.submit(CaseCriteriaResponse(_assignments))
                : null,
            child: const Text('Check all four criteria'),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text('Cited case rubric', style: theme.textTheme.titleMedium),
          for (final role in caseCriterionRoles)
            _CriterionFeedback(
              byRole[role]!,
              label: caseCriterionLabels[role]!,
            ),
          const SizedBox(height: 12),
          Text(
            'Why the other statements do not fit',
            style: theme.textTheme.titleSmall,
          ),
          for (final option in exercise.options)
            if (option.explanation case final explanation?) ...[
              const SizedBox(height: 8),
              Text('${letters[option.id]}. ${option.summary}'),
              Text(explanation),
            ],
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

class _CriterionFeedback extends StatelessWidget {
  const _CriterionFeedback(this.criterion, {required this.label});

  final CaseCriterion criterion;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${criterion.summary}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(criterion.assertion),
          for (final source in criterion.sources) ...[
            const SizedBox(height: 8),
            Text(source.title, style: theme.textTheme.labelLarge),
            Text([source.publisher, ?source.locator].join(' · ')),
            if (source.url case final url?) SelectableText(url),
          ],
        ],
      ),
    );
  }
}
