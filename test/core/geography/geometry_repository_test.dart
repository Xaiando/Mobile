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
      expect(layers.length, greaterThanOrEqualTo(15));
      expect(layers.first.layer.minZoom, 0);
      final zooms = layers.map((entry) => entry.layer.minZoom).toList();
      expect(zooms, orderedEquals([...zooms]..sort()));
      final regions = layers.firstWhere((l) => l.layer.id == 'ml_fr_regions');
      expect([
        for (final s in regions.sources) s.id,
      ], containsAll(['src_inao_areas', 'src_ign_admin_express']));
      expect(regions.attribution, allOf(contains('INAO'), contains('IGN')));
      final countries = layers.firstWhere(
        (l) => l.layer.id == 'ml_world_countries',
      );
      expect(
        countries.attribution,
        'Made with Natural Earth. Made with Natural Earth. '
        'Complete source island polygon parts preserve Salt Spring Island '
        'and Rapa Nui in their countries.',
        reason:
            'the identical country/map-unit credit is included once; '
            'the new island source keeps its distinct qualification',
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
    expect(
      ids(await maps.siblingsOf('n_geo_condrieu')),
      containsAll(['n_geo_cornas', 'n_geo_crozes_hermitage']),
    );
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
    expect(
      ids(burgundy.candidates),
      containsAll([
        'n_geo_burgundy',
        'n_geo_champagne_region',
        'n_geo_loire_valley',
        'n_geo_rhone_valley',
      ]),
    );

    final chablis = (await maps.frameOf('n_geo_chablis'))!;
    expect(chablis.parent.id, 'n_geo_burgundy');
    expect(
      ids(chablis.candidates),
      containsAll(['n_geo_chablis', 'n_geo_volnay']),
    );
    expect(chablis.candidates.length, greaterThanOrEqualTo(4));

    // The expanded northern Rhône has enough targets for a local frame.
    final condrieu = (await maps.frameOf('n_geo_condrieu'))!;
    expect(condrieu.parent.id, 'n_geo_northern_rhone');
    expect(condrieu.candidates.length, greaterThanOrEqualTo(4));
    expect(
      ids(condrieu.candidates),
      containsAll(['n_geo_condrieu', 'n_geo_cornas', 'n_geo_crozes_hermitage']),
    );
    final france = GeoBox.of(
      (await maps.geometriesOf('n_geo_france')).single.geometry,
    );
    expect(
      condrieu.box.width,
      lessThan(france.width),
      reason: 'the local northern Rhône frame is smaller than France',
    );

    final world = (await maps.frameOf('n_geo_france'))!;
    expect(world.parent.id, 'n_geo_world');
    expect(
      ids(world.candidates),
      containsAll([
        'n_geo_france',
        'n_geo_italy',
        'n_geo_spain',
        'n_geo_germany',
      ]),
    );
    expect(
      world.candidates.map((candidate) => candidate.node.nodeType),
      everyElement('country'),
    );
    expect(
      await maps.frameOf('n_geo_world'),
      isNull,
      reason: 'World is the outer map frame',
    );
    expect(await maps.frameOf('n_grape_chardonnay'), isNull);
    expect(
      await maps.frameOf('n_geo_condrieu', minimum: 10000),
      isNull,
      reason: 'an impossible minimum cannot create a frame',
    );
  });
}
