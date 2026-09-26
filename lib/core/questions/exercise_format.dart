import 'package:fsrs/fsrs.dart' as fsrs;

import '../database/app_database.dart';
import 'exercise.dart';

/// The skills a question format trains (question-system §3).
enum FormatFamily {
  /// Producing an answer from memory.
  recall,

  /// Choosing among plausible answers.
  recognition,

  /// Knowing where things are and how places relate.
  spatial,

  /// Relations among several facts, quantities and terms.
  structured,

  /// Applying principles to reach a conclusion.
  reasoning,
}

/// How well an item is remembered, by its FSRS stability: the rungs of the
/// presentation ladder (QF-7, question-system §5).
enum MemoryBand {
  /// New, or on a learning or relearning step.
  learning,

  /// Stability under 7 days.
  young,

  /// Stability from 7 to 30 days.
  maturing,

  /// Stability of 30 days or more.
  mature;

  /// The band of an item whose memory state is [state], which is null while
  /// the item is new.
  static MemoryBand of(ReviewState? state) {
    if (state == null || state.state != fsrs.State.review.value) {
      return learning;
    }
    if (state.stability < 7) return young;
    if (state.stability < 30) return maturing;
    return mature;
  }
}

/// How ingestion generates a format's questions.
enum FormatGeneration {
  /// One `questions` row per eligible item and template.
  single,

  /// Exercise pools, which the format generates itself (QF-10).
  pooled,
}

/// What a format presents from: the curriculum, and the time, so that a
/// composite format can prefer due co-items.
class PresentationContext {
  const PresentationContext(this.db, {required this.now});

  final AppDatabase db;
  final DateTime now;
}

/// What a format generates from, inside the ingestion transaction: its
/// pools, or which items it can ask.
class GeneratorContext {
  const GeneratorContext(this.db, {required this.today, required this.items});

  final AppDatabase db;

  /// The date, `YYYY-MM-DD`, on which relations must be in force.
  final String today;

  /// The items in force, the only ones a pool may hold (FS-13).
  final List<KnowledgeItem> items;
}

/// A question format, plugged in (question-system §9): how its questions
/// are generated, presented and graded, and what they practise.
///
/// A format is one file per layer: its [ExerciseFormat] in
/// `lib/core/questions/formats/<id>/`, and its practice view in
/// `lib/features/practice/formats/`. Each registers with one line.
abstract class ExerciseFormat {
  const ExerciseFormat();

  /// The `question_templates.mode` of its templates.
  String get id;

  /// What the learner sees it called, e.g. "Multiple choice".
  String get label;

  FormatFamily get family;

  /// Graded by the app rather than by the learner (§3).
  bool get isObjective;

  FormatGeneration get generation => FormatGeneration.single;

  /// Whether a single-item question needs wrong answers to show: an MCQ
  /// exists only with enough of them (QG-12).
  bool get needsDistractors => false;

  /// The `minimum_depth` at which a track serves this format in
  /// [direction], `forward` or `reverse` (CM-6, QF-6).
  int requiredDepth(String direction);

  /// Orders a new item's formats, easiest first (FS-15).
  int difficultyRank(String direction);

  /// The memory bands in which the ladder prefers this format in
  /// [direction] (F4, QF-7): recognition while an item is learnt, recall
  /// once it is young, reverse and structured formats as it matures, and
  /// reasoning when it is mature. A spatial format fits every band, its
  /// mode hardening with the band.
  Set<MemoryBand> preferredBands(String direction) {
    if (direction == 'reverse') return const {MemoryBand.maturing};
    return switch (family) {
      FormatFamily.recognition => const {MemoryBand.learning},
      FormatFamily.recall => const {MemoryBand.young},
      FormatFamily.structured => const {MemoryBand.young, MemoryBand.maturing},
      FormatFamily.spatial => MemoryBand.values.toSet(),
      FormatFamily.reasoning => const {MemoryBand.mature},
    };
  }

  /// Writes the pools of [template] and returns how many; only a pooled
  /// format has any.
  Future<int> generatePools(
    GeneratorContext context,
    QuestionTemplate template,
  ) => Future.value(0);

  /// Whether this format can ask [item] with [template]: a single-item
  /// format generates its question only then. A map format, for instance,
  /// needs the item's area drawn and framed. Every item is eligible by
  /// default.
  Future<bool> isEligible(
    GeneratorContext context,
    KnowledgeItem item,
    QuestionTemplate template,
  ) => Future.value(true);

  /// What is wrong with [template] for this format, beyond the checks every
  /// template gets: its `parameters`, for instance. [relationTypes] are the
  /// release's relation type IDs. The validator reports each problem.
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) => const [];

  /// Presents [itemId] with [questionTemplateId], fixed by [seed].
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  });

  /// The grades [answer] earns in [exercise], one per item it settles
  /// (question-system §4). Throws an [ArgumentError] for an answer the
  /// exercise cannot take.
  List<ItemGrade> grade(Exercise exercise, Object answer);

  @override
  String toString() => id;
}
