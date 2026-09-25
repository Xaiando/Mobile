import 'package:fsrs/fsrs.dart' as fsrs;

import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// Multiple choice: the answer among three wrong options (QG-6), with the
/// options drawn by the presentation's seed (QG-7). Right is Good, wrong is
/// Again (FS-6); the options shown and the choice are logged.
class McqFormat extends ExerciseFormat {
  const McqFormat();

  @override
  String get id => 'mcq';

  @override
  String get label => 'Multiple choice';

  @override
  FormatFamily get family => FormatFamily.recognition;

  @override
  bool get isObjective => true;

  @override
  bool get needsDistractors => true;

  @override
  int requiredDepth(String direction) => direction == 'reverse' ? 3 : 1;

  @override
  int difficultyRank(String direction) => direction == 'reverse' ? 2 : 0;

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) =>
      QuestionPresenter(context.db)
          .present(itemId, questionTemplateId, seed: seed);

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    final question = exercise as PresentedQuestion;
    if (answer is! QuestionOption || !question.options.contains(answer)) {
      throw ArgumentError.value(
        answer,
        'answer',
        'is not one of the options shown',
      );
    }
    return [
      ItemGrade(
        question.knowledgeItemId,
        answer == question.answer ? fsrs.Rating.good : fsrs.Rating.again,
        optionNodeIds: [for (final option in question.options) option.nodeId],
        selectedNodeId: answer.nodeId,
      ),
    ];
  }
}
