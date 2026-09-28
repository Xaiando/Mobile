import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_pair/map_pair_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  const layerId = 'ml_cms_greece_markers';
  const locate = 'qt_located_in_fwd_map_locate';
  const identify = 'qt_located_in_fwd_map_identify';
  const pair = 'qt_located_in_fwd_map_pair';
  const grapeMap = 'qt_permitted_grape_fwd_map_grape';
  const targets = {
    'ki_halkidiki_location': 'n_geo_halkidiki',
    'ki_sithonia_location': 'n_geo_sithonia',
    'ki_slopes_of_meliton_location': 'n_geo_slopes_of_meliton',
    'ki_achaea_location': 'n_geo_achaea',
    'ki_patra_location': 'n_geo_patra',
  };
  const pinnedCoordinates = {
    'n_geo_halkidiki': [23.5, 40.41667],
    'n_geo_sithonia': [23.86828, 40.09788],
    'n_geo_slopes_of_meliton': [23.83333, 40.06667],
    'n_geo_achaea': [22.0, 38.13333],
    'n_geo_patra': [21.73508, 38.2462],
  };

  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};

  test(
    'CMS Intro and inherited Certified cover both PDOs and their parents',
    () async {
      final mappings = dataset.certificationKnowledgeMappings;
      for (final id in [
        'ki_macedonia_location',
        'ki_peloponnese_location',
        ...targets.keys,
      ]) {
        expect(
          mappings.any(
            (mapping) =>
                mapping.certificationId == 'CMS_INTRODUCTORY' &&
                mapping.knowledgeItemId == id,
          ),
          isTrue,
          reason: id,
        );
      }
      for (final id in ['ki_slopes_of_meliton_location', 'ki_patra_location']) {
        expect(
          mappings.any(
            (mapping) =>
                mapping.certificationId == 'CMS_INTRODUCTORY' &&
                mapping.knowledgeItemId == id &&
                mapping.importance == 'core',
          ),
          isTrue,
          reason: id,
        );
      }

      final db = openTestDatabase();
      addTearDown(db.close);
      await CurriculumIngester(
        db,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final certified = await StudyPlanner(db)
          .effectiveMappings('CMS_CERTIFIED');
      expect(
        certified.keys,
        containsAll([
          ...targets.keys,
          'ki_slopes_of_meliton_assyrtiko',
          'ki_patra_roditis',
        ]),
      );
    },
  );

  test(
    'sourced orientation markers retain their pinned coordinates and roles',
    () {
      final source = jsonDecode(
        File('tool/geography/cms_greece_points.geojson').readAsStringSync(),
      ) as Map<String, dynamic>;
      final features = (source['features'] as List)
          .cast<Map<String, dynamic>>();
      expect(features, hasLength(targets.length));
      final layer = dataset.mapLayers.singleWhere((row) => row.id == layerId);
      final topology = jsonDecode(
        File(layer.assetPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      final geometries =
          ((topology['objects'] as Map).values.single as Map)['geometries']
              as List;
      final byId = {for (final raw in geometries) (raw as Map)['id']: raw};
      for (final feature in features) {
        final properties = feature['properties'] as Map;
        final node = properties['node'] as String;
        expect(pinnedCoordinates, contains(node));
        expect(properties['license'], 'CC-BY-4.0');
        expect(
          properties['source_file_sha256'],
          matches(RegExp(r'^[a-f0-9]{64}$')),
        );
        expect(properties['point_role'], contains('orientation reference'));
        expect(properties['label_note'], contains('not'));
        final point = (feature['geometry'] as Map)['coordinates'] as List;
        expect(point, pinnedCoordinates[node], reason: node);
        expect((byId[node] as Map)['coordinates'], point, reason: node);
        expect(
          dataset.nodeGeometries.any(
            (geometry) =>
                geometry.knowledgeNodeId == node &&
                geometry.mapLayerId == layerId &&
                geometry.featureKey == node,
          ),
          isTrue,
          reason: node,
        );
      }
      for (final entry in targets.entries) {
        expect(items[entry.key]!.subjectId, entry.value);
        expect(items[entry.key]!.relationType, 'LOCATED_IN');
        expect(items[entry.key]!.verificationStatus, 'unverified');
        expect(
          dataset.knowledgeItemCitations.any(
            (citation) => citation.knowledgeItemId == entry.key,
          ),
          isTrue,
        );
      }
    },
  );

  group('generated CMS Greece map practice', () {
    late AppDatabase db;
    late ExercisePresenter presenter;
    late GeoLayer layer;

    setUpAll(() async {
      final time = TestClock(DateTime.utc(2026, 10, 1, 9));
      db = openTestDatabase();
      await CurriculumIngester(
        db,
        clock: time.clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      presenter = ExercisePresenter(db, clock: time.clock);
      final asset = dataset.mapLayers.singleWhere((row) => row.id == layerId);
      layer = GeoLayer.fromTopology(
        Topology.parse(File(asset.assetPath).readAsStringSync()),
        id: layerId,
      );
    });
    tearDownAll(() => db.close());

    test(
      'all five locations generate click, identify and named-pair questions',
      () async {
        final questions = await db.select(db.questions).get();
        for (final id in targets.keys) {
          expect(
            questions
                .where((q) => q.knowledgeItemId == id)
                .map((q) => q.questionTemplateId),
            containsAll([locate, identify, pair]),
            reason: id,
          );
        }
      },
    );

    test('both named PDOs can be found with a real tap and paired', () async {
      for (final entry in {
        'ki_slopes_of_meliton_location': 'n_geo_slopes_of_meliton',
        'ki_patra_location': 'n_geo_patra',
      }.entries) {
        final exercise = await presenter.present(
          entry.key,
          locate,
          seed: 19,
          certificationId: 'CMS_CERTIFIED',
        ) as MapExercise;
        expect(exercise.nodeId, entry.value);
        expect(exercise.candidateIds, contains(entry.value));
        final geometry = exercise.frame.candidates
            .singleWhere((candidate) => candidate.id == entry.value)
            .geometry;
        final point = LonLat(geometry.labelLon, geometry.labelLat);
        final shapes = [
          for (final candidate in exercise.frame.candidates)
            if (candidate.geometry.mapLayerId == layerId)
              layer.shapeFor(candidate.geometry.featureKey)!,
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
        expect(
          MapLocateAnswer.fromTap(tap, preferredNodeId: entry.value).nodeId,
          entry.value,
          reason: entry.key,
        );
        final namedPair = await presenter.present(
          entry.key,
          pair,
          seed: 19,
          certificationId: 'CMS_CERTIFIED',
        ) as MapPairExercise;
        expect(namedPair.itemIds, contains(entry.key));
        expect(namedPair.map.candidateIds, contains(entry.value));
      }
    });

    test(
      'Certified grape clues point to both PDOs without exclusive claims',
      () async {
        final questions = await db.select(db.questions).get();
        for (final entry in {
          'ki_slopes_of_meliton_assyrtiko': (
            'n_geo_slopes_of_meliton',
            'Assyrtiko',
          ),
          'ki_patra_roditis': ('n_geo_patra', 'Roditis'),
        }.entries) {
          expect(
            questions.any(
              (question) =>
                  question.knowledgeItemId == entry.key &&
                  question.questionTemplateId == grapeMap,
            ),
            isTrue,
            reason: entry.key,
          );
          final exercise = await presenter.present(
            entry.key,
            grapeMap,
            seed: 19,
            certificationId: 'CMS_CERTIFIED',
          ) as MapExercise;
          expect(exercise.prompt, contains(entry.value.$2));
          expect(exercise.candidateIds, contains(entry.value.$1));
          expect(exercise.correctNodeIds, contains(entry.value.$1));
          final grades = presenter.grade(
            exercise,
            MapLocateAnswer.fromList(entry.value.$1),
          );
          expect(grades.single.rating, fsrs.Rating.good);
        }
      },
    );
  });
}
