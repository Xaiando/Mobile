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
  const layerId = 'ml_cms_eastern_europe_markers';
  const locate = 'qt_located_in_fwd_map_locate';
  const identify = 'qt_located_in_fwd_map_identify';
  const pair = 'qt_located_in_fwd_map_pair';
  const grape = 'qt_permitted_grape_fwd_map_grape';
  const locationTargets = {
    'ki_cms_bg_danubian_location': 'n_geo_danubian_plain_bg',
    'ki_cms_bg_thracian_location': 'n_geo_thracian_lowlands_bg',
    'ki_cms_bg_melnik_location': 'n_geo_melnik_pdo',
    'ki_cms_bg_lyubimets_location': 'n_geo_lyubimets_pdo',
    'ki_cms_ro_tarnave_location': 'n_geo_tarnave',
    'ki_cms_ro_cotnari_location': 'n_geo_cotnari',
    'ki_cms_ro_dealu_mare_location': 'n_geo_dealu_mare',
    'ki_cms_ro_murfatlar_location': 'n_geo_murfatlar',
    'ki_cms_ro_recas_location': 'n_geo_recas',
  };
  const grapeTargets = {
    'ki_cms_bg_danubian_gamza': ('n_geo_danubian_plain_bg', 'Gamza'),
    'ki_cms_bg_lyubimets_mavrud': ('n_geo_lyubimets_pdo', 'Mavrud'),
    'ki_cms_bg_melnik_shiroka': ('n_geo_melnik_pdo', 'Shiroka Melnishka Loza'),
    'ki_cms_ro_tarnave_feteasca_regala': ('n_geo_tarnave', 'Fetească Regală'),
    'ki_cms_ro_cotnari_grasa': ('n_geo_cotnari', 'Grasă de Cotnari'),
    'ki_cms_ro_dealu_mare_feteasca_neagra': (
      'n_geo_dealu_mare',
      'Fetească Neagră',
    ),
  };
  const mappedGrapeTargets = {
    'ki_cms_bg_lyubimets_mavrud',
    'ki_cms_ro_cotnari_grasa',
  };
  const completeGrapeUnions = {
    'n_geo_lyubimets_pdo': (19, 'src_cms_bg_lyubimets_spec'),
    'n_geo_cotnari': (11, 'src_cms_ro_cotnari_spec'),
  };
  const coordinates = {
    'n_geo_danubian_plain_bg': [24.61666, 43.41791],
    'n_geo_thracian_lowlands_bg': [24.75001, 42.15387],
    'n_geo_melnik_pdo': [23.28333, 41.56667],
    'n_geo_lyubimets_pdo': [26.08115, 41.84432],
    'n_geo_tarnave': [24.35, 46.16667],
    'n_geo_cotnari': [26.98333, 47.35],
    'n_geo_dealu_mare': [26.23333, 44.98333],
    'n_geo_murfatlar': [28.41667, 44.18333],
    'n_geo_recas': [21.50083, 45.79889],
  };

  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};

  test(
    'district and grape facts are mapped to CMS Certified and cited',
    () async {
      final mappings = dataset.certificationKnowledgeMappings;
      for (final id in [...locationTargets.keys, ...grapeTargets.keys]) {
        expect(
          mappings.any(
            (mapping) =>
                mapping.certificationId == 'CMS_CERTIFIED' &&
                mapping.knowledgeItemId == id,
          ),
          isTrue,
          reason: id,
        );
        expect(
          dataset.knowledgeItemCitations.any(
            (citation) => citation.knowledgeItemId == id,
          ),
          isTrue,
          reason: id,
        );
      }
      for (final entry in locationTargets.entries) {
        expect(items[entry.key]!.subjectId, entry.value);
        expect(items[entry.key]!.relationType, 'LOCATED_IN');
      }
      for (final entry in grapeTargets.entries) {
        expect(items[entry.key]!.subjectId, entry.value.$1);
        expect(items[entry.key]!.relationType, 'PERMITS_GRAPE');
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
        containsAll([...locationTargets.keys, ...grapeTargets.keys]),
      );
    },
  );

  test('all nine named settlement markers retain source and coordinates', () {
    final source = jsonDecode(
      File('tool/geography/cms_eastern_europe_points.geojson')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final features = (source['features'] as List).cast<Map<String, dynamic>>();
    expect(features, hasLength(locationTargets.length));
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
      expect(coordinates, contains(node));
      expect(properties['license'], 'CC BY 4.0');
      expect(properties['point_role'], contains('orientation reference'));
      expect(properties['point_note'], contains('not'));
      expect(properties['geonames_id'], matches(RegExp(r'^\d+$')));
      final point = (feature['geometry'] as Map)['coordinates'] as List;
      expect(point, coordinates[node], reason: node);
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
    for (final country in ['n_geo_bulgaria', 'n_geo_romania']) {
      expect(
        dataset.nodeGeometries.any(
          (geometry) =>
              geometry.knowledgeNodeId == country &&
              geometry.mapLayerId == 'ml_world_countries',
        ),
        isTrue,
      );
    }
  });

  test('only two grape permissions have cited complete legal unions', () {
    for (final entry in completeGrapeUnions.entries) {
      final members = dataset.knowledgeRelations.where(
        (relation) =>
            relation.subjectId == entry.key &&
            relation.relationType == 'PERMITS_GRAPE',
      );
      expect(
        members.map((relation) => relation.objectId).toSet(),
        hasLength(entry.value.$1),
        reason: entry.key,
      );
      expect(
        dataset.relationSetAssertions.any(
          (assertion) =>
              assertion.nodeId == entry.key &&
              assertion.relationType == 'PERMITS_GRAPE' &&
              assertion.direction == 'forward' &&
              assertion.memberNodeType == 'grape' &&
              assertion.sourceCitationId == entry.value.$2,
        ),
        isTrue,
        reason: entry.key,
      );
    }
    for (final itemId in grapeTargets.keys.toSet().difference(
      mappedGrapeTargets,
    )) {
      expect(
        dataset.relationSetAssertions.any(
          (assertion) =>
              assertion.nodeId == grapeTargets[itemId]!.$1 &&
              assertion.relationType == 'PERMITS_GRAPE',
        ),
        isFalse,
        reason: itemId,
      );
    }
  });

  group('generated Bulgarian and Romanian map practice', () {
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

    MapLocateAnswer tapFor(MapExercise exercise, String node) {
      final geometry = exercise.frame.candidates
          .singleWhere((candidate) => candidate.id == node)
          .geometry;
      final point = LonLat(geometry.labelLon, geometry.labelLat);
      final box = exercise.frame.box;
      final tap = MapTap(
        position: point,
        hits: const MapHitTester().hitTest(
          [layer.shapeFor(geometry.featureKey)!],
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
      return MapLocateAnswer.fromTap(tap, preferredNodeId: node);
    }

    test(
      'each district yields click, identify and named-pair questions',
      () async {
        final questions = await db.select(db.questions).get();
        for (final id in locationTargets.keys) {
          expect(
            questions
                .where((q) => q.knowledgeItemId == id)
                .map((q) => q.questionTemplateId),
            containsAll([locate, identify, pair]),
            reason: id,
          );
        }
        for (final id in grapeTargets.keys) {
          final templates = questions
              .where((q) => q.knowledgeItemId == id)
              .map((q) => q.questionTemplateId);
          expect(
            templates,
            contains('qt_permitted_grape_fwd_flashcard'),
            reason: id,
          );
          if (mappedGrapeTargets.contains(id)) {
            expect(templates, contains(grape), reason: id);
          } else {
            expect(templates, isNot(contains(grape)), reason: id);
          }
        }
      },
    );

    test(
      'district location and grape prompts accept a real marker tap',
      () async {
        for (final entry in locationTargets.entries) {
          final exercise = await presenter.present(
            entry.key,
            locate,
            seed: 19,
            certificationId: 'CMS_CERTIFIED',
          ) as MapExercise;
          expect(exercise.candidateIds, contains(entry.value));
          expect(tapFor(exercise, entry.value).nodeId, entry.value);
        }
        for (final entry in grapeTargets.entries.where(
          (entry) => mappedGrapeTargets.contains(entry.key),
        )) {
          final exercise = await presenter.present(
            entry.key,
            grape,
            seed: 19,
            certificationId: 'CMS_CERTIFIED',
          ) as MapExercise;
          expect(exercise.prompt, contains(entry.value.$2));
          expect(exercise.correctNodeIds, contains(entry.value.$1));
          final answer = tapFor(exercise, entry.value.$1);
          expect(answer.nodeId, entry.value.$1);
          expect(
            presenter.grade(exercise, answer).map((grade) => grade.rating),
            everyElement(fsrs.Rating.good),
            reason: entry.key,
          );
        }
        final namedPair = await presenter.present(
          'ki_cms_ro_cotnari_location',
          pair,
          seed: 19,
          certificationId: 'CMS_CERTIFIED',
        ) as MapPairExercise;
        expect(namedPair.itemIds, contains('ki_cms_ro_cotnari_location'));
        expect(namedPair.map.candidateIds, contains('n_geo_cotnari'));
      },
    );
  });
}
