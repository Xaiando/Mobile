import 'dart:convert';
import 'dart:math' as math;

import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/topojson.dart';

/// A small quantized topology of made-up places, "Fixtureland", for the
/// renderer's tests. Test data, not geography: the shapes are squares.
///
/// Quantized positions map to degrees as lon = 2 + x / 1000 and
/// lat = 46 + y / 1000. The features:
///
/// - `country`: Fixtureland, lon 2.2–5.8, lat 46.2–48.8;
/// - `regions`: Fixture Region, lon 2.8–5.7, lat 46.3–48.7, the parent;
/// - `areas`, the candidates and one context feature:
///   - North Hills, lon 3–4, lat 47.5–48.5, with a hole at lon 3.4–3.6,
///     lat 47.9–48.1, sharing its southern border with
///   - South Plain, lon 3–4, lat 46.5–47.5;
///   - Twin Isles, two squares at lon 4.6–5, lat 48–48.4 and 46.8–47.2;
///   - Tiny Clos, lon 5.5–5.51, lat 47.5–47.51, too small to tap;
///   - East Slope, lon 5.2–5.6, lat 48.2–48.6, not a candidate;
///   - a geometry of null type, which decoding leaves out;
/// - `rivers`: Fixture River, through lon 2.5–2.9;
/// - `places`: Fixture Village, a point at lon 5.2, lat 46.6.
const fixtureTopoJson = '''
{
  "type": "Topology",
  "transform": {"scale": [0.001, 0.001], "translate": [2, 46]},
  "arcs": [
    [[1000, 1500], [1000, 0]],
    [[2000, 1500], [0, 1000], [-1000, 0], [0, -1000]],
    [[1400, 1900], [0, 200], [200, 0], [0, -200], [-200, 0]],
    [[1000, 1500], [0, -1000], [1000, 0], [0, 1000]],
    [[2600, 2000], [400, 0], [0, 400], [-400, 0], [0, -400]],
    [[2600, 800], [400, 0], [0, 400], [-400, 0], [0, -400]],
    [[3500, 1500], [10, 0], [0, 10], [-10, 0], [0, -10]],
    [[3200, 2200], [400, 0], [0, 400], [-400, 0], [0, -400]],
    [[800, 300], [2900, 0], [0, 2400], [-2900, 0], [0, -2400]],
    [[200, 200], [3600, 0], [0, 2600], [-3600, 0], [0, -2600]],
    [[500, 2700], [300, -700], [-100, -1000], [200, -700]]
  ],
  "objects": {
    "country": {"type": "GeometryCollection", "geometries": [
      {"type": "Polygon", "id": "n_fx_country", "properties": {"name": "Fixtureland"}, "arcs": [[9]]}
    ]},
    "regions": {"type": "GeometryCollection", "geometries": [
      {"type": "Polygon", "id": "n_fx_region", "properties": {"name": "Fixture Region"}, "arcs": [[8]]}
    ]},
    "areas": {"type": "GeometryCollection", "geometries": [
      {"type": "Polygon", "id": "n_fx_north", "properties": {"name": "North Hills"}, "arcs": [[0, 1], [2]]},
      {"type": "Polygon", "id": "n_fx_south", "properties": {"name": "South Plain"}, "arcs": [[3, -1]]},
      {"type": "MultiPolygon", "id": "n_fx_isles", "properties": {"name": "Twin Isles"}, "arcs": [[[4]], [[5]]]},
      {"type": "Polygon", "id": "n_fx_tiny", "properties": {"name": "Tiny Clos"}, "arcs": [[6]]},
      {"type": "Polygon", "id": "n_fx_east", "properties": {"name": "East Slope"}, "arcs": [[7]]},
      {"type": null, "id": "n_fx_nothing"}
    ]},
    "rivers": {"type": "GeometryCollection", "geometries": [
      {"type": "LineString", "id": "n_fx_river", "properties": {"name": "Fixture River"}, "arcs": [10]}
    ]},
    "places": {"type": "GeometryCollection", "geometries": [
      {"type": "Point", "id": "n_fx_village", "properties": {"name": "Fixture Village"}, "coordinates": [3200, 600]}
    ]}
  }
}
''';

/// The candidates of the fixture's map questions.
const fixtureCandidates = {
  'n_fx_north',
  'n_fx_south',
  'n_fx_isles',
  'n_fx_tiny',
  'n_fx_village',
};

/// The fixture as layers: the country and river are base layers.
final class FixtureLayers {
  FixtureLayers() : this._(Topology.parse(fixtureTopoJson));

