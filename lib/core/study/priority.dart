import 'dart:math';

/// The tuning of the study priority score (spec §G, validation A-1, A-3 to
/// A-5). The values are provisional (audit A-7) until logged reviews can be
/// used to fit them.
class PriorityWeights {
  const PriorityWeights({
    this.urgencyExponent = 1,
    this.relevanceExponent = 1,
    this.lapseExponent = 1,
    this.prerequisiteExponent = 1,
    this.journalExponent = 1,
    this.lapseWeight = 0.2,
    this.prerequisiteWeight = 2,
    this.prerequisiteDecay = 0.5,
    this.journalWeight = 1,
    this.journalDecayDays = 30,
  });

  /// αU, αC, αL and αP: how strongly each factor shapes the ranking. With a
  /// product of powers every weight can change the order (A-1).
  final double urgencyExponent;
  final double relevanceExponent;
  final double lapseExponent;
  final double prerequisiteExponent;

  /// αJ: how strongly a wine in the journal shapes the ranking.
  final double journalExponent;

  /// λ in `L = 1 + λ·lapses`: five lapses double an item's priority.
  final double lapseWeight;

  /// β in `P = 1 + β·max γ^depth·(1 − R)`: a forgotten direct dependent
  /// doubles its prerequisite's priority.
  final double prerequisiteWeight;

  /// γ: how much a dependent's weakness fades per prerequisite step.
  final double prerequisiteDecay;

  /// η in `J = 1 + η·e^(−days/τ)`: a wine logged today doubles the
  /// priority of the items about it.
  final double journalWeight;

  /// τ: after this many days the journal's boost has fallen to 1/e.
  final double journalDecayDays;
}

/// The certification relevance factor C for a mapping's importance: core
/// 1.0, secondary 0.5, tertiary 0.25 (audit CM-5, provisional).
double relevanceOf(String importance) => switch (importance) {
  'core' => 1.0,
  'secondary' => 0.5,
  'tertiary' => 0.25,
  _ => throw ArgumentError.value(importance, 'importance'),
};

/// The four factors of an item's priority, and their weighted product.
class Priority {
  const Priority({
    required this.urgency,
    required this.relevance,
    required this.lapseFactor,
    required this.prerequisiteFactor,
    this.journalFactor = 1,
    required this.score,
  });

  /// `score = U^αU · C^αC · L^αL · P^αP · J^αJ` (A-1).
  factory Priority.of({
    required double retrievability,
    required double relevance,
    required int lapses,
    required double prerequisiteFactor,
    double journalFactor = 1,
    PriorityWeights weights = const PriorityWeights(),
  }) {
    final urgency = 1 - retrievability;
    final lapseFactor = 1 + weights.lapseWeight * lapses;
    return Priority(
      urgency: urgency,
      relevance: relevance,
      lapseFactor: lapseFactor,
      prerequisiteFactor: prerequisiteFactor,
      journalFactor: journalFactor,
      score:
          (pow(urgency, weights.urgencyExponent) *
                  pow(relevance, weights.relevanceExponent) *
                  pow(lapseFactor, weights.lapseExponent) *
                  pow(prerequisiteFactor, weights.prerequisiteExponent) *
                  pow(journalFactor, weights.journalExponent))
              .toDouble(),
    );
  }

  /// U = 1 − R: how close the item is to being forgotten.
  final double urgency;

  /// C, from the effective mapping's importance.
  final double relevance;

  /// L = 1 + λ·lapses.
  final double lapseFactor;

  /// P, from the weakest reviewed dependent (see [prerequisiteFactor]).
  final double prerequisiteFactor;

  /// J, from the latest wine in the journal about the item (see
  /// [journalFactor]).
  final double journalFactor;

  final double score;

  @override
  String toString() =>
      'score ${score.toStringAsFixed(4)} (U ${urgency.toStringAsFixed(3)}, '
      'C $relevance, L $lapseFactor, P ${prerequisiteFactor.toStringAsFixed(3)}, '
      'J ${journalFactor.toStringAsFixed(3)})';
}

/// `J = 1 + η·e^(−days/τ)` (A-5), where [daysSince] counts the days since
/// the learner last logged a wine that the item is about; 1 without one.
double journalFactor(
  int? daysSince, {
  PriorityWeights weights = const PriorityWeights(),
}) => daysSince == null
    ? 1
    : 1 +
          weights.journalWeight *
              exp(-max(0, daysSince) / weights.journalDecayDays);

/// `P = 1 + β · max over dependents of γ^depth · weakness` (A-4).
///
/// [dependents] pairs each reviewed item that builds on this one, directly
/// or transitively, with its distance and its weakness, 1 − R. P only ever
/// boosts; it never blocks an item.
double prerequisiteFactor(
  Iterable<({int depth, double weakness})> dependents, {
  PriorityWeights weights = const PriorityWeights(),
}) {
  var worst = 0.0;
  for (final dependent in dependents) {
    worst = max(
      worst,
      (pow(weights.prerequisiteDecay, dependent.depth) * dependent.weakness)
          .toDouble(),
    );
  }
  return 1 + weights.prerequisiteWeight * worst;
}
