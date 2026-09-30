import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:yaml/yaml.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_identify/map_identify_format.dart';
import 'package:sommelier/core/questions/formats/map_locate/map_locate_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  const layerId = 'ml_alto_adige_uga_geonames_markers';
  const snapshotPath = 'tool/geography/alto_adige_uga_geonames_points.geojson';
  const locateId = 'qt_located_in_fwd_map_locate';
  const identifyId = 'qt_located_in_fwd_map_identify';
  const references = {
    'n_geo_alto_adige_uga_montiggl': (
      name: 'Montiggl',
      alias: 'Monticolo',
      itemId: 'ki_alto_adige_uga_montiggl_location',
      geonamesId: '3172679',
      coordinate: LonLat(11.27682, 46.41792),
    ),
    'n_geo_alto_adige_uga_missian': (
      name: 'Missian',
      alias: 'Missiano',
      itemId: 'ki_alto_adige_uga_missian_location',
      geonamesId: '3173347',
      coordinate: LonLat(11.25418, 46.485),
    ),
  };
  // The first five coordinates were already shipped; these remain unchanged.
  const existingPoints = {
    'n_geo_alto_adige_uga_buchholz': [11.2424, 46.24623],
    'n_geo_alto_adige_uga_girlan': [11.28115, 46.46329],
    'n_geo_alto_adige_uga_gries': [11.33333, 46.51667],
    'n_geo_alto_adige_uga_penon': [11.20115, 46.30188],
    'n_geo_alto_adige_uga_rain': [11.21286, 46.30889],
  };
  final expectedPoints = {
    ...existingPoints,
    for (final entry in references.entries)
      entry.key: [entry.value.coordinate.lon, entry.value.coordinate.lat],
  };

  test(
    'municipal aliases and settlement sources preserve secondary track scope',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      final plan = dataset.sourceCitations.singleWhere(
        (row) => row.id == 'src_alto_adige_eppan_bilingual_plan',
      );
      expect(plan.kind, 'government_publication');
      expect(plan.publisher, contains('Appiano'));
      expect(
        plan.url,
        'https://www.comune.appiano.bz.it/system/web/GetDocument.ashx?cts=1761816820&fileId=1517923',
      );
      expect(
        plan.documentIdentifier,
        contains(
          'b29822c6d0e83744ad961da7a2be9147344c31f31177b443e6ebc9bbd53c66f9',
        ),
      );
      for (final entry in references.entries) {
        final node = dataset.knowledgeNodes.singleWhere(
          (row) => row.id == entry.key,
        );
        expect(node.name, entry.value.name);
        final alias = dataset.nodeAlternativeNames.singleWhere(
          (row) =>
              row.knowledgeNodeId == entry.key && row.name == entry.value.alias,
        );
        expect(alias.kind, 'synonym');
        final item = dataset.knowledgeItems.singleWhere(
          (row) => row.id == entry.value.itemId,
        );
        expect(item.subjectId, entry.key);
        expect(item.objectId, 'n_geo_alto_adige');
        expect(item.relationType, 'LOCATED_IN');
        expect(item.domainId, 'geography');
        expect(item.verificationStatus, 'unverified');
        expect(item.assertionText, contains('settlement reference in Appiano'));
        expect(
          item.assertionText,
          contains(
            'not a legal unit boundary, official centroid or assertion of parcel eligibility',
          ),
        );
        final relation = dataset.knowledgeRelations.singleWhere(
          (row) =>
              row.subjectId == entry.key && row.relationType == 'LOCATED_IN',
        );
        expect(relation.objectId, 'n_geo_alto_adige');
        final mappings = dataset.certificationKnowledgeMappings
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(mappings, hasLength(2), reason: item.id);
        expect(
          mappings.map((row) => row.certificationId).toSet(),
          {'WSET_L3', 'CMS_CERTIFIED'},
          reason:
              'these qualified references do not become required WSET outcomes',
        );
        for (final mapping in mappings) {
          expect(mapping.importance, 'secondary', reason: item.id);
          expect(mapping.minimumDepth, 2, reason: item.id);
        }
        final citations = dataset.knowledgeItemCitations
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(citations.map((row) => row.sourceCitationId).toSet(), {
          'src_alto_adige_ugas',
          'src_alto_adige_eppan_bilingual_plan',
          'src_alto_adige_uga_geonames_markers',
        });
        expect(
          citations
              .singleWhere(
                (row) =>
                    row.sourceCitationId ==
                    'src_alto_adige_uga_geonames_markers',
              )
              .locator,
          contains('record${entry.value.geonamesId}'),
        );
        final prerequisite = dataset.knowledgeItemPrerequisites.singleWhere(
          (row) => row.knowledgeItemId == item.id,
        );
        expect(prerequisite.prerequisiteItemId, 'ki_eac_alto_adige_location');
      }
    },
  );

  test('five original and two bilingual markers are point references in both assets', () {
    final layer = dataset.mapLayers.singleWhere((row) => row.id == layerId);
    expect(layer.geometryKind, 'point');
    expect(layer.displayName, contains('settlement reference'));
    final manifest = loadYaml(
      File('assets/geography/manifest.yaml').readAsStringSync(),
    ) as Map;
    final layerRecord = (manifest['map_layers'] as List)
        .cast<Map<dynamic, dynamic>>()
        .singleWhere((row) => row['id'] == layerId);
    expect(
      layerRecord['attribution'],
      contains('not Alto Adige unit boundaries or official centroids'),
    );
    final asset = File(layer.assetPath);
    final assetBytes = asset.readAsBytesSync();
    expect(assetBytes.length, layerRecord['asset_bytes']);
    expect(sha256.convert(assetBytes).toString(), layer.assetSha256);
    final topology = Topology.parse(asset.readAsStringSync());
    final features = topology.objects.values.single;
    expect(features.map((row) => row.id).toSet(), expectedPoints.keys.toSet());
    expect(features, hasLength(7));
    for (final feature in features) {
      expect(feature.geometry, isA<TopoPoints>(), reason: feature.id);
      expect(
        (feature.geometry as TopoPoints).coordinates.toList(),
        expectedPoints[feature.id],
        reason: feature.id,
      );
    }
    final snapshot = jsonDecode(File(snapshotPath).readAsStringSync()) as Map;
    final sourceFeatures = snapshot['features'] as List;
    final sourceByNode = {
      for (final raw in sourceFeatures)
        (raw['properties'] as Map)['node'] as String: raw as Map,
    };
    expect(sourceByNode.keys.toSet(), expectedPoints.keys.toSet());
    for (final entry in expectedPoints.entries) {
      final raw = sourceByNode[entry.key]!;
      expect((raw['geometry'] as Map)['type'], 'Point');
      expect((raw['geometry'] as Map)['coordinates'], entry.value);
      final geometry = dataset.nodeGeometries.singleWhere(
        (row) => row.knowledgeNodeId == entry.key && row.mapLayerId == layerId,
      );
      expect(geometry.featureKey, entry.key);
      expect(geometry.labelLon, entry.value[0]);
      expect(geometry.labelLat, entry.value[1]);
      expect(
        geometry.minLon,
        geometry.maxLon,
        reason: 'a point has no wine-area boundary',
      );
      expect(geometry.minLat, geometry.maxLat);
    }
    for (final entry in references.entries) {
      final properties = sourceByNode[entry.key]!['properties'] as Map;
      expect(properties['name'], entry.value.name);
      expect(properties['geonames_id'], entry.value.geonamesId);
      expect(properties['geonames_admin3'], '021004');
      expect(properties['license'], 'CC BY 4.0');
      expect(properties['point_role'], contains('settlement'));
      expect(properties['point_role'], contains('not a unit boundary'));
      expect(properties['identity_source_url'], planUrl);
      expect(properties['identity_source_page'], 54);
      expect(
        properties['identity_source_sha256'],
        'b29822c6d0e83744ad961da7a2be9147344c31f31177b443e6ebc9bbd53c66f9',
      );
    }
  });

  test('both qualified references are delivered, tapped and identified with meaningful grades', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(dataset.publishedAt);
      final report = await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final questions = await db.select(db.questions).get();
      final planner = StudyPlanner(db, clock: fixed);
      for (final track in ['WSET_L3', 'CMS_CERTIFIED']) {
        final cards = await planner.cards(track);
        for (final reference in references.values) {
          final card = cards.singleWhere(
            (row) => row.itemId == reference.itemId,
          );
          expect(
            card.formats.map((row) => row.questionTemplateId),
            containsAll([locateId, identifyId]),
            reason: '$track serves both map formats for ${reference.itemId}',
          );
        }
      }
      final layerAssets = {
        for (final layer in await db.select(db.mapLayers).get())
          layer.id: layer.assetPath,
      };
      final loadedLayers = <String, GeoLayer>{};
      GeoLayer loadLayer(String id) => loadedLayers.putIfAbsent(
        id,
        () => GeoLayer.fromTopology(
          Topology.parse(File(layerAssets[id]!).readAsStringSync()),
          id: id,
        ),
      );
      MapTap tapAt(MapExercise exercise, LonLat at) {
        final frame = exercise.frame.box;
        final shapes = [
          for (final candidate in exercise.frame.candidates)
            loadLayer(candidate.geometry.mapLayerId)
                .shapeFor(candidate.geometry.featureKey)!,
        ];
        final pixelsPerWorld = 400 / ((frame.maxLon - frame.minLon) / 360);
        return MapTap(
          position: at,
          hits: const MapHitTester().hitTest(
            shapes,
            WebMercator.project(at),
            pixelsPerWorld,
          ),
          zoom: 8,
          visibleBounds: GeoBounds(
            minLon: frame.minLon,
            minLat: frame.minLat,
            maxLon: frame.maxLon,
            maxLat: frame.maxLat,
          ),
        );
      }

      final presenter = ExercisePresenter(db, clock: fixed);
      for (final entry in references.entries) {
        for (final template in [locateId, identifyId]) {
          expect(
            questions.where(
              (row) =>
                  row.knowledgeItemId == entry.value.itemId &&
                  row.questionTemplateId == template,
            ),
            hasLength(1),
            reason: entry.value.itemId,
          );
          expect(
            report.skipped.where(
              (row) =>
                  row.itemId == entry.value.itemId &&
                  row.templateId == template,
            ),
            isEmpty,
          );
        }
        final locate = await presenter.present(
          entry.value.itemId,
          locateId,
          certificationId: 'WSET_L3',
          seed: 19,
        ) as MapExercise;
        expect(locate.nodeId, entry.key);
        expect(locate.nodeName, entry.value.name);
        expect(locate.prompt, 'Find ${entry.value.name} on the map.');
        expect(locate.correctNodeIds, {entry.key});
        expect(locate.candidateIds, containsAll(expectedPoints.keys));
        expect(locate.explanation, contains('settlement reference in Appiano'));
        expect(
          locate.explanation,
          contains(
            'not a legal unit boundary, official centroid or assertion of parcel eligibility',
          ),
        );
        final candidate = locate.frame.candidates.singleWhere(
          (row) => row.id == entry.key,
        );
        final shape = loadLayer(candidate.geometry.mapLayerId)
            .shapeFor(candidate.geometry.featureKey)!;
        expect(shape.kind, GeometryKind.point);
        final tap = tapAt(locate, entry.value.coordinate);
        expect(tap.hits.map((hit) => hit.key), contains(entry.key));
        final correct = const MapLocateFormat()
            .grade(
              locate,
              MapLocateAnswer.fromTap(tap, preferredNodeId: entry.key),
            )
            .single;
        expect(correct.itemId, entry.value.itemId);
        expect(correct.rating, fsrs.Rating.good);
        expect(correct.selectedNodeId, entry.key);
        expect(
          correct.payload,
          containsPair('tap', [
            entry.value.coordinate.lon,
            entry.value.coordinate.lat,
          ]),
        );

        // A preserved, distinct settlement is still a meaningful incorrect tap.
        const wrongNode = 'n_geo_alto_adige_uga_buchholz';
        final wrongGeometry = locate.frame.candidates
            .singleWhere((row) => row.id == wrongNode)
            .geometry;
        final wrongTap = tapAt(
          locate,
          LonLat(wrongGeometry.labelLon, wrongGeometry.labelLat),
        );
        expect(wrongTap.hits.map((hit) => hit.key), contains(wrongNode));
        final wrong = const MapLocateFormat()
            .grade(
              locate,
              MapLocateAnswer.fromTap(wrongTap, preferredNodeId: wrongNode),
            )
            .single;
        expect(wrong.rating, fsrs.Rating.again);
        expect(wrong.selectedNodeId, wrongNode);
        final outside = tapAt(
          locate,
          LonLat(locate.frame.box.minLon - 20, locate.frame.box.minLat - 20),
        );
        expect(outside.hit, isNull);
        expect(
          const MapLocateFormat()
              .grade(locate, MapLocateAnswer.fromTap(outside))
              .single
              .rating,
          fsrs.Rating.again,
        );

        final identify = await presenter.present(
          entry.value.itemId,
          identifyId,
          certificationId: 'CMS_CERTIFIED',
          seed: 19,
        ) as MapExercise;
        expect(identify.nodeId, entry.key);
        expect(identify.prompt, 'Name the highlighted area.');
        expect(identify.correctNodeIds, {entry.key});
        expect(identify.mode, MapMode.outline);
        expect(identify.options, hasLength(4));
        expect(identify.options.map((row) => row.nodeId).toSet(), hasLength(4));
        expect(identify.explanation, locate.explanation);
        // The generic format highlights the sourced point; it never supplies a legal polygon.
        final highlighted = identify.frame.candidates
            .singleWhere((row) => row.id == entry.key)
            .geometry;
        expect(
          loadLayer(highlighted.mapLayerId)
              .shapeFor(highlighted.featureKey)!
              .kind,
          GeometryKind.point,
        );
        for (final option in identify.options) {
          final grade = const MapIdentifyFormat()
              .grade(identify, option)
              .single;
          expect(grade.itemId, entry.value.itemId);
          expect(
            grade.rating,
            option.nodeId == entry.key ? fsrs.Rating.good : fsrs.Rating.again,
          );
          expect(grade.selectedNodeId, option.nodeId);
          expect(
            grade.optionNodeIds,
            identify.options.map((row) => row.nodeId).toList(),
          );
        }
      }
    } finally {
      await db.close();
    }
  });
}

const planUrl =
    'https://www.comune.appiano.bz.it/system/web/GetDocument.ashx?cts=1761816820&fileId=1517923';
