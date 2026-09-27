import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/learner_state.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  late StudyPlanner planner;
  late TrackCoverage coverage;
  late TrackScopeManifest scope;
  late Map<String, dynamic> data;
  late Clock clock;

  setUpAll(() async {
    final dataset = bundledDataset();
    data = flattenDataset(curriculumAssetPath);
    final on = isoDate(dataset.publishedAt.toUtc());
    clock = Clock.fixed(DateTime.parse('${on}T12:00:00Z'));
    db = openTestDatabase();
    addTearDown(db.close);
    final generation = await CurriculumIngester(
      db,
      clock: clock,
    ).ingest(dataset);
    planner = StudyPlanner(db, clock: clock);
    final checker = CoverageChecker(
      db,
      CoveragePolicy.parse(
        File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
      ),
    );
    coverage = await checker.check(
      'WSET_L4',
      on: on,
      skipped: generation.skipped,
    );
    scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
  });

  test(
    'the dynamic picker offers Diploma and the profile can select it',
    () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appStartupProvider.overrideWith(
            (ref) async => StorageDurability.memoryOnly,
          ),
        ],
      );
      addTearDown(container.dispose);
      final choices = await container.read(selectableTracksProvider.future);
      expect(
        choices.map((track) => track.id),
        containsAll(['CMS_CERTIFIED', 'WSET_L3', 'WSET_L4']),
      );
      final diploma = choices.singleWhere((track) => track.id == 'WSET_L4');
      expect(diploma.includesCertificationId, 'WSET_L3');
      final selected = await LearnerProfiles(
        db,
        clock: clock,
      ).selectTrack('WSET_L4');
      expect(selected.activeCertificationId, 'WSET_L4');
    },
  );

  test(
    'Diploma inherits location depth and served maps without copied mappings',
    () async {
      final lower = await planner.effectiveMappings('WSET_L3');
      final higher = await planner.effectiveMappings('WSET_L4');
      expect(higher.keys, containsAll(lower.keys));
      final locationIds = {
        for (final row in rowsOf(data, 'knowledge_items'))
          if (row['relation_type'] == 'LOCATED_IN') row['id'],
      };
      for (final entry in lower.entries) {
        if (!locationIds.contains(entry.key)) continue;
        final inherited = higher[entry.key]!;
        expect(inherited.certificationId, entry.value.certificationId);
        expect(inherited.minimumDepth, entry.value.minimumDepth);
        expect(inherited.importance, entry.value.importance);
        expect(inherited.chainDepth, entry.value.chainDepth + 1);
      }
      final chablis = coverage.items.singleWhere(
        (item) => item.id == 'ki_chablis_location',
      );
      expect(chablis.mapping.certificationId, 'WSET_L3');
      expect(
        chablis.servedFormats,
        containsAll(['map_locate', 'map_identify', 'map_pair']),
      );
      expect(
        rowsOf(data, 'certification_knowledge_mappings').where(
          (row) =>
              row['certification_id'] == 'WSET_L4' &&
              locationIds.contains(row['knowledge_item_id']),
        ),
        isEmpty,
        reason: 'locations retain inherited depth; analytical principles may have explicit Diploma mappings',
      );
    },
  );

  test(
    'Diploma pins the official issue and accounts for all six unit workstreams',
    () {
      final diploma = scope.tracks['WSET_L4']!;
      expect(diploma.source.version, '2025, Issue 1.4');
      expect(
        diploma.source.url,
        'https://www.wsetglobal.com/media/17609/wset_l4wines_specification_en_august-2025.pdf',
      );
      expect(diploma.source.checkedOn, '2026-09-26');
      const units = {
        'production': 'DIP-1',
        'business': 'DIP-2',
        'world': 'DIP-3',
        'sparkling': 'DIP-4',
        'fortified': 'DIP-5',
        'research': 'DIP-6',
      };
      for (final unit in units.entries) {
        final objectives = diploma.objectives.where(
          (objective) => objective.id.startsWith('wset_l4.${unit.key}.'),
        );
        expect(objectives, isNotEmpty);
        expect(
          objectives.every((objective) => objective.tasks.contains(unit.value)),
          isTrue,
        );
      }
      Set<String> ids(String section) => {
        for (final row in rowsOf(data, section)) row['id'] as String,
      };
      expect(
        scope.problemsWith(
          tracks: ids('certifications'),
          selectableTracks: {
            for (final row in rowsOf(data, 'certifications'))
              if (row['is_selectable'] == true) row['id'] as String,
          },
          domains: ids('curriculum_domains'),
          nodes: ids('knowledge_nodes'),
          relationTypes: ids('relation_types'),
          nodeTypes: ids('node_types'),
          citedUrls: {
            for (final row in rowsOf(data, 'source_citations'))
              if (row['url'] != null) row['id'] as String: row['url'] as String,
          },
        ),
        isEmpty,
        reason: 'scope selectors must be real and the specification cannot be a fact source',
      );
    },
  );

  test(
    'accounted scope and usable maps do not claim complete Diploma content',
    () {
      final measured = {
        for (final objective in objectiveCoverage(
          scope.tracks['WSET_L4']!,
          coverage,
        ))
          objective.objective.id: objective,
      };
      expect(
        measured.values.where(
          (objective) => objective.status == ObjectiveStatus.missing,
        ),
        isEmpty,
      );
      for (final id in [
        'wset_l4.sparkling.tasting',
        'wset_l4.fortified.tasting',
        'wset_l4.research.evidence',
        'wset_l4.research.argument',
      ]) {
        expect(measured[id]!.status, ObjectiveStatus.planned, reason: id);
        expect(
          measured[id]!.items,
          0,
          reason: 'a backlog entry is not authored content',
        );
      }
      for (final id in [
        'wset_l4.production.vineyard',
        'wset_l4.production.quality_control',
        'wset_l4.business.routes',
        'wset_l4.business.marketing',
        'wset_l4.sparkling.production',
        'wset_l4.sparkling.commerce',
        'wset_l4.fortified.production_and_market',
        'wset_l4.world.tasting',
        'wset_l4.world.comparison',
      ]) {
        expect(measured[id]!.status, ObjectiveStatus.represented, reason: id);
        expect(measured[id]!.items, greaterThan(0));
        expect(
          measured[id]!.objective.tasks,
          isNotEmpty,
          reason: 'partial authored support does not finish the workstream',
        );
      }
      final burgundy = measured['wset_l4.world.burgundy']!;
      expect(measured['wset_l4.world.china']!.items, 52);
      expect(measured['wset_l4.world.china']!.core, 44);
      expect(measured['wset_l4.world.comparison']!.items, 704);
      for (final region in [
        'italy_north',
        'italy_centre',
        'italy_south',
        'spain',
        'portugal',
        'alsace',
        'beaujolais',
        'jura',
        'southern_france',
        'southwest_france',
        'loire',
        'rhone',
        'germany',
        'austria',
        'hungary',
        'greece',
        'usa_west',
        'usa_new_york',
        'canada',
        'chile',
        'argentina',
        'australia',
        'new_zealand',
        'south_africa',
        'china',
      ]) {
        final objective = measured['wset_l4.world.$region']!;
        expect(objective.status, ObjectiveStatus.represented, reason: region);
        expect(objective.items, greaterThan(0), reason: region);
        expect(objective.objective.tasks, contains('DIP-3'));
        expect(
          objective.objective.covers!.within.any(
            (node) => node.startsWith('n_reg_'),
          ),
          isTrue,
          reason: 'authored analysis joins existing map context',
        );
      }
      for (final trackId in ['WSET_L3', 'CMS_CERTIFIED']) {
        final track = scope.tracks[trackId]!;
        final optionalJura = track.objectives.singleWhere(
          (o) => o.id.endsWith('.regional.jura_support'),
        );
        expect(optionalJura.isRequired, isFalse);
        expect(optionalJura.tasks, contains('DIP-3'));
        expect(
          optionalJura.covers!.within.every(
            (node) => node.startsWith('n_reg_fe_'),
          ),
          isTrue,
          reason: 'optional analytical support has explicit subjects',
        );
        final juraIds = {
          for (final row in rowsOf(data, 'knowledge_items'))
            if (optionalJura.covers!.within.contains(row['subject_id']))
              row['id'],
        };
        final supportingMappings =
            rowsOf(data, 'certification_knowledge_mappings').where(
              (row) =>
                  row['certification_id'] == trackId &&
                  juraIds.contains(row['knowledge_item_id']),
            );
        expect(supportingMappings, isNotEmpty);
        expect(
          supportingMappings.every((row) => row['importance'] == 'secondary'),
          isTrue,
          reason: 'editorial Jura enrichment is not lower-track core coverage',
        );
        final atlas = track.objectives.singleWhere(
          (o) => o.id.endsWith('.atlas.additional_places'),
        );
        expect(atlas.isRequired, isFalse);
        expect(atlas.covers!.relationTypes, {'LOCATED_IN'});
      }
      expect(burgundy.status, ObjectiveStatus.represented);
      expect(burgundy.items, greaterThan(0));
      expect(burgundy.objective.tasks, contains('DIP-3'));
      final newYork = measured['wset_l4.world.usa_new_york']!;
      expect(newYork.status, ObjectiveStatus.represented);
      expect(newYork.items, greaterThan(0));
      expect(newYork.objective.tasks, contains('DIP-3'));
      expect(
        measured.values.where(
          (objective) => objective.status == ObjectiveStatus.planned,
        ),
        isNotEmpty,
        reason: 'zero missing objectives means accounted scope, not six completed units',
      );
    },
  );
}
