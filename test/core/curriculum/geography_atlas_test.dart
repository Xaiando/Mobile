import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
  });
  tearDown(() => db.close());

  test(
    'every authored location has a sourced target and a clickable question',
    () async {
      final dataset = bundledDataset();
      final locations = dataset.knowledgeItems
          .where((i) => i.relationType == 'LOCATED_IN')
          .toList();
      final mapped = dataset.nodeGeometries
          .map((g) => g.knowledgeNodeId)
          .toSet();
      final questions = await db.select(db.questions).get();
      final locate = questions
          .where((q) => q.questionTemplateId == 'qt_located_in_fwd_map_locate')
          .map((q) => q.knowledgeItemId)
          .toSet();
      final pair = questions
          .where((q) => q.questionTemplateId == 'qt_located_in_fwd_map_pair')
          .map((q) => q.knowledgeItemId)
          .toSet();
      final identify = questions
          .where(
            (q) => q.questionTemplateId == 'qt_located_in_fwd_map_identify',
          )
          .map((q) => q.knowledgeItemId)
          .toSet();
      expect(locations.length, greaterThanOrEqualTo(400));
      for (final item in locations) {
        expect(
          mapped,
          contains(item.subjectId),
          reason: '${item.id} lacks a sourced location',
        );
        expect(
          locate,
          contains(item.id),
          reason: '${item.id} cannot be clicked',
        );
        expect(
          pair,
          contains(item.id),
          reason: '${item.id} cannot participate in named-place practice',
        );
        expect(
          identify,
          contains(item.id),
          reason: '${item.id} cannot be named',
        );
      }
    },
  );

  test(
    'Chablis Grand Cru climats have seven distinct vineyard targets',
    () async {
      final maps = GeometryRepository(db);
      final coordinates = <(double, double)>{};
      for (final climat in [
        'blanchot',
        'bougros',
        'les_clos',
        'grenouilles',
        'preuses',
        'valmur',
        'vaudesir',
      ]) {
        final node = 'n_geo_chablis_gc_$climat';
        final geometry = (await maps.geometriesOf(node)).single.geometry;
        coordinates.add((geometry.labelLon, geometry.labelLat));
        final frame = await maps.frameOf(node);
        expect(frame, isNotNull, reason: node);
        expect(frame!.candidates.map((n) => n.id), contains(node));
        expect(
          frame.box.width,
          lessThan(0.5),
          reason: 'a local vineyard question',
        );
      }
      expect(
        coordinates,
        hasLength(7),
        reason: 'shared commune centroids cannot distinguish these climats',
      );
    },
  );

  test('selected Chablis Premier Crus have distinct local targets', () async {
    final maps = GeometryRepository(db);
    final coordinates = <(double, double)>{};
    for (final site in [
      'fourchaume',
      'montee_de_tonnerre',
      'mont_de_milieu',
      'vaulorent',
      'vaillons',
      'montmains',
      'cote_de_lechet',
      'beauroy',
      'vaucoupin',
      'vosgros',
    ]) {
      final node = 'n_geo_chablis_pc_$site';
      final geometry = (await maps.geometriesOf(node)).single.geometry;
      coordinates.add((geometry.labelLon, geometry.labelLat));
      final frame = await maps.frameOf(node);
      expect(frame, isNotNull, reason: node);
      expect(
        frame!.candidates.map((candidate) => candidate.id),
        contains(node),
      );
      expect(frame.box.width, lessThan(0.5));
    }
    expect(coordinates, hasLength(10));
  });

  test(
    'complete Chablis and Alsace named lists stay independently clickable',
    () async {
      final dataset = bundledDataset();
      final maps = GeometryRepository(db);
      for (final (prefix, expected) in [
        ('n_geo_chablis_pc_', 40),
        ('n_geo_alsace_grand_cru_', 51),
      ]) {
        final nodes = dataset.knowledgeNodes
            .where((node) => node.id.startsWith(prefix))
            .toList();
        expect(nodes, hasLength(expected));
        final coordinates = <(double, double)>{};
        for (final node in nodes) {
          final target = (await maps.geometriesOf(node.id)).single.geometry;
          coordinates.add((target.labelLon, target.labelLat));
          final frame = await maps.frameOf(node.id);
          expect(frame, isNotNull, reason: node.name);
          expect(frame!.candidates.map((c) => c.id), contains(node.id));
        }
        expect(
          coordinates,
          hasLength(expected),
          reason: 'different named targets must not share one village point',
        );
      }
    },
  );
}
