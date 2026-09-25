import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_baseline.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';

import '../../support/curriculum_fixture.dart';
import 'coverage_fixture.dart';

/// The fixture's blocking gaps, accepted until Q1.
const knownGaps = [
  KnownGap(
    item: 'ki_cool_frost',
    kind: GapKind.untestable,
    reason: 'Too few hazards for an MCQ, and no flashcard template.',
    closedBy: 'C5',
  ),
  KnownGap(
    item: 'ki_meursault_grape',
    kind: GapKind.flashcardOnly,
    reason: 'mcq_disabled.',
    closedBy: 'Q1',
  ),
  KnownGap(
    item: 'ki_pommard_grape',
    kind: GapKind.flashcardOnly,
    reason: 'mcq_disabled.',
    closedBy: 'Q1',
  ),
];

/// The baseline of the fixture as it is, as JSON.
Future<Map<String, dynamic>> baselineJson() async => jsonDecode(
  CoverageBaseline.of(
    await coverageOfTracks(coverageDataset()),
    release: '1.0.0',
    knownGaps: knownGaps,
  ).toJson(),
) as Map<String, dynamic>;

Future<RatchetResult> ratchet(
  Map<String, dynamic> baseline, [
  Map<String, dynamic>? dataset,
]) async =>
    CoverageBaseline.parse(jsonEncode(baseline))
        .check(await coverageOfTracks(dataset ?? coverageDataset()));

Map<String, dynamic> burgundy(Map<String, dynamic> baseline) =>
    (((baseline['tracks'] as Map)['WSET_L2'] as Map)['domains']
            as Map)['geography']['areas']['n_geo_burgundy']
        as Map<String, dynamic>;