  FixtureLayers._(this.topology)
    : country = GeoLayer.fromTopology(
        topology,
        id: 'ml_fx_country',
        object: 'country',
        attribution: 'Fixture country data',
      ),
      regions = GeoLayer.fromTopology(
        topology,
        id: 'ml_fx_regions',
        object: 'regions',
      ),
      areas = GeoLayer.fromTopology(
        topology,
        id: 'ml_fx_areas',
        object: 'areas',
        attribution: 'Fixture area data',
      ),
      rivers = GeoLayer.fromTopology(
        topology,
        id: 'ml_fx_rivers',
        object: 'rivers',
      ),
      places = GeoLayer.fromTopology(
        topology,
        id: 'ml_fx_places',
        object: 'places',
      );

  final Topology topology;
  final GeoLayer country;
  final GeoLayer regions;
  final GeoLayer areas;
  final GeoLayer rivers;
  final GeoLayer places;

  /// The parent's box: the frame of a question about its areas.
  GeoBounds get regionFrame =>
      GeoBounds(minLon: 2.8, minLat: 46.3, maxLon: 5.7, maxLat: 48.7);

  /// One level up: the country's box.
  GeoBounds get countryFrame =>
      GeoBounds(minLon: 2.2, minLat: 46.2, maxLon: 5.8, maxLat: 48.8);
}

/// A synthetic layer of [columns] × [rows] cells, lon 0 to 0.2 · [columns]
/// and lat 40 to 40 + 0.2 · [rows], with wavy borders of [pointsPerEdge]
/// points shared between neighbours: the stress layer of geography §10.
/// Cell (i, j) has the key `n_stress_<i>_<j>`.
String stressTopoJson({
  int columns = 50,
  int rows = 40,
  int pointsPerEdge = 30,
  int seed = 7,
}) {
  const cell = 2000;
  final random = math.Random(seed);
  final arcs = <List<List<int>>>[];

  // An edge between two grid nodes. Inner edges wave across the straight
  // line, like a commune border; the outer border is straight.
  List<List<int>> edge(int x0, int y0, int x1, int y1, {required bool wavy}) {
    final phase = random.nextDouble() * 2 * math.pi;
    final amplitude = wavy ? 60 + random.nextInt(120) : 0;
    final positions = <List<int>>[];
    for (var k = 0; k <= pointsPerEdge + 1; k++) {
      final t = k / (pointsPerEdge + 1);
      final offset =
          (amplitude *
                  math.sin(math.pi * t) *
                  math.sin(3 * math.pi * t + phase))
              .round();
      final x = x0 + ((x1 - x0) * t).round() + (y1 == y0 ? 0 : offset);
      final y = y0 + ((y1 - y0) * t).round() + (x1 == x0 ? 0 : offset);
      positions.add([x, y]);
    }
    return [
      positions.first,
      for (var k = 1; k < positions.length; k++)
        [
          positions[k][0] - positions[k - 1][0],
          positions[k][1] - positions[k - 1][1],
        ],
    ];
  }

  int horizontal(int i, int j) => j * columns + i;
  final verticalStart = (rows + 1) * columns;
  int vertical(int i, int j) => verticalStart + j * (columns + 1) + i;

  for (var j = 0; j <= rows; j++) {
    for (var i = 0; i < columns; i++) {
      arcs.add(
        edge(
          i * cell,
          j * cell,
          (i + 1) * cell,
          j * cell,
          wavy: j > 0 && j < rows,
        ),
      );
    }
  }
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i <= columns; i++) {
      arcs.add(
        edge(
          i * cell,
          j * cell,
          i * cell,
          (j + 1) * cell,
          wavy: i > 0 && i < columns,
        ),
      );
    }
  }

  final geometries = [
    for (var j = 0; j < rows; j++)
      for (var i = 0; i < columns; i++)
        {
          'type': 'Polygon',
          'id': 'n_stress_${i}_$j',
          'arcs': [
            [
              horizontal(i, j),
              vertical(i + 1, j),
              ~horizontal(i, j + 1),
              ~vertical(i, j),
            ],
          ],
        },
  ];

  return jsonEncode({
    'type': 'Topology',
    'transform': {
      'scale': [1e-4, 1e-4],
      'translate': [0, 40],
    },
    'arcs': arcs,
    'objects': {
      'cells': {'type': 'GeometryCollection', 'geometries': geometries},
    },
  });
}
