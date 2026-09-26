import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

/// Backlog G2: the queries of the map formats, on the bundled layers.
void main() {
  late AppDatabase db;
  late GeometryRepository maps;

  setUp(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    maps = GeometryRepository(db);
  });
  tearDown(() => db.close());

  List<String> ids(Iterable<MappedNode> nodes) => [for (final n in nodes) n.id];

  test(
    'lists the layers, the coarsest first, with composed attributions',
    () async {
      final layers = await maps.layers();
      expect(layers, hasLength(10));
      expect(layers.first.layer.minZoom, 0);
      final regions = layers.firstWhere((l) => l.layer.id == 'ml_fr_regions');
      expect(
        [for (final s in regions.sources) s.id],
        ['src_inao_areas', 'src_ign_admin_express'],
      );
      expect(
        regions.attribution,
        'INAO – aires géographiques des AOC/AOP, 9 October 2025. '
        'IGN – ADMIN EXPRESS COG CARTO, edition of 1 January 2026.',
      );
      final countries = layers.firstWhere(
        (l) => l.layer.id == 'ml_world_countries',
      );
      expect(
        countries.attribution,
        'Made with Natural Earth.',
        reason: 'each text once',
      );
    },
  );

  test("gives a node's geometry, and nothing for a node never drawn", () async {
    final chablis = (await maps.geometriesOf('n_geo_chablis')).single;
    expect(chablis.geometry.mapLayerId, 'ml_fr_appellations');
    expect(chablis.node.name, 'Chablis');
    final box = GeoBox.of(chablis.geometry);
    expect(
      box.contains(chablis.geometry.labelLon, chablis.geometry.labelLat),
      isTrue,
    );
    expect(await maps.geometriesOf('n_grape_chardonnay'), isEmpty);
  });

  test('finds the drawn siblings and the candidates in a box', () async {
    expect(ids(await maps.siblingsOf('n_geo_condrieu')), [
      'n_geo_cornas',
      'n_geo_crozes_hermitage',
    ]);
    final burgundy = (await maps.geometriesOf('n_geo_burgundy')).single;
    final inBurgundy = await maps.candidatesIn(
      GeoBox.of(burgundy.geometry),
      nodeType: 'appellation',
    );
    expect(ids(inBurgundy), containsAll(['n_geo_chablis', 'n_geo_volnay']));
    expect(ids(inBurgundy), isNot(contains('n_geo_condrieu')));
  });

  test('counts a node drawn in two layers once', () async {
    await db.writeCurriculum(
      () => db
          .into(db.nodeGeometries)
          .insert(
            NodeGeometriesCompanion.insert(
              knowledgeNodeId: 'n_geo_condrieu',
              mapLayerId: 'ml_fr_subregions',
              featureKey: 'n_geo_condrieu',
              minLon: 4.7,
              minLat: 45.3,
              maxLon: 4.8,
              maxLat: 45.5,
              labelLon: 4.75,
              labelLat: 45.4,
            ),
          ),
    );
    expect(await maps.geometriesOf('n_geo_condrieu'), hasLength(2));
    final france = (await maps.geometriesOf('n_geo_france')).single;
    final inFrance = ids(
      await maps.candidatesIn(
        GeoBox.of(france.geometry),
        nodeType: 'appellation',
      ),
    );
    expect(inFrance.where((id) => id == 'n_geo_condrieu'), hasLength(1));
    // Condrieu and Cornas share the northern Rhône.
    final siblings = ids(await maps.siblingsOf('n_geo_cornas'));
    expect(siblings.where((id) => id == 'n_geo_condrieu'), hasLength(1));
  });

  test('frames a question on the parent, or a level up for four '
      'candidates (geography §5)', () async {
    final burgundy = (await maps.frameOf('n_geo_burgundy'))!;
    expect(burgundy.parent.id, 'n_geo_france');
    expect(ids(burgundy.candidates), [
      'n_geo_burgundy',
      'n_geo_champagne_region',
      'n_geo_loire_valley',
      'n_geo_rhone_valley',
    ]);

    // The northern Rhône draws three appellations: the frame moves up.
    final condrieu = (await maps.frameOf('n_geo_condrieu'))!;
    expect(condrieu.parent.id, 'n_geo_rhone_valley');
    expect(
      ids(condrieu.candidates),
      containsAll([
        'n_geo_condrieu',
        'n_geo_cornas',
        'n_geo_crozes_hermitage',
        'n_geo_chateauneuf_du_pape',
      ]),
    );
    final france = GeoBox.of(
      (await maps.geometriesOf('n_geo_france')).single.geometry,
    );
    expect(
      condrieu.box.width,
      lessThan(france.width),
      reason: 'framed on the Rhône Valley, not all of France',
    );

    expect(
      await maps.frameOf('n_geo_france'),
      isNull,
      reason: 'France is drawn inside nothing',
    );
    expect(await maps.frameOf('n_grape_chardonnay'), isNull);
    expect(
      await maps.frameOf('n_geo_condrieu', minimum: 30),
      isNull,
      reason: 'no ancestor draws thirty appellations',
    );
  });
}
