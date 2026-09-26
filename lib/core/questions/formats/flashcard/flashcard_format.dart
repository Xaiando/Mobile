import 'package:fsrs/fsrs.dart' as fsrs;

import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// A flashcard: the learner recalls the answer, reveals it and grades
/// themselves from Again to Easy (FS-6, QG-8).
class FlashcardFormat extends ExerciseFormat {
  const FlashcardFormat();

  @override
  String get id => 'flashcard';

  @override
  String get label => 'Flashcard';

  @override
  FormatFamily get family => FormatFamily.recall;

  @override
  bool get isObjective => false;

  @override
  int requiredDepth(String direction) => direction == 'reverse' ? 3 : 2;

  @override
  int difficultyRank(String direction) => direction == 'reverse' ? 3 : 1;

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) =>
      QuestionPresenter(context.db)
          .present(itemId, questionTemplateId, seed: seed);

  /// The learner's own grade, an [fsrs.Rating].
  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (answer is! fsrs.Rating) {
      throw ArgumentError.value(answer, 'answer', 'is not a grade');
    }
    return [ItemGrade(exercise.primaryItemId, answer)];
  }
}
