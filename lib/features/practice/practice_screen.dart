import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/learner_state.dart';
import '../../core/feedback/feedback_providers.dart';
import '../../core/feedback/question_feedback.dart';
import '../../core/questions/exercise.dart';
import '../../core/questions/question_providers.dart';
import '../home/track_picker.dart';
import 'format_views.dart';
import 'study_session_controller.dart';

/// Practice: adaptive study sessions (spec §M, TASK-007).
class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(studySessionProvider);
    final controller = ref.read(studySessionProvider.notifier);
    final running = session.value != null;
    final exercise = session.value?.turn?.exercise;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: [
          if (exercise != null)
            IconButton(
              tooltip: 'Flag this question',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => flagQuestion(context, ref, exercise),
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

/// The current card: its prompt, then its format's view.
class _TurnView extends ConsumerWidget {
  const _TurnView(this.state);

  final StudySessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = state.turn!;
    final theme = Theme.of(context);
    final view = ref.watch(formatViewsProvider)[turn.exercise.formatId];
    if (view != null && view.expands) {
      // A map fills the height left, and pans instead of scrolling.
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 12),
            _Badges(turn: turn, icon: view.icon),
            const SizedBox(height: 12),
            Text(turn.exercise.prompt, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(child: view.builder(turn)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 12),
        _Badges(turn: turn, icon: view?.icon),
        const SizedBox(height: 16),
        Text(turn.exercise.prompt, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 24),
        if (view == null)
          Text(
            'This version of the app cannot show '
            '"${turn.exercise.formatId}" questions.',
          )
        else
          view.builder(turn),
      ],
    );
  }
}

class _Badges extends ConsumerWidget {
  const _Badges({required this.turn, required this.icon});

  final SessionTurn turn;
  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = turn.card;
    final format = ref.watch(formatRegistryProvider)[turn.exercise.formatId];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Chip(
          avatar: icon == null ? null : Icon(icon, size: 18),
          label: Text(
            '${format?.label ?? turn.exercise.formatId}'
            '${turn.format.isReverse ? ' · reverse' : ''}',
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
                'answers correct across ${session.planned} items'
                '${session.bonus == 0 ? '' : ', and ${session.bonus} more '
                          'items reviewed along the way'}.',
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

/// Asks why [exercise] is off and records the flag on the device (backlog
/// R1). Curators receive it only if the learner exports their data.
Future<void> flagQuestion(
  BuildContext context,
  WidgetRef ref,
  Exercise exercise,
) async {
  final flag = await showDialog<(FlagReason, String)>(
    context: context,
    builder: (context) => _FlagDialog(exercise),
  );
  if (flag == null) return;
  final (reason, note) = flag;
  await ref
      .read(questionFeedbackProvider)
      .flag(
        itemId: exercise.primaryItemId,
        templateId: exercise.questionTemplateId,
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
  const _FlagDialog(this.exercise);

  final Exercise exercise;

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
          Text(widget.exercise.prompt, style: theme.textTheme.bodyMedium),
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
