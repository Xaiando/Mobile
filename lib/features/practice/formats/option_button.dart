import 'package:flutter/material.dart';

import '../../../core/questions/question_presenter.dart';

/// How an option turned out once the question is answered.
enum OptionOutcome { answer, wrongChoice }

/// An answer option: a name to choose, then its outcome, marked by icon as
/// well as colour.
class OptionButton extends StatelessWidget {
  const OptionButton({
    super.key,
    required this.option,
    required this.outcome,
    required this.onPressed,
  });

  final QuestionOption option;
  final OptionOutcome? outcome;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // An icon as well as a colour, so the outcome never rests on colour alone.
    final (background, foreground, border, icon, label) = switch (outcome) {
      OptionOutcome.answer => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        colors.primary,
        Icons.check_circle,
        'Correct answer',
      ),
      OptionOutcome.wrongChoice => (
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
