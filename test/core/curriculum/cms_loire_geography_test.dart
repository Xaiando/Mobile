import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  const layerId = 'ml_cms_loire_markers';
  const locate = 'qt_located_in_fwd_map_locate';
  const identify = 'qt_located_in_fwd_map_identify';
  const pair = 'qt_located_in_fwd_map_pair';
  const wineRecall = 'qt_principle_explanation_flashcard';
  const locations = {
    'ki_cms_loire_saint_pourcain_location': 'n_geo_saint_pourcain',
    'ki_cms_loire_cheverny_location': 'n_geo_cheverny',
    'ki_cms_loire_orleans_location': 'n_geo_orleans_aoc',
  };
  const wines = [
    'ki_cms_loire_saint_pourcain_red_rose',
    'ki_cms_loire_saint_pourcain_white',
    'ki_cms_loire_cheverny_red_rose',
    'ki_cms_loire_cheverny_white',
    'ki_cms_loire_orleans_red_rose',
    'ki_cms_loire_orleans_white',
  ];
  const coordinates = {
    'n_geo_saint_pourcain': [3.28931, 46.30748],
    'n_geo_cheverny': [1.45951, 47.50079],
    'n_geo_orleans_aoc': [1.90407, 47.90248],
  };

  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};

  test(
    'named municipality markers keep their qualified source coordinates',
    () {
      final source = jsonDecode(
        File('tool/geography/cms_loire_points.geojson').readAsStringSync(),
      ) as Map<String, dynamic>;
      final features = (source['features'] as List)
          .cast<Map<String, dynamic>>();
      expect(features, hasLength(locations.length));
      final asset = dataset.mapLayers.singleWhere(
        (layer) => layer.id == layerId,
      );
      final topology = jsonDecode(
        File(asset.assetPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      final geometries =
          ((topology['objects'] as Map).values.single as Map)['geometries']
              as List;
      final byId = {
        for (final geometry in geometries) (geometry as Map)['id']: geometry,
      };

      for (final feature in features) {
        final properties = feature['properties'] as Map;
        final node = properties['node'] as String;
        final point = (feature['geometry'] as Map)['coordinates'] as List;
        expect(point, coordinates[node], reason: node);
        expect(
          properties['point_role'],
          'qualified_municipality_orientation_reference',
        );
        expect(properties['license'], 'CC-BY-4.0');
        expect(
          properties['label_note'],
          contains('not an official appellation centroid'),
        );
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
    },
  );

  test(
    'Certified includes cited Loire locations and wine-style facts',
    () async {
      for (final entry in locations.entries) {
        expect(items[entry.key]!.subjectId, entry.value);
        expect(items[entry.key]!.relationType, 'LOCATED_IN');
      }
      for (final id in [...locations.keys, ...wines]) {
        expect(items[id]!.verificationStatus, 'unverified', reason: id);
        expect(
          dataset.knowledgeItemCitations.any(
            (citation) => citation.knowledgeItemId == id,
          ),
          isTrue,
          reason: id,
        );
        expect(
          dataset.certificationKnowledgeMappings.any(
            (mapping) =>
                mapping.certificationId == 'CMS_CERTIFIED' &&
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
      expect(certified.keys, containsAll([...locations.keys, ...wines]));
    },
  );

  group('generated Loire map and wine practice', () {
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
      'all three places generate click, identify and named-pair questions',
      () async {
        final questions = await db.select(db.questions).get();
        for (final id in locations.keys) {
          expect(
            questions
                .where((q) => q.knowledgeItemId == id)
                .map((q) => q.questionTemplateId),
            containsAll([locate, identify, pair]),
            reason: id,
          );
        }
        for (final id in wines) {
          expect(
            questions
                .where((q) => q.knowledgeItemId == id)
                .map((q) => q.questionTemplateId),
            contains(wineRecall),
            reason: id,
          );
        }
      },
    );

    test(
      'each appellation can be tapped and used in a named-place pair',
      () async {
        for (final entry in locations.entries) {
          final exercise = await presenter.present(
            entry.key,
            locate,
            seed: 19,
            certificationId: 'CMS_CERTIFIED',
          ) as MapExercise;
          expect(exercise.nodeId, entry.value);
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
      },
    );
  });
}
