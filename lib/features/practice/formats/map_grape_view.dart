import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/map/map_exercise.dart';
import '../../map/map_presentation.dart';
import '../study_session_controller.dart';
import 'map_question.dart';

class MapGrapeView extends ConsumerStatefulWidget {
  const MapGrapeView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<MapGrapeView> createState() => _MapGrapeViewState();
}

class _MapGrapeViewState extends ConsumerState<MapGrapeView> {
  var _list = false;
  var _miss = false;

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final exercise = turn.exercise as MapExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final chosen = (turn.answer as MapLocateAnswer?)?.nodeId;
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
              if (turn.isAnswered)
                for (final id in exercise.correctNodeIds)
                  id: MapHighlight.correct,
              if (turn.isAnswered && chosen != null && !correct)
                chosen: MapHighlight.incorrect,
            },
            onTap: turn.isAnswered
                ? null
                : (tap) {
                    if (tap.hit == null) {
                      setState(() => _miss = true);
                      return;
                    }
                    controller.submit(
                      MapLocateAnswer.fromTap(
                        tap,
                        preferredNodeIds: exercise.correctNodeIds,
                      ),
                    );
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
                if (!turn.isAnswered) ...[
                  const Text(
                    'Select one location. More than one may be correct.',
                  ),
                  if (_miss)
                    const Text('Select one of the marked study locations.'),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            correct
                                ? 'Correct: ${exercise.names[chosen]}'
                                : 'The accepted wine areas are marked.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(exercise.explanation),
                        ],
                      ),
                    ),
                  ),
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