void main() {
  test('the coverage as it is passes its own baseline', () async {
    final result = await ratchet(await baselineJson());
    expect(result.failures, isEmpty);
    expect(result.notices, isEmpty);
  });

  test('is written with each group on one line, and reads back', () async {
    final tracks = await coverageOfTracks(coverageDataset());
    final baseline = CoverageBaseline.of(
      tracks,
      release: '1.0.0',
      knownGaps: knownGaps,
    );
    final text = baseline.toJson();
    expect(
      text,
      contains(
        '            "n_geo_burgundy": {"items": 4, "core": 3, "testable": 4, '
        '"flashcard_only": 2, "useful_practice": 1, "recall": 3, '
        '"recognition": 2, "spatial": 0, "structured": 0, "reasoning": 0, '
        '"core_flashcard_only": 1, "core_useful_practice": 1, '
        '"core_reasoning": 0}',
      ),
    );
    final read = CoverageBaseline.parse(text);
    expect(read.release, '1.0.0');
    expect(read.on, coverageDate);
    expect(read.tracks.keys, ['CMS_CERTIFIED', 'WSET_L2']);
    expect(read.knownGaps.map((g) => '$g'), [
      'ki_cool_frost untestable',
      'ki_meursault_grape flashcard_only',
      'ki_pommard_grape flashcard_only',
    ]);
    expect(read.toJson(), text);
  });

  group('the ratchet', () {
    test('fails when a metric falls', () async {
      final baseline = await baselineJson();
      burgundy(baseline)['useful_practice'] = 2;
      final result = await ratchet(baseline);
      expect(result.failures, [
        'WSET_L2 > Geography > Burgundy: useful_practice fell from 2 to 1',
      ]);
    });

    test('fails when an area loses its items', () async {
      final baseline = await baselineJson();
      final data = coverageDataset();
      // Moved to the other track: every item keeps a mapping.
      mappingOf(data, 'WSET_L2', 'ki_morgon_grape')['certification_id'] =
          'CMS_CERTIFIED';
      final result = await ratchet(baseline, data);
      expect(
        result.failures,
        containsAll([
          'WSET_L2: items fell from 7 to 6',
          'WSET_L2 > Geography > n_geo_beaujolais: items fell from 1 to 0',
        ]),
      );
    });

    test('passes when a metric rises, and says so', () async {
      final baseline = await baselineJson();
      burgundy(baseline)['recognition'] = 1;
      final result = await ratchet(baseline);
      expect(result.failures, isEmpty);
      expect(result.notices, [
        'WSET_L2: coverage rose; raise the baseline with --update-baseline',
      ]);
    });

    test('ignores a metric where less is better', () async {
      final baseline = await baselineJson();
      burgundy(baseline)['flashcard_only'] = 0;
      expect((await ratchet(baseline)).passes, isTrue);
    });

    test('fails on a new flashcard-only item', () async {
      final data = coverageDataset();
      rowOf(data, 'knowledge_items', 'id', 'ki_chablis_grape')['mcq_disabled'] =
          true;
      final result = await ratchet(await baselineJson(), data);
      expect(
        result.failures,
        contains(
          'WSET_L2: new gap: ki_chablis_grape: flashcard-only: mcq: '
          'mcq_disabled. Close it, or list it in known_gaps with a reason '
          'and the task that closes it',
        ),
      );
    });

    test('says when a known gap is closed', () async {
      final data = coverageDataset();
      rowOf(
        data,
        'knowledge_items',
        'id',
        'ki_meursault_grape',
      ).remove('mcq_disabled');
      final result = await ratchet(await baselineJson(), data);
      expect(result.passes, isTrue);
      expect(
        result.notices,
        contains(
          'closed: ki_meursault_grape flashcard_only (Q1); remove it from '
          'known_gaps, as --update-baseline does',
        ),
      );
    });

    test('fails for a track without a baseline', () async {
      final baseline = await baselineJson();
      (baseline['tracks'] as Map).remove('CMS_CERTIFIED');
      expect((await ratchet(baseline)).failures, [
        'CMS_CERTIFIED has no baseline: record it with --update-baseline',
      ]);
    });

    test('checks one track alone', () async {
      final baseline = CoverageBaseline.parse(jsonEncode(await baselineJson()));
      final track = await coverageOf(coverageDataset());
      final result = baseline.check([track], allTracks: false);
      expect(result.failures, isEmpty);
      expect(result.notices, isEmpty);
    });
  });

  group('raising the baseline', () {
    test('keeps the open known gaps and drops the closed ones', () async {
      final data = coverageDataset();
      rowOf(
        data,
        'knowledge_items',
        'id',
        'ki_meursault_grape',
      ).remove('mcq_disabled');
      final raised = CoverageBaseline.parse(jsonEncode(await baselineJson()))
          .raisedTo(await coverageOfTracks(data), release: '1.0.1');
      expect(raised.release, '1.0.1');
      expect(raised.knownGaps.map((g) => g.item), [
        'ki_cool_frost',
        'ki_pommard_grape',
      ]);
      expect(
        raised.tracks['WSET_L2']!.counts[CoverageMetric.usefulPractice],
        4,
      );
    });

    test('refuses a gap that is not known', () async {
      final baseline = CoverageBaseline.parse(jsonEncode(await baselineJson()));
      final data = coverageDataset();
      rowOf(data, 'knowledge_items', 'id', 'ki_chablis_grape')['mcq_disabled'] =
          true;
      final tracks = await coverageOfTracks(data);
      expect(
        () => baseline.raisedTo(tracks, release: '1.0.1'),
        throwsA(
          isA<CoverageBaselineException>().having(
            (e) => e.message,
            'message',
            contains('ki_chablis_grape: flashcard-only: mcq: mcq_disabled'),
          ),
        ),
      );
    });
  });

  group('rejects a baseline with', () {
    Matcher fails(String message) => throwsA(
      isA<CoverageBaselineException>().having(
        (e) => e.message,
        'message',
        contains(message),
      ),
    );

    Map<String, dynamic> gap([Map<String, dynamic> changes = const {}]) => {
      'item': 'ki_x',
      'gap': 'flashcard_only',
      'reason': 'A reason.',
      'closed_by': 'Q1',
      ...changes,
    };

    CoverageBaseline parse(Object document) =>
        CoverageBaseline.parse(jsonEncode(document), path: 'b.json');

    test('an unknown metric or a bad count', () {
      expect(
        () => parse({
          'tracks': {
            'WSET_L2': {
              'total': {'itemz': 1},
            },
          },
        }),
        fails('b.json: WSET_L2.total: unknown metric "itemz"'),
      );
      expect(
        () => parse({
          'tracks': {
            'WSET_L2': {
              'total': {'items': -1},
            },
          },
        }),
        fails('b.json: WSET_L2.total.items must be a count'),
      );
    });

    test('a known gap without its reason or task, or of a kind that does '
        'not block', () {
      expect(
        () => parse({
          'known_gaps': [
            gap({'reason': ''}),
          ],
        }),
        fails('known_gaps[0] needs a "reason"'),
      );
      expect(
        () => parse({
          'known_gaps': [
            {...gap()}..remove('closed_by'),
          ],
        }),
        fails('known_gaps[0] needs a "closed_by"'),
      );
      expect(
        () => parse({
          'known_gaps': [
            gap({'gap': 'no_useful_practice'}),
          ],
        }),
        fails('known_gaps[0]: gap must be one of untestable, flashcard_only'),
      );
      expect(
        () => parse({
          'known_gaps': [gap(), gap()],
        }),
        fails('known_gaps[1]: ki_x flashcard_only is listed twice'),
      );
      expect(
        () => parse({
          'known_gaps': [
            gap({'track': 'WSET_L3'}),
          ],
        }),
        fails('known_gaps[0]: unknown key "track"'),
      );
    });

    test('an unknown key, or text that is not JSON', () {
      expect(
        () => parse({'metrics': <String, Object?>{}}),
        fails('unknown key "metrics"'),
      );
      expect(
        () => CoverageBaseline.parse('{', path: 'b.json'),
        fails('b.json: not valid JSON'),
      );
    });
  });
}
