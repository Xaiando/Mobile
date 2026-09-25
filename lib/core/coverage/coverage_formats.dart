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

/// A question format as the coverage checker sees it (question-system §2).
final class CoverageFormat {
  const CoverageFormat(this.id, this.family, {required this.isObjective});

  /// The `question_templates.mode` whose questions have this format.
  final String id;
  final FormatFamily family;

  /// Graded by the app rather than by the learner (§3). Only the flashcard
  /// and the short written answer are self-graded.
  final bool isObjective;

  @override
  String toString() => id;
}

/// The formats built today, by ID. A reverse question has its format's
/// family: a reverse flashcard is recall, a reverse MCQ recognition.
///
/// Each format task adds its format here and to every relation type in
/// `coverage_policy.yaml` (audit COV-3). Task F3 moves this catalogue into
/// the format registry.
const builtFormats = {
  'flashcard': CoverageFormat(
    'flashcard',
    FormatFamily.recall,
    isObjective: false,
  ),
  'mcq': CoverageFormat('mcq', FormatFamily.recognition, isObjective: true),
};
