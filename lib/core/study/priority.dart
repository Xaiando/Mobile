import 'dart:math';

/// The tuning of the study priority score (spec §G, validation A-1, A-3,
/// A-4). The values are provisional (audit A-7) until logged reviews can be
/// used to fit them.
class PriorityWeights {
  const PriorityWeights({
    this.urgencyExponent = 1,
    this.relevanceExponent = 1,
    this.lapseExponent = 1,
    this.prerequisiteExponent = 1,
    this.lapseWeight = 0.2,
    this.prerequisiteWeight = 2,
    this.prerequisiteDecay = 0.5,
  });

  /// αU, αC, αL and αP: how strongly each factor shapes the ranking. With a
  /// product of powers every weight can change the order (A-1).
  final double urgencyExponent;
  final double relevanceExponent;
  final double lapseExponent;
  final double prerequisiteExponent;

  /// λ in `L = 1 + λ·lapses`: five lapses double an item's priority.
  final double lapseWeight;

  /// β in `P = 1 + β·max γ^depth·(1 − R)`: a forgotten direct dependent
  /// doubles its prerequisite's priority.
  final double prerequisiteWeight;

  /// γ: how much a dependent's weakness fades per prerequisite step.
  final double prerequisiteDecay;
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
    required this.score,
  });

  /// `score = U^αU · C^αC · L^αL · P^αP` (A-1). The journal factor J joins
  /// in Phase 5 (A-5).
  factory Priority.of({
    required double retrievability,
    required double relevance,
    required int lapses,
    required double prerequisiteFactor,
    PriorityWeights weights = const PriorityWeights(),
  }) {
    final urgency = 1 - retrievability;
    final lapseFactor = 1 + weights.lapseWeight * lapses;
    return Priority(
      urgency: urgency,
      relevance: relevance,
      lapseFactor: lapseFactor,
      prerequisiteFactor: prerequisiteFactor,
      score:
          (pow(urgency, weights.urgencyExponent) *
                  pow(relevance, weights.relevanceExponent) *
                  pow(lapseFactor, weights.lapseExponent) *
                  pow(prerequisiteFactor, weights.prerequisiteExponent))
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

  final double score;

  @override
  String toString() =>
      'score ${score.toStringAsFixed(4)} (U ${urgency.toStringAsFixed(3)}, '
      'C $relevance, L $lapseFactor, P ${prerequisiteFactor.toStringAsFixed(3)})';
}

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
