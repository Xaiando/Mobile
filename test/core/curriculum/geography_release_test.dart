import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

/// Backlog G2: the release brings in the map layers of tool/geography.
void main() {
  const geography = 'assets/geography/manifest.yaml';

  /// The bundled release's files, with the text of [path] changed by
  /// [change].
  List<DatasetFile> filesWith(String path, String Function(String) change) {
    const manifest = curriculumAssetPath;
    final text = File(manifest).readAsStringSync();
    String read(String file) => file == path
        ? change(File(file).readAsStringSync())
        : File(file).readAsStringSync();
    return [
      DatasetFile(manifest, path == manifest ? change(text) : text),
      for (final include in [
        ...datasetIncludes(manifest, text),
        ?datasetGeography(manifest, text),
      ])
        DatasetFile(include, read(include)),
    ];
  }

  Future<List<int>> readAsset(String path) async =>
      File(path).readAsBytesSync();

  group('the geography manifest', () {
    test('comes with the release; its sources become citations, in order', () {
      final dataset = bundledDataset();
      expect(dataset.files.last, geography);
      expect(dataset.mapLayers.map((layer) => layer.id), [
        'ml_world_continents',
        'ml_world_countries',
        'ml_world_coastline',
        'ml_world_marine',
        'ml_world_lakes',
        'ml_world_rivers',
        'ml_world_physical',
        'ml_fr_regions',
        'ml_fr_subregions',
        'ml_fr_appellations',
        'ml_current_regions_markers',
        'ml_world_atlas_markers',
        'ml_central_europe_atlas_markers',
        'ml_france_champagne_markers',
        'ml_france_atlas_markers',
        'ml_france_chablis_cadastre_markers',
        'ml_france_atlas_completion_markers',
        'ml_france_atlas_completion_cadastre_markers',
        'ml_france_atlas_completion_reference_markers',
        'ml_vino_nobile_pievi_markers',
        'ml_europe_atlas_completion_markers',
        'ml_new_world_atlas_completion_markers',
        'ml_new_world_atlas_completion_gazetteer_markers',
        'ml_british_atlas_markers',
        'ml_china_atlas_markers',
        'ml_diploma_us_atlas_markers',
        'ml_diploma_regions_markers',
        'ml_new_world_oceania_africa_au_gis_markers',
        'ml_new_world_oceania_africa_reference_markers',
        'ml_new_world_oceania_africa_gazetteer_markers',
        'ml_new_world_americas_markers',
        'ml_new_world_americas_gazetteer_markers',
        'ml_soave_uga_wikidata_markers',
        'ml_soave_uga_geonames_markers',
        'ml_alto_adige_uga_geonames_markers',
      ]);
      final featureKeys = <String>[];
      for (final layer in dataset.mapLayers) {
        final topology = jsonDecode(File(layer.assetPath).readAsStringSync());
        final object = (topology['objects'] as Map).values.single as Map;
        for (final feature in object['geometries'] as List) {
          if (feature['id'] != null) {
            featureKeys.add('${layer.id} ${feature['id']}');
          }
        }
      }
      expect(
        dataset.nodeGeometries.map(
          (geometry) => '${geometry.mapLayerId} ${geometry.knowledgeNodeId}',
        ),
        unorderedEquals(featureKeys),
        reason: 'each sourced node feature is present in the release manifest',
      );
      expect(
        [
          for (final c in dataset.mapLayerCitations)
            if (c.mapLayerId == 'ml_world_countries')
              (c.sourceCitationId, c.position),
        ],
        [
          ('src_ne_countries', 1),
          ('src_ne_map_units', 2),
          ('src_ne_americas_island_parts', 3),
        ],
      );
      final chablis = dataset.locate((
        section: 'node_geometries',
        key: 'n_geo_chablis ml_fr_appellations',
      ));
      expect(chablis?.path, geography, reason: 'lint points at its line');
    });

    test('is part of the checksum', () {
      final same = CurriculumDataset.fromFiles(
        filesWith(geography, (text) => text),
      );
      final changed = CurriculumDataset.fromFiles(
        filesWith(geography, (text) => '$text\n# A new comment\n'),
      );
      expect(same.checksum, bundledDataset().checksum);
      expect(changed.checksum, isNot(same.checksum));
    });

    test('refuses a layer without sources, and an unknown column or '
        'section', () {
      for (final change in <String Function(String)>[
        (text) => text.replaceFirst(
          RegExp(r'    source_citation_ids:\r?\n      - src_ne_regions\r?\n'),
          '',
        ),
        (text) => text.replaceFirst(
          '    max_zoom: 3',
          '    max_zoom: 3\n    fill: red',
        ),
        (text) => '$text\nmap_labels: []\n',
      ]) {
        expect(
          () => CurriculumDataset.fromFiles(filesWith(geography, change)),
          throwsA(isA<DatasetFormatException>()),
        );
      }
    });

    test('must be a YAML file inside the assets', () {
      for (final path in [
        '/etc/manifest.yaml',
        '../../../manifest.yaml',
        'x',
      ]) {
        expect(
          () => CurriculumDataset.fromFiles([
            DatasetFile(
              curriculumAssetPath,
              'dataset_version: "1.0.0"\n'
              'published_at: "2026-01-01T00:00:00.000Z"\n'
              'geography: "$path"\n',
            ),
          ]),
          throwsA(isA<DatasetFormatException>()),
          reason: path,
        );
      }
      expect(
        datasetGeography(curriculumAssetPath, 'geography: ../geography/a.yaml'),
        'assets/geography/a.yaml',
      );
      expect(
        datasetGeography(
          '/tmp/x/assets/curriculum/curriculum.yaml',
          'geography: ../geography/a.yaml',
        ),
        '/tmp/x/assets/geography/a.yaml',
        reason: 'a folder from the root stays one',
      );
    });

    test('has the same checksum wherever the release is read', () {
      final temp = Directory.systemTemp.createTempSync('release');
      addTearDown(() => temp.deleteSync(recursive: true));
      for (final path in bundledDataset().files) {
        File('${temp.path}/$path')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(File(path).readAsStringSync());
      }
      final elsewhere = CurriculumDataset.loadSync(
        '${temp.path}/$curriculumAssetPath'.replaceAll(r'\', '/'),
        (path) => File(path).readAsStringSync(),
      );
      expect(elsewhere.mapLayers, bundledDataset().mapLayers);
      expect(elsewhere.nodeGeometries, bundledDataset().nodeGeometries);
      expect(elsewhere.checksum, bundledDataset().checksum);
    });
  });

  group('ingestion', () {
    late AppDatabase db;

    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    test('brings in the layers, their sources and the geometries', () async {
      final dataset = bundledDataset();
      await CurriculumIngester(db, assets: readAsset).ingest(dataset);
      expect(
        await db.select(db.mapLayers).get(),
        unorderedEquals(dataset.mapLayers),
      );
      expect(
        await db.select(db.mapLayerCitations).get(),
        unorderedEquals(dataset.mapLayerCitations),
      );
      expect(
        await db.select(db.nodeGeometries).get(),
        unorderedEquals(dataset.nodeGeometries),
      );
    });

    test('refuses an asset that does not match its SHA-256, and writes '
        'nothing', () async {
      final ingester = CurriculumIngester(
        db,
        assets: (path) async {
          final bytes = File(path).readAsBytesSync();
          return path.endsWith('fr_regions.topo.json') ? [...bytes, 32] : bytes;
        },
      );
      await expectLater(
        ingester.ingest(bundledDataset()),
        throwsA(
          isA<CurriculumIngestionException>().having(
            (e) => e.message,
            'message',
            contains('fr_regions.topo.json does not match its SHA-256'),
          ),
        ),
      );
      expect(await db.select(db.curriculumReleases).get(), isEmpty);
      expect(await db.select(db.mapLayers).get(), isEmpty);
    });

    test('refuses a geometry whose feature its asset lacks', () async {
      final dataset = CurriculumDataset.fromFiles(
        filesWith(
          geography,
          (text) => text.replaceFirst(
            'feature_key: n_geo_volnay',
            'feature_key: n_geo_nowhere',
          ),
        ),
      );
      await expectLater(
        CurriculumIngester(db, assets: readAsset).ingest(dataset),
        throwsA(
          isA<CurriculumIngestionException>().having(
            (e) => e.message,
            'message',
            contains('has no feature n_geo_nowhere for n_geo_volnay'),
          ),
        ),
      );
      expect(await db.select(db.knowledgeNodes).get(), isEmpty);
    });

    test('refuses a geometry of an unknown node', () async {
      final dataset = CurriculumDataset.fromFiles(
        filesWith(
          geography,
          (text) => text.replaceFirst(
            'knowledge_node_id: n_geo_volnay',
            'knowledge_node_id: n_geo_nowhere',
          ),
        ),
      );
      await expectLater(
        CurriculumIngester(db, assets: readAsset).ingest(dataset),
        throwsA(
          isA<CurriculumIngestionException>().having(
            (e) => e.message,
            'message',
            contains('n_geo_nowhere'),
          ),
        ),
      );
      expect(await db.select(db.nodeGeometries).get(), isEmpty);
    });
  });
}
