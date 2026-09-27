import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/numeric/numeric_format.dart';
import '../study_session_controller.dart';

/// An objective quantity answer, with an optional range for genuine ranges.
class NumericView extends ConsumerStatefulWidget {
  const NumericView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<NumericView> createState() => _NumericViewState();
}

class _NumericViewState extends ConsumerState<NumericView> {
  final _single = TextEditingController();
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();
  final _maximumFocus = FocusNode();
  var _asRange = false;
  var _submitting = false;
  String? _error;

  @override
  void didUpdateWidget(covariant NumericView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.turn.exercise, widget.turn.exercise)) {
      _single.clear();
      _minimum.clear();
      _maximum.clear();
      _asRange = false;
      _submitting = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _single.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _maximumFocus.dispose();
    super.dispose();
  }

  (NumericAnswer?, String?) _parseAnswer(NumericQuestion question) {
    if (!_asRange) {
      final answer = NumericAnswer.tryParse(
        _single.text,
        defaultUnit: question.displayUnit,
      );
      if (answer == null || !answer.isValid) {
        return (null, 'Enter a valid number using a decimal point.');
      }
      if (answer.isInterval) {
        return (
          null,
          question.allowsInterval
              ? 'Enter one number, or choose Answer with a range.'
              : 'Enter one number for this question.',
        );
      }
      return (answer, null);
    }

    final minimum = NumericAnswer.tryParse(
      _minimum.text,
      defaultUnit: question.displayUnit,
    );
    final maximum = NumericAnswer.tryParse(
      _maximum.text,
      defaultUnit: question.displayUnit,
    );
    if (minimum == null ||
        maximum == null ||
        !minimum.isValid ||
        !maximum.isValid ||
        minimum.isInterval ||
        maximum.isInterval) {
      return (null, 'Enter a valid number at each end of the range.');
    }
    if (!unitMatches(minimum.unit, maximum.unit)) {
      return (null, 'Use the same unit at both ends of the range.');
    }
    final answer = NumericAnswer.interval(
      minimum.minimum,
      maximum.minimum,
      unit: minimum.unit,
    );
    if (!answer.isValid) {
      return (null, 'The lower value must not exceed the upper value.');
    }
    return (answer, null);
  }

  Future<void> _check() async {
    if (widget.turn.isAnswered || _submitting) return;
    final question = widget.turn.exercise as NumericQuestion;
    final (answer, error) = _parseAnswer(question);
    if (answer == null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref.read(studySessionProvider.notifier).submit(answer);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String unit,
    required bool enabled,
    FocusNode? focusNode,
    bool autofocus = false,
    bool next = false,
  }) => TextField(
    controller: controller,
    focusNode: focusNode,
    enabled: enabled,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: next ? TextInputAction.next : TextInputAction.done,
    decoration: InputDecoration(
      labelText: label,
      suffixText: unit,
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) {
      if (_error != null) setState(() => _error = null);
    },
    onSubmitted: (_) {
      if (next) {
        _maximumFocus.requestFocus();
      } else {
        _check();
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final question = turn.exercise as NumericQuestion;
    final enabled = !turn.isAnswered && !_submitting;
    final controller = ref.read(studySessionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question.allowsInterval)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Answer with a range'),
            value: _asRange,
            onChanged: enabled
                ? (value) => setState(() {
                    _asRange = value;
                    _error = null;
                  })
                : null,
          ),
        if (_asRange) ...[
          _field(
            controller: _minimum,
            label: 'Lower value',
            unit: question.displayUnit,
            enabled: enabled,
            autofocus: true,
            next: true,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _maximum,
            focusNode: _maximumFocus,
            label: 'Upper value',
            unit: question.displayUnit,
            enabled: enabled,
          ),
        ] else
          _field(
            controller: _single,
            label: 'Your answer',
            unit: question.displayUnit,
            enabled: enabled,
            autofocus: true,
          ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!turn.isAnswered)
          ListenableBuilder(
            listenable: Listenable.merge([_single, _minimum, _maximum]),
            builder: (context, _) {
              final hasInput = _asRange
                  ? _minimum.text.trim().isNotEmpty &&
                        _maximum.text.trim().isNotEmpty
                  : _single.text.trim().isNotEmpty;
              return FilledButton(
                onPressed: enabled && hasInput ? _check : null,
                child: Text(_submitting ? 'Checking…' : 'Check'),
              );
            },
          )
        else ...[
          NumericFeedback(turn),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : controller.next,
            child: const Text('Continue'),
          ),
        ],
      ],
    );
  }
}

/// The target, grade and explanation appear only after a submitted answer.
class NumericFeedback extends StatelessWidget {
  const NumericFeedback(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context) {
    if (!turn.isAnswered) return const SizedBox.shrink();
    final question = turn.exercise as NumericQuestion;
    final submitted = turn.answer;
    final answer = switch (submitted) {
      final NumericAnswer value => value,
      final String text => NumericAnswer.tryParse(
        text,
        defaultUnit: question.displayUnit,
      ),
      _ => null,
    };
    final theme = Theme.of(context);
    final outcome = switch (submitted) {
      final NumericAnswer value => NumericFormat.outcome(question, value),
      final String text => NumericFormat.outcome(question, text),
      _ => NumericOutcome.wrong,
    };
    final (icon, colour, heading) = switch (outcome) {
      NumericOutcome.exact => (
        Icons.check_circle,
        theme.colorScheme.primary,
        'Correct',
      ),
      NumericOutcome.near => (
        Icons.more_horiz,
        theme.colorScheme.tertiary,
        'Close',
      ),
      NumericOutcome.wrong => (
        Icons.cancel_outlined,
        theme.colorScheme.error,
        'Not correct',
      ),
    };
    final entered = answer == null || !answer.isValid
        ? 'Invalid numeric input'
        : answer.isInterval
        ? '${formatNumericValue(answer.minimum)}–'
              '${formatNumericValue(answer.maximum!)} ${answer.unit}'
        : '${formatNumericValue(answer.minimum)} ${answer.unit}';
    final grade = turn.result!.rating.name;
    final gradeLabel = '${grade[0].toUpperCase()}${grade.substring(1)}';
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
            const SizedBox(height: 8),
            Text(
              '${question.allowsInterval ? 'Target range' : 'Target'}: '
              '${question.displayAnswer}',
            ),
            Text('You entered: $entered'),
            Text('Review grade: $gradeLabel'),
            const SizedBox(height: 8),
            Text(question.explanation, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
