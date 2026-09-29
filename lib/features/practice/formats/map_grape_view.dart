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
  final _selections = <String, MapLocateAnswer>{};

  void _toggle(MapLocateAnswer answer) {
    final id = answer.nodeId;
    if (id == null) {
      setState(() => _miss = true);
      return;
    }
    setState(() {
      if (_selections.containsKey(id)) {
        _selections.remove(id);
      } else {
        _selections[id] = answer;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final exercise = turn.exercise as MapExercise;
    final controller = ref.read(studySessionProvider.notifier);
    final chosen = switch (turn.answer) {
      MapLocateAnswer(:final nodeId) => nodeId,
      _ => null,
    };
    final correct = exercise.correctNodeIds.contains(chosen);
    final selected = switch (turn.answer) {
      MapMultiLocateAnswer(:final selections) => {
        for (final answer in selections) ?answer.nodeId,
      },
      _ => _selections.keys.toSet(),
    };
    final setCorrect =
        selected.length == exercise.correctNodeIds.length &&
        selected.containsAll(exercise.correctNodeIds);
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
              if (!turn.isAnswered && exercise.selectAll)
                for (final id in selected) id: MapHighlight.focus,
              if (turn.isAnswered)
                for (final id in exercise.correctNodeIds)
                  id: MapHighlight.correct,
              if (turn.isAnswered && chosen != null && !correct)
                chosen: MapHighlight.incorrect,
              if (turn.isAnswered && exercise.selectAll)
                for (final id in selected.difference(exercise.correctNodeIds))
                  id: MapHighlight.incorrect,
            },
            onTap: turn.isAnswered
                ? null
                : (tap) {
                    if (tap.hit == null) {
                      setState(() => _miss = true);
                      return;
                    }
                    if (exercise.selectAll) {
                      _toggle(MapLocateAnswer.fromTap(tap));
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
                  Text(
                    exercise.selectAll
                        ? 'Select every correct marked location, then check your set.'
                        : 'Select one location. More than one may be correct.',
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
                            onPressed: () => exercise.selectAll
                                ? _toggle(MapLocateAnswer.fromList(id))
                                : controller.submit(
                                    MapLocateAnswer.fromList(id),
                                  ),
                            child: Text(
                              exercise.selectAll && selected.contains(id)
                                  ? '✓ $name'
                                  : name,
                            ),
                          ),
                      ],
                    ),
                  if (exercise.selectAll) ...[
                    const SizedBox(height: 8),
                    Text('${selected.length} selected'),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => controller.submit(
                              MapMultiLocateAnswer(_selections.values.toList()),
                            ),
                      child: const Text('Check locations'),
                    ),
                  ],
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.selectAll
                                ? setCorrect
                                      ? 'Correct: all ${selected.length} locations found.'
                                      : 'The complete set of accepted wine areas is marked.'
                                : correct
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
