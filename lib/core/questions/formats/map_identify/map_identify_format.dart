import 'dart:math';

import 'package:fsrs/fsrs.dart' as fsrs;

import '../../exercise.dart';
import '../../question_presenter.dart';
import '../map/map_exercise.dart';

/// Name it on the map (backlog G4): the area is highlighted on its frame,
/// and the learner names it among four of the frame's candidates. Right is
/// Good, wrong is Again, as for an MCQ (FS-6); the options shown are logged.
class MapIdentifyFormat extends MapFormat {
  const MapIdentifyFormat();

  @override
  String get id => 'map_identify';

  @override
  String get label => 'Name it on the map';

  @override
  int requiredDepth(String direction) => 1;

  @override
  int difficultyRank(String direction) => 5;

  /// A labelled map would name the answer, so it starts at outline.
  @override
  MapMode modeFor(MapMode mode) =>
      mode == MapMode.labelled ? MapMode.outline : mode;

  /// The answer and three other candidates of the frame, drawn by the seed
  /// and shuffled (QG-6, QG-7). A frame always holds four (geography §5).
  @override
  List<QuestionOption> optionsFor(
    QuestionOption answer,
    List<QuestionOption> candidates,
    Random random,
  ) {
    final others = [
      for (final c in candidates)
        if (c != answer) c,
    ]..shuffle(random);
    return [answer, ...others.take(3)]..shuffle(random);
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    final map = exercise as MapExercise;
    if (answer is! QuestionOption || !map.options.contains(answer)) {
      throw ArgumentError.value(
        answer,
        'answer',
        'is not one of the options shown',
      );
    }
    return [
      ItemGrade(
        map.primaryItemId,
        map.correctNodeIds.contains(answer.nodeId)
            ? fsrs.Rating.good
            : fsrs.Rating.again,
        optionNodeIds: [for (final option in map.options) option.nodeId],
        selectedNodeId: answer.nodeId,
        payload: {'frame': map.frame.parent.id, 'mode': map.mode.name},
      ),
    ];
  }
}
