import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../app/learner_state.dart';
import '../../core/feedback/feedback_providers.dart';
import '../../core/feedback/question_feedback.dart';
import '../../core/questions/question_presenter.dart';
import '../../core/study/study_planner.dart';
import '../home/track_picker.dart';
import 'study_session_controller.dart';

/// Practice: adaptive study sessions (spec §M, TASK-007).
class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(studySessionProvider);
    final controller = ref.read(studySessionProvider.notifier);
    final running = session.value != null;
    final question = session.value?.turn?.question;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: [
          if (question != null)
            IconButton(
              tooltip: 'Flag this question',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => flagQuestion(context, ref, question),
            ),
          if (running)
            IconButton(
              tooltip: 'End session',
              icon: const Icon(Icons.close),
              onPressed: controller.end,
            ),
        ],
      ),
      body: switch (session) {
        AsyncError(:final error) => _Message(
          icon: Icons.error_outline,
          text: 'The session stopped: $error',
          action: TextButton(
            onPressed: controller.end,
            child: const Text('Back'),
          ),
        ),
        AsyncData(value: final state?) when state.isFinished => _Summary(state),
        AsyncData(value: final state?) => _TurnView(state),
        AsyncData() => const _StartView(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Before a session: what is waiting, and the button to start.
class _StartView extends ConsumerWidget {
  const _StartView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(studyOverviewProvider);
    return switch (overview) {
      AsyncData(value: null) => const _Message(
        icon: Icons.school_outlined,
        text: 'Choose the certification you are studying for.',
        action: TrackPicker(),
      ),
      AsyncData(value: final overview?) => _Message(
        icon: Icons.quiz_outlined,
        text: overview.dueCount + overview.newAvailable == 0
            ? 'All caught up on ${overview.certification.displayName}. '
                  'Come back when reviews are due.'
            : '${overview.certification.displayName}: '
                  '${overview.dueCount} due, '
                  '${overview.newAvailable} new available.',
        action: FilledButton.icon(
          onPressed: overview.dueCount + overview.newAvailable == 0
              ? null
              : ref.read(studySessionProvider.notifier).start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start session'),
        ),
      ),
      AsyncError(:final error) => _Message(
        icon: Icons.error_outline,
        text: 'Your progress could not be read: $error',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// The current card: its question, then the answer.
class _TurnView extends ConsumerWidget {
  const _TurnView(this.state);

  final StudySessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = state.turn!;
    final question = turn.question;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 12),
        _Badges(card: turn.card, question: question),
        const SizedBox(height: 16),
        Text(question.prompt, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 24),
        if (question.isMultipleChoice)
          _MultipleChoice(turn)
        else
          _Flashcard(turn),
      ],
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.card, required this.question});

  final StudyCard card;
  final PresentedQuestion question;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Chip(
          avatar: Icon(
            question.isMultipleChoice ? Icons.list : Icons.style_outlined,
            size: 18,
          ),
          label: Text(
            '${question.isMultipleChoice ? 'Multiple choice' : 'Flashcard'}'
            '${question.direction == 'reverse' ? ' · reverse' : ''}',
          ),
        ),
        if (card.isNew) const Chip(label: Text('New')),
        if (card.isUnverified)
          const Tooltip(
            message:
                'Drafted from public sources; not yet checked by a '
                'qualified reviewer.',
            child: Chip(
              avatar: Icon(Icons.pending_outlined, size: 18),
              label: Text('Unverified'),
            ),
          ),
        if (card.isStale)
          const Chip(
            avatar: Icon(Icons.update, size: 18),
            label: Text('May be out of date'),
          ),
      ],
    );
  }
}

class _MultipleChoice extends ConsumerWidget {
  const _MultipleChoice(this.turn);

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
          _Feedback(turn),
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

class _Flashcard extends ConsumerWidget {
  const _Flashcard(this.turn);

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
        _Feedback(turn),
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

/// The answer and the item's assertion, shown after answering.
class _Feedback extends StatelessWidget {
  const _Feedback(this.turn);

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

class _Summary extends ConsumerWidget {
  const _Summary(this.state);

  final StudySessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(studySessionProvider.notifier);
    final session = state.session;
    return _Message(
      icon: Icons.check_circle_outline,
      text: session.answered == 0
          ? 'Nothing to study right now.'
          : 'Session complete: ${session.correct} of ${session.answered} '
                'answers correct across ${session.planned} items.',
      action: Wrap(
        spacing: 8,
        children: [
          OutlinedButton(onPressed: controller.end, child: const Text('Done')),
          FilledButton(
            onPressed: controller.start,
            child: const Text('Study more'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              text,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Asks why [question] is off and records the flag on the device (backlog
/// R1). Curators receive it only if the learner exports their data.
Future<void> flagQuestion(
  BuildContext context,
  WidgetRef ref,
  PresentedQuestion question,
) async {
  final flag = await showDialog<(FlagReason, String)>(
    context: context,
    builder: (context) => _FlagDialog(question),
  );
  if (flag == null) return;
  final (reason, note) = flag;
  await ref
      .read(questionFeedbackProvider)
      .flag(
        itemId: question.knowledgeItemId,
        templateId: question.questionTemplateId,
        reason: reason,
        note: note,
      );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Thank you. The flag is kept on this device and goes out only in '
        'your data export.',
      ),
    ),
  );
}

class _FlagDialog extends StatefulWidget {
  const _FlagDialog(this.question);

  final PresentedQuestion question;

  @override
  State<_FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends State<_FlagDialog> {
  FlagReason _reason = FlagReason.wrong;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Flag this question'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.question.prompt, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          RadioGroup<FlagReason>(
            groupValue: _reason,
            onChanged: (reason) => setState(() => _reason = reason!),
            child: Column(
              children: [
                for (final reason in FlagReason.values)
                  RadioListTile<FlagReason>(
                    value: reason,
                    title: Text(reason.label),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What is off? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_reason, _note.text)),
          child: const Text('Flag'),
        ),
      ],
    );
  }
}
