import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/short_answer/short_answer_format.dart';
import '../study_session_controller.dart';

/// A short written answer (spec §T): write it, then tick the key points it
/// covered. Each point is an item: ticked is Good, not ticked Again.
class ShortAnswerView extends ConsumerStatefulWidget {
  const ShortAnswerView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<ShortAnswerView> createState() => _ShortAnswerViewState();
}

class _ShortAnswerViewState extends ConsumerState<ShortAnswerView> {
  final _text = TextEditingController();
  final _covered = <String>{};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final exercise = turn.exercise as ShortAnswerExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final theme = Theme.of(context);
    if (!turn.revealed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Your answer',
              alignLabelWithHint: true,
              helperText:
                  'Write it as you would in the exam, then check it against '
                  'the key points.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: controller.reveal,
            child: const Text('Check the key points'),
          ),
        ],
      );
    }

    final response = turn.answer as ShortAnswerResponse?;
    final covered = response?.covered ?? _covered;
    final points = exercise.keyPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WrittenAnswer(response?.text ?? _text.text),
        const SizedBox(height: 16),
        Text(
          response == null
              ? 'Tick the key points your answer covered.'
              : 'You covered ${covered.length} of ${points.length} key '
                    'points.',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final point in points)
          if (response == null)
            CheckboxListTile(
              value: covered.contains(point.itemId),
              onChanged: (value) => setState(
                () => value!
                    ? _covered.add(point.itemId)
                    : _covered.remove(point.itemId),
              ),
              title: Text(point.title),
              subtitle: Text(point.statement),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            )
          else
            ListTile(
              leading: covered.contains(point.itemId)
                  ? Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      semanticLabel: 'Covered',
                    )
                  : Icon(
                      Icons.cancel_outlined,
                      color: theme.colorScheme.error,
                      semanticLabel: 'Not covered',
                    ),
              title: Text(point.title),
              subtitle: Text(point.statement),
              contentPadding: EdgeInsets.zero,
            ),
        const SizedBox(height: 16),
        if (response == null)
          FilledButton(
            onPressed: () => controller.submit(
              ShortAnswerResponse(_text.text, {..._covered}),
            ),
            child: const Text('Done'),
          )
        else
          FilledButton(
            onPressed: controller.next,
            child: const Text('Continue'),
          ),
      ],
    );
  }
}

/// What the learner wrote, kept on screen while the key points are checked.
class _WrittenAnswer extends StatelessWidget {
  const _WrittenAnswer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your answer', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (text.trim().isEmpty)
              Text(
                'You wrote nothing.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Text(text, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
