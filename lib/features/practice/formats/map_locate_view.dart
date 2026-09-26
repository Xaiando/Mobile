import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/map/map_exercise.dart';
import '../../map/map_presentation.dart';
import '../study_session_controller.dart';
import 'map_question.dart';

/// Find it on the map: tap the area, or pick its name from a list, the
/// accessible answer mode of GEO-13.
class MapLocateView extends ConsumerStatefulWidget {
  const MapLocateView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<MapLocateView> createState() => _MapLocateViewState();
}

class _MapLocateViewState extends ConsumerState<MapLocateView> {
  bool _list = false;

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final exercise = turn.exercise as MapExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final answer = turn.answer as MapLocateAnswer?;
    final chosen = answer?.nodeId;
    final correct = exercise.correctNodeIds.contains(chosen);
    final names = exercise.names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: MapQuestionMap(
            exercise: exercise,
            revealed: turn.isAnswered,
            highlights: {
              if (turn.isAnswered) exercise.nodeId: MapHighlight.correct,
              if (turn.isAnswered && chosen != null && !correct)
                chosen: MapHighlight.incorrect,
            },
            onTap: turn.isAnswered
                ? null
                : (tap) => controller.submit(MapLocateAnswer.fromTap(tap)),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!turn.isAnswered) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _list = !_list),
                      icon: Icon(_list ? Icons.map_outlined : Icons.list),
                      label: Text(
                        _list ? 'Hide the list' : 'Answer from a list',
                      ),
                    ),
                  ),
                  if (_list)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final MapEntry(key: id, value: name) in names)
                          OutlinedButton(
                            onPressed: () =>
                                controller.submit(MapLocateAnswer.fromList(id)),
                            child: Text(name),
                          ),
                      ],
                    ),
                ] else ...[
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
