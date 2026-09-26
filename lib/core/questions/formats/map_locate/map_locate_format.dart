import 'package:fsrs/fsrs.dart' as fsrs;

import '../../exercise.dart';
import '../map/map_exercise.dart';

/// Find it on the map (backlog G4): "Find Chablis on the map." The learner
/// taps the area on its frame, or picks its name from the accessible list.
/// A correct node is Good, anything else Again (geography §4); the tap is
/// logged in `answer_payload`.
class MapLocateFormat extends MapFormat {
  const MapLocateFormat();

  @override
  String get id => 'map_locate';

  @override
  String get label => 'Find it on the map';

  /// Recognition on a labelled map from depth 1 (QF-6); the modes without
  /// labels follow the item's memory.
  @override
  int requiredDepth(String direction) => 1;

  /// After the text formats, so a new item starts with its MCQ (FS-15).
  @override
  int difficultyRank(String direction) => 4;

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    final map = exercise as MapExercise;
    if (answer is! MapLocateAnswer) {
      throw ArgumentError.value(answer, 'answer', 'is not a map answer');
    }
    final node = answer.nodeId;
    if (node != null && !map.candidateIds.contains(node)) {
      throw ArgumentError.value(node, 'answer', 'is not a candidate');
    }
    return [
      ItemGrade(
        map.primaryItemId,
        map.correctNodeIds.contains(node)
            ? fsrs.Rating.good
            : fsrs.Rating.again,
        selectedNodeId: node,
        payload: answer.payload(map),
      ),
    ];
  }
}
