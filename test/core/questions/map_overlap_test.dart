import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';

void main() {
  // Two legally distinct appellations can share the same geographical
  // commune union. The target must not become unreachable by key sorting.
  final layer = GeoLayer.fromTopology(
    Topology.parse('''
  {"type":"Topology","arcs":[[[3,47],[1,0],[0,1],[-1,0],[0,-1]]],
   "transform":{"scale":[1,1],"translate":[0,0]},
   "objects":{"areas":{"type":"GeometryCollection","geometries":[
    {"type":"Polygon","id":"n_area_a","arcs":[[0]]},
    {"type":"Polygon","id":"n_area_b","arcs":[[0]]}
   ]}}}
  '''),
    id: 'ml_overlap',
  );
  final bounds = GeoBounds(minLon: 2, minLat: 46, maxLon: 5, maxLat: 49);
  MapTap tap(List<MapHit> hits) => MapTap(
    position: const LonLat(3.5, 47.5),
    hits: hits,
    zoom: 8,
    visibleBounds: bounds,
  );

  test('a real tap inside shared polygons accepts either requested target', () {
    final hits = const MapHitTester().hitTest(
      layer.shapes,
      WebMercator.project(const LonLat(3.5, 47.5)),
      65536,
    );
    expect(hits.map((h) => h.key), ['n_area_a', 'n_area_b']);
    expect(hits.map((h) => h.kind), everyElement(HitKind.inside));
    expect(MapLocateAnswer.fromTap(tap(hits)).nodeId, 'n_area_a');
    expect(
      MapLocateAnswer.fromTap(tap(hits), preferredNodeId: 'n_area_b').nodeId,
      'n_area_b',
    );
    expect(
      MapLocateAnswer.fromTap(tap(hits), preferredNodeIds: {'n_area_b'}).nodeId,
      'n_area_b',
    );
  });

  test('a nearby requested target never overrides an exact hit elsewhere', () {
    final exact = MapHit(
      shape: layer.shapes.first,
      kind: HitKind.inside,
      distance: 4,
    );
    final near = MapHit(
      shape: layer.shapes.last,
      kind: HitKind.near,
      distance: 2,
    );
    expect(
      MapLocateAnswer.fromTap(
        tap([exact, near]),
        preferredNodeId: 'n_area_b',
      ).nodeId,
      'n_area_a',
    );
  });

  test('only an equal nearest distance may break a near-hit tie', () {
    final first = MapHit(
      shape: layer.shapes.first,
      kind: HitKind.near,
      distance: 2,
    );
    final tied = MapHit(
      shape: layer.shapes.last,
      kind: HitKind.near,
      distance: 2,
    );
    final farther = MapHit(
      shape: layer.shapes.last,
      kind: HitKind.near,
      distance: 5,
    );
    expect(
      MapLocateAnswer.fromTap(
        tap([first, tied]),
        preferredNodeId: 'n_area_b',
      ).nodeId,
      'n_area_b',
    );
    expect(
      MapLocateAnswer.fromTap(
        tap([first, farther]),
        preferredNodeId: 'n_area_b',
      ).nodeId,
      'n_area_a',
    );
  });
}
