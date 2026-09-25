import '../questions/exercise_format.dart';
import '../questions/format_registry.dart';

export '../questions/exercise_format.dart' show FormatFamily;

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

/// The formats built today, by ID: those of the format registry (F3). A
/// reverse question has its format's family: a reverse flashcard is recall,
/// a reverse MCQ recognition.
///
/// A new format registers in `appFormats` and adds itself to every relation
/// type in `coverage_policy.yaml` (audit COV-3).
final Map<String, CoverageFormat> builtFormats = {
  for (final format in appFormats.formats)
    format.id: CoverageFormat(
      format.id,
      format.family,
      isObjective: format.isObjective,
    ),
};
