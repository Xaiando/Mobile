import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/typed/typed_format.dart';
import '../study_session_controller.dart';

/// Typed recall: the learner types the answer and the app grades it: exact,
/// a slip of one letter (Hard), or wrong.
class TypedView extends ConsumerStatefulWidget {
  const TypedView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<TypedView> createState() => _TypedViewState();
}

class _TypedViewState extends ConsumerState<TypedView> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _check() {
    if (_text.text.trim().isEmpty) return;
    ref.read(studySessionProvider.notifier).submit(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final question = turn.exercise as TypedQuestion;
    final controller = ref.read(studySessionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          enabled: !turn.isAnswered,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Your answer',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _check(),
        ),
        const SizedBox(height: 12),
        if (!turn.isAnswered)
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => FilledButton(
              onPressed: _text.text.trim().isEmpty ? null : _check,
              child: const Text('Check'),
            ),
          )
        else ...[
          TypedFeedback(question, typed: turn.answer! as String),
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

/// How a typed answer was graded, with the answer and its explanation.
class TypedFeedback extends StatelessWidget {
  const TypedFeedback(this.question, {required this.typed, super.key});

  final TypedQuestion question;
  final String typed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (outcome, matched) = TypedFormat.outcome(question, typed);
    final answer = question.answer.name;
    final (icon, colour, heading) = switch (outcome) {
      TypedOutcome.exact => (
        Icons.check_circle,
        theme.colorScheme.primary,
        matched == answer ? 'Correct: $answer' : 'Correct: $matched',
      ),
      TypedOutcome.near => (
        Icons.spellcheck,
        theme.colorScheme.tertiary,
        'Almost: $matched. Check the spelling.',
      ),
      TypedOutcome.partial => (
        Icons.more_horiz,
        theme.colorScheme.tertiary,
        'Almost: the full answer is $matched.',
      ),
      TypedOutcome.wrong => (
        Icons.cancel,
        theme.colorScheme.error,
        'The answer is $answer',
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colour),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(heading, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (outcome != TypedOutcome.exact) ...[
              const SizedBox(height: 4),
              Text('You typed: $typed', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Text(question.explanation, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
