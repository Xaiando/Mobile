import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';

import 'coverage_fixture.dart';

Matcher rejects(String problem) => throwsA(
  isA<CoveragePolicyException>().having(
    (e) => e.problems,
    'problems',
    contains(problem),
  ),
);

/// A valid policy with [thresholds] in place of its own.
String withThresholds(String thresholds) =>
    '${coveragePolicyText.substring(0, coveragePolicyText.indexOf('thresholds:'))}'
    'thresholds:\n$thresholds';

void main() {
  test('parses capabilities, areas and thresholds', () {
    final policy = fixturePolicy(coveragePolicyText);
    expect(policy.regionalCountries, {'n_geo_france'});
    expect(policy.capabilities.keys, [
      'LOCATED_IN',
      'HAS_BERRY_COLOUR',
      'PERMITS_PRINCIPAL_GRAPE',
      'SUSCEPTIBLE_TO',
    ]);
    expect(policy.capabilities['PERMITS_PRINCIPAL_GRAPE']!.supports, {
      'flashcard',
      'mcq',
    });
    final berry = policy.capabilities['HAS_BERRY_COLOUR']!;
    expect(berry.supports, isEmpty);
    expect(berry.excludes, {
      'flashcard': 'Structural in this fixture.',
      'mcq': 'Structural in this fixture.',
    });

    final all = policy.thresholdsFor('WSET_L2');
    expect(all.keys, [
      CoverageMetric.coreFlashcardOnly,
      CoverageMetric.coreUsefulPractice,
    ]);
    final flashcardOnly = all[CoverageMetric.coreFlashcardOnly]!;
    expect(flashcardOnly.isMinimum, isFalse);
    expect(flashcardOnly.value, 0);
    expect(flashcardOnly.isPercent, isFalse);
    final useful = all[CoverageMetric.coreUsefulPractice]!;
    expect('$useful', 'at least 90%');
    expect(useful.admits(9, 10), isTrue);
    expect(useful.admits(8, 10), isFalse);
    expect(useful.admits(0, 0), isNull);
    expect(
      policy.thresholdsFor('WSET_L2', 'viticulture').keys,
      contains(CoverageMetric.coreReasoning),
    );
  });

  test('a domain, then a track, replace the thresholds before them', () {
    final policy = fixturePolicy(
      withThresholds('''
  all:
    core_useful_practice: {min: 90%}
    testable: {min: 1}
  domains:
    geography:
      core_useful_practice: {min: 95%}
  tracks:
    WSET_L2:
      core_useful_practice: {min: 99.5%}
'''),
    );
    num value(String track, [String? domain]) => policy
        .thresholdsFor(track, domain)[CoverageMetric.coreUsefulPractice]!
        .value;
    expect(value('CMS_CERTIFIED'), 90);
    expect(value('CMS_CERTIFIED', 'geography'), 95);
    expect(value('WSET_L2', 'geography'), 99.5);
    expect(
      policy.thresholdsFor('WSET_L2', 'geography')[CoverageMetric.testable],
      isNotNull,
    );
  });

  group('rejects', () {
    test('a relation type that does not say how each format serves it', () {
      expect(
        () => fixturePolicy(
          coveragePolicyText.replaceFirst(
            'SUSCEPTIBLE_TO:\n    supports: [flashcard, mcq]',
            'SUSCEPTIBLE_TO:\n    supports: [flashcard]',
          ),
        ),
        rejects(
          'coverage_policy.yaml:12: SUSCEPTIBLE_TO does not say whether mcq '
          'should test it: list it under supports, or under excludes with a '
          'reason',
        ),
      );
    });

    test('an unknown format, one named twice, or one both ways', () {
      expect(
        () => fixturePolicy(
          coveragePolicyText.replaceFirst(
            'supports: [flashcard, mcq]',
            'supports: [flashcard, mcq, typed]',
          ),
        ),
        rejects(
          'coverage_policy.yaml:4: LOCATED_IN: "typed" is not a built format '
          '(flashcard, mcq)',
        ),
      );
      expect(
        () => fixturePolicy(
          coveragePolicyText.replaceFirst(
            'supports: [flashcard, mcq]',
            'supports: [flashcard, mcq, mcq]',
          ),
        ),
        rejects('coverage_policy.yaml:4: LOCATED_IN supports mcq twice'),
      );
      expect(
        () => fixturePolicy(
          coveragePolicyText.replaceFirst(
            'supports: [flashcard, mcq]',
            'supports: [flashcard, mcq]\n    excludes: {mcq: Too hard.}',
          ),
        ),
        rejects(
          'coverage_policy.yaml:5: LOCATED_IN both supports and '
          'excludes mcq',
        ),
      );
    });

    test('an exclusion without a reason', () {
      expect(
        () => fixturePolicy(
          coveragePolicyText.replaceFirst(
            'mcq: Structural in this fixture.',
            'mcq: ""',
          ),
        ),
        rejects(
          'coverage_policy.yaml:8: HAS_BERRY_COLOUR excludes mcq '
          'without a reason',
        ),
      );
    });

    test('malformed thresholds', () {
      for (final (threshold, problem) in [
        (
          '  all:\n    core_usefulness: {min: 90%}\n',
          'coverage_policy.yaml:15: thresholds.all: unknown metric '
              '"core_usefulness"',
        ),
        (
          '  all:\n    testable: {min: 1, max: 2}\n',
          'coverage_policy.yaml:15: thresholds.all.testable must be '
              '{min: <bound>} or {max: <bound>}',
        ),
        (
          '  all:\n    testable: 90%\n',
          'coverage_policy.yaml:15: thresholds.all.testable must be '
              '{min: <bound>} or {max: <bound>}',
        ),
        (
          '  all:\n    testable: {at_least: 1}\n',
          'coverage_policy.yaml:15: thresholds.all.testable must be '
              '{min: <bound>} or {max: <bound>}',
        ),
        (
          '  all:\n    testable: {min: 150%}\n',
          'coverage_policy.yaml:15: thresholds.all.testable: "150%" is not a '
              'count or a percentage from 0% to 100%',
        ),
        (
          '  all:\n    testable: {min: -1}\n',
          'coverage_policy.yaml:15: thresholds.all.testable: "-1" is not a '
              'count or a percentage from 0% to 100%',
        ),
        (
          '  all:\n    testable: {min: 0.5}\n',
          'coverage_policy.yaml:15: thresholds.all.testable: "0.5" is not a '
              'count or a percentage from 0% to 100%',
        ),
        (
          '  domains:\n    geography:\n      testable: {min: ninety}\n',
          'coverage_policy.yaml:16: thresholds.domains.geography.testable: '
              '"ninety" is not a count or a percentage from 0% to 100%',
        ),
        (
          '  everywhere:\n    testable: {min: 1}\n',
          'coverage_policy.yaml:14: thresholds: unknown key "everywhere" '
              '(all, domains or tracks)',
        ),
      ]) {
        expect(
          () => fixturePolicy(withThresholds(threshold)),
          rejects(problem),
          reason: threshold,
        );
      }
    });

    test('an unknown key, or text that is not YAML', () {
      expect(
        () => fixturePolicy('$coveragePolicyText\nformats: []\n'),
        rejects('coverage_policy.yaml:21: unknown key "formats"'),
      );
      expect(
        () => fixturePolicy('capabilities: [', path: 'p.yaml'),
        throwsA(
          isA<CoveragePolicyException>().having(
            (e) => e.message,
            'message',
            startsWith('p.yaml:1: not valid YAML'),
          ),
        ),
      );
    });
  });

  test('says where it does not fit a curriculum', () {
    final policy = fixturePolicy(coveragePolicyText);
    expect(
      policy.problemsWith(
        relationTypes: {
          'LOCATED_IN',
          'HAS_BERRY_COLOUR',
          'PERMITS_PRINCIPAL_GRAPE',
          'SUSCEPTIBLE_TO',
        },
        domains: {'geography', 'viticulture'},
        tracks: {'WSET_L2'},
        nodes: {'n_geo_france'},
      ),
      isEmpty,
    );
    expect(
      policy.problemsWith(
        relationTypes: {
          'LOCATED_IN',
          'PERMITS_PRINCIPAL_GRAPE',
          'SUSCEPTIBLE_TO',
          'MIN_AGEING',
        },
        domains: {'geography'},
        tracks: const {},
        nodes: const {},
      ),
      [
        'MIN_AGEING is not in the coverage policy: say which formats should '
            'test it',
        'the coverage policy lists HAS_BERRY_COLOUR, which is not a relation '
            'type',
        'the coverage policy sets thresholds for viticulture, which is not a '
            'domain',
        'regional_countries lists n_geo_france, which is not a node',
      ],
    );
  });
}
