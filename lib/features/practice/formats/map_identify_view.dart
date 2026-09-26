import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/map/map_exercise.dart';
import '../../map/map_presentation.dart';
import '../study_session_controller.dart';
import 'map_question.dart';
import 'option_button.dart';

/// Name it on the map: the area is highlighted, and the learner names it
/// among four of its neighbours.
class MapIdentifyView extends ConsumerWidget {
  const MapIdentifyView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = turn.exercise as MapExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final chosen = turn.selected?.nodeId;
    final correct = exercise.correctNodeIds.contains(chosen);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: MapQuestionMap(
            exercise: exercise,
            revealed: turn.isAnswered,
            highlights: {
              exercise.nodeId: turn.isAnswered
                  ? MapHighlight.correct
                  : MapHighlight.focus,
              if (turn.isAnswered && chosen != null && !correct)
                chosen: MapHighlight.incorrect,
            },
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in exercise.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OptionButton(
                      option: option,
                      outcome: !turn.isAnswered
                          ? null
                          : exercise.correctNodeIds.contains(option.nodeId)
                          ? OptionOutcome.answer
                          : option.nodeId == chosen
                          ? OptionOutcome.wrongChoice
                          : null,
                      onPressed: turn.isAnswered
                          ? null
                          : () => controller.submit(option),
                    ),
                  ),
                if (turn.isAnswered) ...[
                  MapFeedback(
                    exercise: exercise,
                    correct: correct,
                    chosen: chosen,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: controller.next,
                    child: const Text('Continue'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
