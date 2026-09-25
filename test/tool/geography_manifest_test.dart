import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:yaml/yaml.dart';

import '../support/curriculum_fixture.dart';

/// The map layers built by tool/geography (backlog G1), as the renderer
/// (G3) and ingestion (G2) will read them.
void main() {
  final manifest = loadYaml(
    File('assets/geography/manifest.yaml').readAsStringSync(),
  ) as YamlMap;
  final layers = (manifest['map_layers'] as YamlList).cast<YamlMap>();
  final geometries = (manifest['node_geometries'] as YamlList).cast<YamlMap>();

  test('the manifest has the fields map_layers and node_geometries need', () {
    expect(layers, isNotEmpty);
    for (final layer in layers) {
      expect(layer['id'], matches(r'^ml_[a-z0-9_]+$'));
      expect(layer['display_name'], isA<String>());
      expect(['area', 'line', 'point'], contains(layer['geometry_kind']));
      expect(
        layer['asset_path'],
        matches(r'^assets/geography/[a-z0-9_]+\.topo\.json$'),
      );
      expect(layer['asset_sha256'], matches(r'^[0-9a-f]{64}$'));
      expect(layer['min_zoom'], lessThan(layer['max_zoom'] as num));
      expect(layer['source_citation_ids'], isNotEmpty);
      expect(layer['attribution'], isA<String>());
      final parent = layer['parent_layer_id'];
      if (parent != null) {
        expect(layers.map((l) => l['id']), contains(parent));
      }
    }
    for (final g in geometries) {
      expect(layers.map((l) => l['id']), contains(g['map_layer_id']));
      for (final key in [
        'min_lon',
        'min_lat',
        'max_lon',
        'max_lat',
        'label_lon',
        'label_lat',
      ]) {
        expect(g[key], isA<num>(), reason: '${g['knowledge_node_id']} $key');
      }
    }
  });

  test('every node with a geometry exists in the curriculum', () {
    final nodes = {for (final n in bundledDataset().knowledgeNodes) n.id};
    for (final g in geometries) {
      expect(nodes, contains(g['knowledge_node_id']));
    }
  });

  test('each asset matches its checksum, fits its budget and loads', () {
    var total = 0;
    for (final layer in layers) {
      final bytes = File(layer['asset_path'] as String).readAsBytesSync();
      total += bytes.length;
      expect(
        '${sha256.convert(bytes)}',
        layer['asset_sha256'],
        reason: '${layer['id']}',
      );
      expect(
        bytes.length,
        lessThanOrEqualTo(1.5 * 1024 * 1024),
        reason: 'GEO-11',
      );

      final id = layer['id'] as String;
      final own = geometries.where((g) => g['map_layer_id'] == id);
      final loaded = GeoLayer.fromTopology(
        Topology.parse(utf8.decode(bytes)),
        id: id,
        minZoom: (layer['min_zoom'] as num).toDouble(),
        maxZoom: (layer['max_zoom'] as num).toDouble(),
        attribution: layer['attribution'] as String,
        labelPoints: {
          for (final g in own)
            g['feature_key'] as String: LonLat(
              (g['label_lon'] as num).toDouble(),
              (g['label_lat'] as num).toDouble(),
            ),
        },
      );
      expect(loaded.shapes, isNotEmpty, reason: id);
      for (final g in own) {
        final shape = loaded.shapeFor(g['feature_key'] as String);
        expect(shape, isNotNull, reason: '${g['feature_key']} in $id');
        if (layer['geometry_kind'] == 'area') {
          expect(
            shape!.contains(
              WebMercator.project(
                LonLat(
                  (g['label_lon'] as num).toDouble(),
                  (g['label_lat'] as num).toDouble(),
                ),
              ),
            ),
            isTrue,
            reason: '${g['feature_key']}: its label point lies inside it',
          );
        }
      }
    }
    expect(total, lessThanOrEqualTo(8 * 1024 * 1024), reason: 'GEO-11');
  });
}
