import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/study/priority.dart';

void main() {
  test('relevance: core 1.0, secondary 0.5, tertiary 0.25 (CM-5)', () {
    expect(relevanceOf('core'), 1.0);
    expect(relevanceOf('secondary'), 0.5);
    expect(relevanceOf('tertiary'), 0.25);
    expect(() => relevanceOf('essential'), throwsArgumentError);
  });

  test('the score is U^αU · C^αC · L^αL · P^αP (A-1, A-3)', () {
    const weights = PriorityWeights(
      urgencyExponent: 2,
      relevanceExponent: 0.5,
      lapseExponent: 1.5,
      prerequisiteExponent: 3,
      lapseWeight: 0.3,
    );
    final priority = Priority.of(
      retrievability: 0.8,
      relevance: 0.5,
      lapses: 2,
      prerequisiteFactor: 1.2,
      weights: weights,
    );
    expect(priority.urgency, closeTo(0.2, 1e-12));
    expect(priority.lapseFactor, closeTo(1.6, 1e-12));
    expect(
      priority.score,
      closeTo(pow(0.2, 2) * pow(0.5, 0.5) * pow(1.6, 1.5) * pow(1.2, 3), 1e-12),
    );
  });

  test('no factor is zero for a mapped item, so none wipes out the product '
      '(A-3)', () {
    final priority = Priority.of(
      retrievability: 0.9,
      relevance: relevanceOf('tertiary'),
      lapses: 0,
      prerequisiteFactor: prerequisiteFactor(const []),
    );
    expect(priority.lapseFactor, 1);
    expect(priority.prerequisiteFactor, 1);
    expect(priority.score, greaterThan(0));
  });

  test('every weight can change the ranking (A-1)', () {
    // A slightly overdue core item against a long-overdue tertiary item.
    Priority coreItem(PriorityWeights w) => Priority.of(
      retrievability: 0.85,
      relevance: 1,
      lapses: 0,
      prerequisiteFactor: 1,
      weights: w,
    );
    Priority tertiaryItem(PriorityWeights w) => Priority.of(
      retrievability: 0.3,
      relevance: 0.25,
      lapses: 0,
      prerequisiteFactor: 1,
      weights: w,
    );
    const neutral = PriorityWeights();
    const relevanceFirst = PriorityWeights(relevanceExponent: 2);
    expect(tertiaryItem(neutral).score, greaterThan(coreItem(neutral).score));
    expect(
      coreItem(relevanceFirst).score,
      greaterThan(tertiaryItem(relevanceFirst).score),
    );
  });

  test('lapses raise priority gently (L = 1 + λ·lapses)', () {
    double score(int lapses) => Priority.of(
      retrievability: 0.9,
      relevance: 1,
      lapses: lapses,
      prerequisiteFactor: 1,
    ).score;
    expect(score(1), greaterThan(score(0)));
    expect(score(5), closeTo(2 * score(0), 1e-12));
  });

  test('P takes the weakest dependent, faded by distance (A-4)', () {
    expect(prerequisiteFactor(const []), 1);
    // A forgotten direct dependent doubles the prerequisite's priority.
    expect(prerequisiteFactor([(depth: 1, weakness: 1.0)]), 2);
    // Two steps away counts half as much.
    expect(prerequisiteFactor([(depth: 2, weakness: 1.0)]), 1.5);
    expect(
      prerequisiteFactor([
        (depth: 1, weakness: 0.1),
        (depth: 2, weakness: 0.9),
        (depth: 1, weakness: 0.3),
      ]),
      closeTo(1 + 2 * max(0.5 * 0.3, 0.25 * 0.9), 1e-12),
    );
    // Well-remembered dependents barely move it: a boost, never a gate.
    expect(prerequisiteFactor([(depth: 1, weakness: 0.0)]), 1);
  });
}
