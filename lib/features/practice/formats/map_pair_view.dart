import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/questions/formats/map/map_exercise.dart';
import '../../../core/questions/formats/map_pair/map_pair_format.dart';
import '../../map/map_presentation.dart';
import '../study_session_controller.dart';
import 'map_question.dart';

/// Select each named place independently, revise selections, then submit
/// together. Both map taps and the accessible list use the same answer.
class MapPairView extends ConsumerStatefulWidget {
  const MapPairView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<MapPairView> createState() => _MapPairViewState();
}

class _MapPairViewState extends ConsumerState<MapPairView> {
  final _selections = <String, MapLocateAnswer>{};
  var _active = 0;
  var _list = false;

  void _select(MapLocateAnswer answer, MapPairExercise exercise) {
    if (answer.nodeId == null) return;
    setState(() {
      _selections[exercise.places[_active].itemId] = answer;
      final next = exercise.places.indexWhere(
        (p) => !_selections.containsKey(p.itemId),
      );
      if (next >= 0) _active = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turn;
    final exercise = turn.exercise as MapPairExercise;
    final map = exercise.map;
    final controller = ref.read(studySessionProvider.notifier);
    final selections =
        (turn.answer as MapPairAnswer?)?.selections ?? _selections;
    final names = map.names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: MapQuestionMap(
            exercise: map,
            revealed: turn.isAnswered,
            highlights: {
              if (!turn.isAnswered)
                for (final selected in selections.values)
                  ?selected.nodeId: MapHighlight.focus,
              if (turn.isAnswered) ...{
                for (final place in exercise.places)
                  place.nodeId: MapHighlight.correct,
                for (final place in exercise.places)
                  if (selections[place.itemId]?.nodeId case final id?
                      when id != place.nodeId &&
                          !exercise.places.any((p) => p.nodeId == id))
                    id: MapHighlight.incorrect,
              },
            },
            onTap: turn.isAnswered
                ? null
                : (tap) => _select(
                    MapLocateAnswer.fromTap(
                      tap,
                      preferredNodeId: exercise.places[_active].nodeId,
                    ),
                    exercise,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          flex: 3,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, place) in exercise.places.indexed)
                  ListTile(
                    selected: !turn.isAnswered && index == _active,
                    leading: turn.isAnswered
                        ? Icon(
                            selections[place.itemId]?.nodeId == place.nodeId
                                ? Icons.check_circle
                                : Icons.cancel,
                          )
                        : CircleAvatar(child: Text('${index + 1}')),
                    title: Text(place.name),
                    subtitle: Text(
                      turn.isAnswered
                          ? '${selections[place.itemId]?.nodeId == place.nodeId ? 'Correct' : 'Correct location: ${place.name}'}. ${place.explanation}'
                          : map.names[selections[place.itemId]?.nodeId] ??
                                'Tap its location on the map',
                    ),
                    onTap: turn.isAnswered
                        ? null
                        : () => setState(() => _active = index),
                  ),
                if (!turn.isAnswered) ...[
                  Text(
                    'Selecting: ${exercise.places[_active].name}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
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
                                _select(MapLocateAnswer.fromList(id), exercise),
                            child: Text(name),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: selections.length == exercise.places.length
                        ? () => controller.submit(MapPairAnswer(_selections))
                        : null,
                    child: Text('Check ${exercise.places.length} locations'),
                  ),
                ] else
                  FilledButton(
                    onPressed: controller.next,
                    child: const Text('Continue'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
