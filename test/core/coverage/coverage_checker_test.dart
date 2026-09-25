import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_formats.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';

import '../../support/curriculum_fixture.dart';
import 'coverage_fixture.dart';

/// [counts] as `{metric key: count}`, leaving out zeros.
Map<String, int> nonZero(CoverageCounts counts) => {
  for (final MapEntry(key: metric, value: count) in counts.toMap().entries)
    if (count != 0) metric.key: count,
};

void main() {
  group('the metrics of a track', () {
    late TrackCoverage coverage;

    setUpAll(() async => coverage = await coverageOf(coverageDataset()));

    test('count the items in force that the track maps', () {
      expect(coverage.trackId, 'WSET_L2');
      expect(coverage.on, coverageDate);
      expect(
        coverage.items.map((i) => i.id),
        [
          'ki_chablis_grape',
          'ki_cool_frost',
          'ki_meursault_grape',
          'ki_morgon_grape',
          'ki_pommard_grape',
          'ki_volnay_grape',
          'ki_walporzheim_grape',
        ],
        reason:
            'ki_pommard_gamay has ended; ki_walporzheim_grape is mapped '
            'by the included level',
      );
      expect(nonZero(coverage.counts), {
        'items': 7,
        'core': 6,
        'testable': 6,
        'flashcard_only': 2,
        'useful_practice': 3,
        'recall': 5,
        'recognition': 4,
        'core_flashcard_only': 1,
        'core_useful_practice': 3,
      });
    });

    test('are split by domain, then by area', () {
      expect(coverage.domains.map((d) => d.id), ['geography', 'viticulture']);
      final geography = coverage.domains.first;
      expect(nonZero(geography.counts), {
        'items': 6,
        'core': 5,
        'testable': 6,
        'flashcard_only': 2,
        'useful_practice': 3,
        'recall': 5,
        'recognition': 4,
        'core_flashcard_only': 1,
        'core_useful_practice': 3,
      });
      expect(
        {
          for (final MapEntry(key: area, value: counts)
              in geography.areas.entries)
            '${area.id} ${area.name}': nonZero(counts),
        },
        {
          'n_geo_beaujolais Beaujolais': {
            'items': 1,
            'core': 1,
            'testable': 1,
            'useful_practice': 1,
            'recall': 1,
            'recognition': 1,
            'core_useful_practice': 1,
          },
          'n_geo_burgundy Burgundy': {
            'items': 4,
            'core': 3,
            'testable': 4,
            'flashcard_only': 2,
            'useful_practice': 1,
            'recall': 3,
            'recognition': 2,
            'core_flashcard_only': 1,
            'core_useful_practice': 1,
          },
          'n_geo_germany Germany': {
            'items': 1,
            'core': 1,
            'testable': 1,
            'useful_practice': 1,
            'recall': 1,
            'recognition': 1,
            'core_useful_practice': 1,
          },
        },
        reason: 'France is split by region; Germany is not',
      );
      final viticulture = coverage.domains.last;
      expect(nonZero(viticulture.counts), {'items': 1, 'core': 1});
      expect(viticulture.areas.keys.single.id, 'type:climate');
      expect(viticulture.areas.keys.single.name, 'climate');
    });

    test('follow the formats the track serves at each depth', () {
      ItemCoverage item(String id) =>
          coverage.items.firstWhere((i) => i.id == id);
      expect(item('ki_chablis_grape').servedFormats, {'mcq', 'flashcard'});
      expect(item('ki_chablis_grape').families, {
        FormatFamily.recall,
        FormatFamily.recognition,
      });
      expect(item('ki_chablis_grape').hasUsefulPractice, isTrue);
      // Depth 1 serves the MCQ only (CM-6).
      expect(item('ki_volnay_grape').servedFormats, {'mcq'});
      expect(item('ki_volnay_grape').hasUsefulPractice, isFalse);
      expect(item('ki_meursault_grape').isFlashcardOnly, isTrue);
      expect(item('ki_meursault_grape').missing, {'mcq': 'mcq_disabled'});
      expect(item('ki_cool_frost').isTestable, isFalse);
      expect(item('ki_cool_frost').missing, {
        'flashcard': 'no flashcard template for SUSCEPTIBLE_TO',
        'mcq': 'too few distractors',
      });
    });
  });

  test('the gaps of a track, blocking first', () async {
    final coverage = await coverageOf(coverageDataset());
    expect(
      [for (final gap in coverage.gaps) '$gap'],
      [
        'ki_cool_frost: no question: flashcard: no flashcard template for '
            'SUSCEPTIBLE_TO; mcq: too few distractors',
        'ki_meursault_grape: flashcard-only: mcq: mcq_disabled',
        'ki_pommard_grape: flashcard-only: mcq: mcq_disabled',
        'ki_volnay_grape: core item without useful practice: served mcq '
            '(recognition) at depth 1',
        'ki_cool_frost: expected format missing (flashcard): no flashcard '
            'template for SUSCEPTIBLE_TO',
        'ki_cool_frost: expected format missing (mcq): too few distractors',
        'ki_meursault_grape: expected format missing (mcq): mcq_disabled',
        'ki_pommard_grape: expected format missing (mcq): mcq_disabled',
      ],
    );
    expect(coverage.blockingGaps.map((g) => g.itemId), [
      'ki_cool_frost',
      'ki_meursault_grape',
      'ki_pommard_grape',
    ], reason: 'a flashcard-only item blocks whatever its importance');
  });

  test('another track counts only its own mappings', () async {
    final coverage = await coverageOf(
      coverageDataset(),
      track: 'CMS_CERTIFIED',
    );
    expect(nonZero(coverage.counts), {
      'items': 2,
      'core': 1,
      'testable': 2,
      'flashcard_only': 1,
      'recall': 1,
      'recognition': 1,
    });
    expect(coverage.gaps.map((g) => '${g.itemId} ${g.kind.key}'), [
      'ki_meursault_grape flashcard_only',
      'ki_chablis_grape no_useful_practice',
      'ki_meursault_grape missing_format',
    ]);
  });

  test('every selectable track, by organization and level', () async {
    final tracks = await coverageOfTracks(coverageDataset());
    expect(tracks.map((t) => t.trackId), ['CMS_CERTIFIED', 'WSET_L2']);
  });

  test('an item below its depth is still served its easiest question '
      '(A-10)', () async {
    final data = coverageDataset();
    mappingOf(data, 'WSET_L2', 'ki_meursault_grape')['minimum_depth'] = 1;
    final coverage = await coverageOf(data);
    final item = coverage.items.firstWhere((i) => i.id == 'ki_meursault_grape');
    expect(item.servedFormats, {'flashcard'});
    expect(item.isFlashcardOnly, isTrue);
  });

  group('areas', () {
    Future<Map<String, String>> areasOf(
      Map<String, dynamic> data, {
      String policy = coveragePolicyText,
    }) async {
      final coverage = await coverageOf(data, policy: policy);
      return {for (final item in coverage.items) item.id: item.area.id};
    }

    test('split a regional country by region', () async {
      final areas = await areasOf(
        coverageDataset(),
        policy: coveragePolicyText.replaceFirst(
          '[n_geo_france]',
          '[n_geo_france, n_geo_germany]',
        ),
      );
      expect(areas['ki_walporzheim_grape'], 'n_geo_ahr');
      expect(areas['ki_chablis_grape'], 'n_geo_burgundy');
    });

    test('put a place in no country among the unplaced', () async {
      final data = coverageDataset();
      rowsOf(
        data,
        'knowledge_relations',
      ).removeWhere((r) => r['subject_id'] == 'n_geo_ahr');
      rowsOf(data, 'knowledge_relations').removeWhere(
        (r) =>
            r['subject_id'] == 'n_geo_volnay' &&
            r['relation_type'] == 'LOCATED_IN',
      );
      final areas = await areasOf(data);
      expect(areas['ki_walporzheim_grape'], 'unplaced');
      expect(areas['ki_volnay_grape'], 'unplaced');
      expect(areas['ki_chablis_grape'], 'n_geo_burgundy');
    });
  });

  group('policy thresholds', () {
    test('are measured on the track and on each domain', () async {
      final coverage = await coverageOf(coverageDataset());
      expect(
        [
          for (final result in coverage.thresholds)
            '${result.domainId ?? 'all'} ${result.threshold.metric.key} '
                '${result.threshold}: ${result.value}/${result.base} '
                '${result.passes}',
        ],
        [
          'all core_flashcard_only at most 0: 1/6 false',
          'all core_useful_practice at least 90%: 3/6 false',
          'geography core_flashcard_only at most 0: 1/5 false',
          'geography core_useful_practice at least 90%: 3/5 false',
          'viticulture core_flashcard_only at most 0: 0/1 true',
          'viticulture core_useful_practice at least 90%: 0/1 false',
          'viticulture core_reasoning at least 50%: 0/1 false',
        ],
      );
    });

    test('of a share of no items do not apply', () async {
      final data = coverageDataset();
      mappingOf(data, 'CMS_CERTIFIED', 'ki_chablis_grape')['importance'] =
          'secondary';
      final coverage = await coverageOf(data, track: 'CMS_CERTIFIED');
      final useful = coverage.thresholds.firstWhere(
        (r) =>
            r.domainId == null &&
            r.threshold.metric == CoverageMetric.coreUsefulPractice,
      );
      expect(useful.base, 0, reason: 'the track has no core item');
      expect(useful.passes, isNull);
    });
  });

  group('the checker refuses a policy that does not fit', () {
    Future<void> expectProblem(String policy, String problem) => expectLater(
      coverageOf(coverageDataset(), policy: policy),
      throwsA(
        isA<CoveragePolicyException>().having(
          (e) => e.problems,
          'problems',
          contains(problem),
        ),
      ),
    );

    test(
      'a relation type missing from the policy',
      () => expectProblem(
        coveragePolicyText.replaceFirst(
          '  SUSCEPTIBLE_TO:\n    supports: [flashcard, mcq]\n',
          '',
        ),
        'SUSCEPTIBLE_TO is not in the coverage policy: say which formats '
        'should test it',
      ),
    );

    test(
      'an unknown relation type',
      () => expectProblem(
        coveragePolicyText.replaceFirst(
          'capabilities:\n',
          'capabilities:\n  MIN_AGEING:\n    supports: [flashcard, mcq]\n',
        ),
        'the coverage policy lists MIN_AGEING, which is not a relation type',
      ),
    );

    test('an unknown domain, track or country', () async {
      await expectProblem(
        coveragePolicyText.replaceFirst('viticulture:', 'tasting:'),
        'the coverage policy sets thresholds for tasting, which is not a '
        'domain',
      );
      await expectProblem(
        '$coveragePolicyText  tracks:\n    WSET_L9:\n'
            '      core_reasoning: {min: 1}\n',
        'the coverage policy sets thresholds for WSET_L9, which is not a '
            'track',
      );
      await expectProblem(
        coveragePolicyText.replaceFirst('[n_geo_france]', '[n_geo_spain]'),
        'regional_countries lists n_geo_spain, which is not a node',
      );
    });
  });
}
