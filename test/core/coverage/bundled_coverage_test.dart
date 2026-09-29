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

  test('the checker measures every selectable track (F1)', () {
    expect(tracks.map((t) => t.trackId), [
      'CMS_CERTIFIED',
      'WSET_L1',
      'WSET_L2',
      'WSET_L3',
      'WSET_L4',
    ]);
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

  test('pooled formats count as the planner serves them (QF-14)', () {
    final wset = tracks.firstWhere((t) => t.trackId == 'WSET_L3');
    ItemCoverage item(String id) => wset.items.firstWhere((i) => i.id == id);
    expect([
      for (final format in item('ki_chablis_soil').generated) format.mode,
    ], contains('short_answer'));
    expect(item('ki_chablis_soil').servedFormats, contains('short_answer'));
    final vouvray = item('ki_vouvray_grape');
    expect(
      vouvray.missing,
      containsPair('short_answer', 'in no short_answer pool'),
      reason: 'Vouvray has one key point',
    );
    expect(
      vouvray.missing,
      containsPair('map_grape', 'the format cannot ask it'),
      reason: 'Vouvray has no complete permitted-grape assertion',
    );
    expect(vouvray.servedFormats, isNot(contains('map_grape')));
  });

  test('the scope manifest accounts for every selectable track objective '
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

  test('CMS beverage objectives select their authored lessons', () {
    final scope = TrackScopeManifest.parse(
      File(scopePath).readAsStringSync(),
      path: scopePath,
    ).tracks['CMS_CERTIFIED']!;
    final cms = tracks.singleWhere((track) => track.trackId == 'CMS_CERTIFIED');
    final objectives = {
      for (final coverage in objectiveCoverage(scope, cms))
        coverage.objective.id: coverage,
    };
    for (final id in [
      'cms_certified.spirits',
      'cms_certified.liqueurs_and_aperitifs',
      'cms_certified.beer_and_cider',
      'cms_certified.sake',
    ]) {
      expect(objectives[id]!.status, ObjectiveStatus.represented, reason: id);
      expect(objectives[id]!.items, greaterThan(0), reason: id);
    }
  });

  test('Diploma D2 objectives include the applied business mechanisms', () {
    final scope = TrackScopeManifest.parse(
      File(scopePath).readAsStringSync(),
      path: scopePath,
    ).tracks['WSET_L4']!;
    final diploma = tracks.singleWhere((track) => track.trackId == 'WSET_L4');
    final objectives = {
      for (final objective in scope.objectives) objective.id: objective,
    };
    final itemById = {for (final item in diploma.items) item.id: item};
    expect(
      objectives['wset_l4.business.economics']!.covers!.matches(
        itemById['ki_d2_supply_demand_shift']!,
      ),
      isTrue,
    );
    expect(
      objectives['wset_l4.business.economics']!.covers!.matches(
        itemById['ki_d2_import_cost_stack']!,
      ),
      isTrue,
    );
    for (final id in [
      'ki_biz_models_custom_capacity',
      'ki_biz_routes_service_scope',
      'ki_biz_routes_case_dtc_capacity_action',
    ]) {
      expect(
        objectives['wset_l4.business.routes']!.covers!.matches(itemById[id]!),
        isTrue,
        reason: id,
      );
    }
    expect(
      objectives['wset_l4.business.marketing']!.covers!.matches(
        itemById['ki_d2_marketing_mix']!,
      ),
      isTrue,
    );
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
