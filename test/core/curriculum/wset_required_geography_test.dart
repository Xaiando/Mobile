import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final evidence = jsonDecode(
    File('docs/research/wset-required-geography-evidence.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final requirements = (evidence['requirements'] as List)
      .cast<Map<String, dynamic>>();

  test('required geography retains cited, reviewable factual assertions', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final added = items.values.where(
      (item) => item.id.startsWith('ki_wset_geo_'),
    );
    expect(added.length, greaterThanOrEqualTo(60));
    for (final item in added) {
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        dataset.knowledgeItemCitations.where(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isNotEmpty,
        reason: item.id,
      );
    }
    for (final requirement in requirements) {
      expect(requirement['canonical_node_id'], isNotNull);
      expect(requirement['location_item_ids'], isNotEmpty);
      for (final id in (requirement['location_item_ids'] as List)) {
        expect(items[id]!.relationType, 'LOCATED_IN', reason: id as String);
        expect(
          dataset.certificationKnowledgeMappings.any(
            (mapping) =>
                mapping.knowledgeItemId == id &&
                mapping.certificationId == requirement['level'] &&
                mapping.importance == 'core',
          ),
          isTrue,
          reason: '${requirement['required_name']} at ${requirement['level']}',
        );
      }
    }
  });

  test('administrative references and wine identities remain distinct', () {
    expect(nodes['n_geo_sonoma_county']!.nodeType, 'region');
    expect(nodes['n_geo_sonoma_valley']!.nodeType, 'appellation');
    expect(nodes['n_geo_navarra_region']!.nodeType, 'region');
    expect(nodes['n_geo_navarra_do']!.nodeType, 'appellation');
    expect(nodes['n_geo_castilla_y_leon']!.nodeType, 'region');
    expect(nodes['n_geo_castilla_y_leon_igp']!.nodeType, 'appellation');
    expect(nodes['n_geo_burgundy']!.nodeType, 'region');
    expect(nodes['n_geo_bourgogne_aoc']!.nodeType, 'appellation');
    final grandCru = (evidence['protected_categories'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (row) => row['classification'] == 'named_site_AOC_category',
        );
    expect(nodes[grandCru['node_id']]!.nodeType, 'wine_type');
    expect(grandCru['canonical_map_origin_node_id'], 'n_geo_alsace_region');
    expect(
      items['ki_wset_geo_porto_origin']!.objectId,
      'n_geo_douro',
      reason: 'Port is sourced to Douro, not to a Porto-city marker',
    );
  });

  test(
    'licensed markers preserve exact source coordinates and qualifications',
    () {
      final source = jsonDecode(
        File('tool/geography/wset_required_gazetteer_points.geojson')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final features = (source['features'] as List)
          .cast<Map<String, dynamic>>();
      final topology = jsonDecode(
        File('assets/geography/wset_required_gazetteer.topo.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final geometries =
          ((topology['objects'] as Map).values.single as Map)['geometries']
              as List;
      final byId = {for (final raw in geometries) (raw as Map)['id']: raw};
      for (final feature in features) {
        final properties = feature['properties'] as Map;
        expect(properties['license'], 'CC-BY-4.0');
        expect(
          properties['source_file_sha256'],
          matches(RegExp(r'^[a-f0-9]{64}$')),
        );
        expect(
          properties['label_note'],
          contains('not an official appellation centroid'),
        );
        expect(
          (byId[properties['node']] as Map)['coordinates'],
          (feature['geometry'] as Map)['coordinates'],
          reason: properties['node'] as String,
        );
      }
      final forst = features.singleWhere(
        (feature) =>
            (feature['properties'] as Map)['node'] == 'n_geo_forst_pfalz',
      );
      final point = (forst['geometry'] as Map)['coordinates'] as List;
      expect(point[0], closeTo(8.1897, 0.00001));
      expect(point[1], closeTo(49.42567, 0.00001));
    },
  );

  group('actual generated map practice', () {
    late AppDatabase db;
    late TestClock time;
    late GeometryRepository maps;
    late ExercisePresenter presenter;
    final layers = <String, GeoLayer>{};

    setUpAll(() async {
      time = TestClock(DateTime.utc(2026, 10, 1, 9));
      db = openTestDatabase();
      await CurriculumIngester(
        db,
        clock: time.clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      maps = GeometryRepository(db);
      presenter = ExercisePresenter(db, clock: time.clock);
    });
    tearDownAll(() => db.close());

    test(
      'every required place has a framed, generated click-location question',
      () async {
        final questions = await db.select(db.questions).get();
        final locate = questions
            .where(
              (q) => q.questionTemplateId == 'qt_located_in_fwd_map_locate',
            )
            .map((q) => q.knowledgeItemId)
            .toSet();
        for (final id
            in requirements
                .map((row) => row['canonical_node_id'] as String)
                .toSet()) {
          final frame = await maps.frameOf(id, on: '2026-10-01');
          expect(frame, isNotNull, reason: id);
          expect(
            frame!.candidates.map((candidate) => candidate.id),
            contains(id),
          );
        }
        for (final id
            in requirements
                .expand(
                  (row) => (row['location_item_ids'] as List).cast<String>(),
                )
                .toSet()) {
          expect(locate, contains(id), reason: id);
        }
      },
    );

    test('real taps grade correctly for country, AVA and overlapping protected areas', () async {
      final assets = {
        for (final layer in await db.select(db.mapLayers).get())
          layer.id: layer.assetPath,
      };
      for (final itemId in [
        'ki_wset_geo_chile_world_location',
        'ki_atlas_st_helena_location',
        'ki_wset_geo_bourgogne_aoc_location',
        'ki_wset_geo_rose_d_anjou_location',
        'ki_wset_geo_cabernet_d_anjou_location',
        'ki_fr_atlas_vougeot_location',
        'ki_fr_atlas_cote_de_nuits_villages_location',
        'ki_fr_atlas_cote_de_beaune_villages_location',
        'ki_fr_atlas_aloxe_corton_location',
        'ki_fr_atlas_saumur_champigny_location',
        'ki_eac_friuli_colli_orientali_location',
      ]) {
        final exercise = await presenter.present(
          itemId,
          'qt_located_in_fwd_map_locate',
          seed: 19,
        ) as MapExercise;
        final geometry = exercise.frame.candidates
            .firstWhere((candidate) => candidate.id == exercise.nodeId)
            .geometry;
        final point = LonLat(geometry.labelLon, geometry.labelLat);
        final shapes = [
          for (final candidate in exercise.frame.candidates)
            layers
                .putIfAbsent(
                  candidate.geometry.mapLayerId,
                  () => GeoLayer.fromTopology(
                    Topology.parse(
                      File(assets[candidate.geometry.mapLayerId]!)
                          .readAsStringSync(),
                    ),
                    id: candidate.geometry.mapLayerId,
                  ),
                )
                .shapeFor(candidate.geometry.featureKey)!,
        ];
        final box = exercise.frame.box;
        final tap = MapTap(
          position: point,
          hits: const MapHitTester().hitTest(
            shapes,
            WebMercator.project(point),
            400 / ((box.maxLon - box.minLon) / 360),
          ),
          zoom: 6,
          visibleBounds: GeoBounds(
            minLon: box.minLon,
            minLat: box.minLat,
            maxLon: box.maxLon,
            maxLat: box.maxLat,
          ),
        );
        final answer = MapLocateAnswer.fromTap(
          tap,
          preferredNodeIds: exercise.correctNodeIds,
        );
        expect(answer.nodeId, exercise.nodeId, reason: itemId);
      }
    });
  });
}
