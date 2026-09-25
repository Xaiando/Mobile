import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_baseline.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const policyPath = 'assets/curriculum/coverage_policy.yaml';
const baselinePath = 'assets/curriculum/coverage_baseline.json';
const scopePath = 'assets/curriculum/track_scope.yaml';

void main() {
  late List<TrackCoverage> tracks;

  // Measured as tool/coverage_report.dart measures it: on the release date,
  // with the questions generated for that date (COV-5).
  setUpAll(() async {
    final dataset = bundledDataset();
    final on = isoDate(dataset.publishedAt.toUtc());
    final date = DateTime.parse(on);
    final db = openTestDatabase();
    addTearDown(db.close);
    final generation = await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime(date.year, date.month, date.day, 12)),
    ).ingest(dataset);
    final checker = CoverageChecker(
      db,
      CoveragePolicy.parse(
        File(policyPath).readAsStringSync(),
        path: policyPath,
      ),
    );
    tracks = [
      for (final track in await checker.selectableTracks())
        await checker.check(track.id, on: on, skipped: generation.skipped),
    ];
  });

  test('the checker measures both selectable tracks (F1)', () {
    expect(tracks.map((t) => t.trackId), ['CMS_CERTIFIED', 'WSET_L3']);
    for (final track in tracks) {
      expect(track.counts[CoverageMetric.items], greaterThan(0));
      expect(
        track.counts[CoverageMetric.testable],
        track.counts[CoverageMetric.items],
        reason: 'every item has a flashcard (§S.3), so each is testable',
      );
      expect(track.domains, isNotEmpty);
    }
  });

  test('the scope manifest accounts for every objective of both tracks '
      '(SCOPE-1)', () {
    final scope = TrackScopeManifest.parse(
      File(scopePath).readAsStringSync(),
      path: scopePath,
    );
    for (final track in tracks) {
      final trackScope = scope.tracks[track.trackId];
      expect(trackScope, isNotNull, reason: '${track.trackId} has a scope');
      final objectives = objectiveCoverage(trackScope!, track);
      expect(
        objectives.where((o) => o.status == ObjectiveStatus.represented),
        isNotEmpty,
        reason: 'the release represents some of ${track.trackId}',
      );
      expect(
        [
          for (final o in objectives)
            if (o.objective.isRequired && o.status == ObjectiveStatus.missing)
              o.objective.id,
        ],
        isEmpty,
        reason: 'each required objective is covered, planned or excluded',
      );
    }
  });

  test('the bundled release keeps the committed coverage baseline', () {
    final baseline = CoverageBaseline.parse(
      File(baselinePath).readAsStringSync(),
      path: baselinePath,
    );
    final result = baseline.check(tracks);
    expect(
      result.failures,
      isEmpty,
      reason:
          'Coverage fell or a gap is new. See dart run '
          'tool/coverage_report.dart. Close the gap, or if the change is '
          'intended, list new gaps in known_gaps and run the tool with '
          '--update-baseline (audit COV-3).',
    );
  });
}
