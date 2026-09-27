import '../../../curriculum/curriculum_validator.dart'
    show regulatoryRelationTypes;
import '../../question_presenter.dart';
import 'numeric_answer.dart';

/// One current quantity, preserving its canonical values and presentation unit.
final class NumericQuestion extends PresentedQuestion {
  const NumericQuestion({
    required super.knowledgeItemId,
    required super.questionTemplateId,
    required super.prompt,
    required super.answer,
    required super.explanation,
    required super.seed,
    required this.relationType,
    required this.canonicalMinimum,
    double? canonicalMaximum,
    required this.canonicalUnit,
    required this.displayUnit,
    this.exactTolerance = 0,
    this.tolerance = 0,
  }) : canonicalMaximum = canonicalMaximum ?? canonicalMinimum,
       super(direction: 'forward', mode: 'numeric', options: const []);

  final String relationType;
  final double canonicalMinimum;
  final double canonicalMaximum;
  final String canonicalUnit;
  final String displayUnit;

  /// Good expands the canonical band by this width on each side.
  final double exactTolerance;

  /// TOTAL outer width, not an addition to [exactTolerance]: inside this
  /// expanded band but outside the exact band is Hard.
  final double tolerance;

  bool get isRegulatory => regulatoryRelationTypes.contains(relationType);
  bool get isLegalMinimum =>
      const {'MIN_AGEING', 'MIN_WOOD_AGEING'}.contains(relationType);

  bool get allowsInterval =>
      !isRegulatory &&
      canonicalMinimum.isFinite &&
      canonicalMaximum.isFinite &&
      canonicalMinimum < canonicalMaximum;

  double get displayMinimum => numericValueInUnit(
    canonicalMinimum,
    fromUnit: canonicalUnit,
    toUnit: displayUnit,
  );

  double get displayMaximum => numericValueInUnit(
    isLegalMinimum ? canonicalMinimum : canonicalMaximum,
    fromUnit: canonicalUnit,
    toUnit: displayUnit,
  );

  /// Feedback only: views must not expose these values before submission.
  String get displayAnswer {
    final low = formatNumericValue(displayMinimum);
    final high = formatNumericValue(displayMaximum);
    return '${low == high ? low : '$low–$high'} $displayUnit';
  }
}
