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
      expect(dataset.mapLayers, hasLength(10));
      expect(dataset.nodeGeometries, hasLength(20));
      expect(
        [
          for (final c in dataset.mapLayerCitations)
            if (c.mapLayerId == 'ml_world_countries')
              (c.sourceCitationId, c.position),
        ],
        [('src_ne_countries', 1), ('src_ne_map_units', 2)],
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
      expect(elsewhere.mapLayers, hasLength(10));
      expect(elsewhere.checksum, bundledDataset().checksum);
    });
  });

  group('ingestion', () {
    late AppDatabase db;

    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    test('brings in the layers, their sources and the geometries', () async {
      await CurriculumIngester(db, assets: readAsset).ingest(bundledDataset());
      expect(await db.select(db.mapLayers).get(), hasLength(10));
      expect(await db.select(db.mapLayerCitations).get(), hasLength(14));
      expect(await db.select(db.nodeGeometries).get(), hasLength(20));
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
