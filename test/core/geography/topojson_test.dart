import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/topojson.dart';

import '../../support/geography_fixture.dart';

/// [ring] as (lon, lat) pairs rounded to a thousandth of a degree, the
/// fixture's quantization step.
List<(double, double)> points(Float64List ring) => [
  for (var i = 0; i < ring.length; i += 2)
    (
      (ring[i] * 1000).roundToDouble() / 1000,
      (ring[i + 1] * 1000).roundToDouble() / 1000,
    ),
];

void main() {
  final topology = Topology.parse(fixtureTopoJson);

  TopoFeature feature(String object, String id) =>
      topology.objects[object]!.singleWhere((f) => f.id == id);

  group('TopoJSON decoding of the fixture', () {
    test('reads every object and flattens collections', () {
      expect(topology.objects.keys, [
        'country',
        'regions',
        'areas',
        'rivers',
        'places',
      ]);
      expect(topology.objects['areas']!.map((f) => f.id), [
        'n_fx_north',
        'n_fx_south',
        'n_fx_isles',
        'n_fx_tiny',
        'n_fx_east',
      ], reason: 'the geometry of null type has no shape and is left out');
      expect(feature('areas', 'n_fx_north').properties, {
        'name': 'North Hills',
      });
    });

    test('undoes the delta encoding and the quantization of arcs', () {
      expect(topology.arcs, hasLength(11));
      // Arc 1: (2000, 1500) then deltas (0, 1000), (-1000, 0), (0, -1000).
      expect(points(topology.arcs[1]), [
        (4.0, 47.5),
        (4.0, 48.5),
        (3.0, 48.5),
        (3.0, 47.5),
      ]);
      expect(topology.arcs[1][0], closeTo(4.0, 1e-12));
      expect(topology.arcs[1][3], closeTo(48.5, 1e-12));
    });

    test('stitches rings from arcs, reversing negative references', () {
      final south = feature('areas', 'n_fx_south').geometry as TopoPolygons;
      expect(south.polygons, [
        [
          [3, -1],
        ],
      ]);
      // Arc 3 forwards, then arc 0 backwards (~0 is -1): their shared
      // point appears once, and the ring closes.
      expect(points(topology.polygonsOf(south).single.single), [
        (3.0, 47.5),
        (3.0, 46.5),
        (4.0, 46.5),
        (4.0, 47.5),
        (3.0, 47.5),
      ]);
    });

    test('keeps a polygon hole as the second ring', () {
      final north = feature('areas', 'n_fx_north').geometry as TopoPolygons;
      final rings = topology.polygonsOf(north).single;
      expect(rings, hasLength(2));
      expect(points(rings[0]), [
        (3.0, 47.5),
        (4.0, 47.5),
        (4.0, 48.5),
        (3.0, 48.5),
        (3.0, 47.5),
      ]);
      expect(points(rings[1]), [
        (3.4, 47.9),
        (3.4, 48.1),
        (3.6, 48.1),
        (3.6, 47.9),
        (3.4, 47.9),
      ]);
    });

    test('keeps each part of a multipolygon', () {
      final isles = feature('areas', 'n_fx_isles').geometry as TopoPolygons;
      final polygons = topology.polygonsOf(isles);
      expect(polygons, hasLength(2));
      expect(points(polygons[0].single).first, (4.6, 48.0));
      expect(points(polygons[1].single).first, (4.6, 46.8));
    });

    test('decodes lines and quantized points', () {
      final river = feature('rivers', 'n_fx_river').geometry as TopoLines;
      expect(points(topology.linesOf(river).single), [
        (2.5, 48.7),
        (2.8, 48.0),
        (2.7, 47.0),
        (2.9, 46.3),
      ]);
      // A point is quantized but not delta-encoded.
      final village = feature('places', 'n_fx_village').geometry as TopoPoints;
      expect(points(village.coordinates), [(5.2, 46.6)]);
    });

    test('shares a border between neighbours: one arc, two directions', () {
      final north = feature('areas', 'n_fx_north').geometry as TopoPolygons;
      final south = feature('areas', 'n_fx_south').geometry as TopoPolygons;
      expect(north.polygons.single.first, contains(0));
      expect(south.polygons.single.first, contains(~0));
    });
  });

  group('TopoJSON without quantization', () {
    test('reads absolute positions and numeric IDs', () {
      final topology = Topology.fromJson({
        'type': 'Topology',
        'arcs': [
          [
            [0.5, 45.25],
            [1.5, 45.25],
            [1.5, 46.75],
            [0.5, 45.25],
          ],
        ],
        'objects': {
          'one': {
            'type': 'Polygon',
            'id': 1234,
            'arcs': [
              [0],
            ],
          },
          'decimal': {
            'type': 'Point',
            'id': 1.5,
            'coordinates': [2.5, 3.5],
          },
        },
      });
      final one = topology.objects['one']!.single;
      expect(one.id, '1234');
      expect(one.properties, isEmpty);
      expect(topology.polygonsOf(one.geometry as TopoPolygons).single.single, [
        0.5,
        45.25,
        1.5,
        45.25,
        1.5,
        46.75,
        0.5,
        45.25,
      ]);
      final decimal = topology.objects['decimal']!.single;
      expect(decimal.id, '1.5');
      expect((decimal.geometry as TopoPoints).coordinates, [2.5, 3.5]);
    });
  });

  group('TopoJSON errors', () {
    Map<String, Object?> topology({
      List<Object?>? arcs,
      Map<String, Object?>? objects,
    }) => {
      'type': 'Topology',
      'arcs':
          arcs ??
          [
            [
              [0, 0],
              [1, 0],
              [1, 1],
              [0, 0],
            ],
          ],
      'objects':
          objects ??
          {
            'a': {
              'type': 'Polygon',
              'arcs': [
                [0],
              ],
            },
          },
    };

    test('rejects what is not a topology', () {
      expect(
        () => Topology.parse('{"type": "FeatureCollection"}'),
        throwsFormatException,
      );
      expect(() => Topology.parse('[1, 2]'), throwsFormatException);
      expect(() => Topology.parse('not json'), throwsFormatException);
      expect(
        () => Topology.fromJson({'type': 'Topology'}),
        throwsFormatException,
      );
    });

    test('accepts the minimal valid topology', () {
      expect(Topology.fromJson(topology()).objects['a'], hasLength(1));
    });

    test('rejects a reference to a missing arc', () {
      expect(
        () => Topology.fromJson(
          topology(
            objects: {
              'a': {
                'type': 'Polygon',
                'arcs': [
                  [1],
                ],
              },
            },
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => Topology.fromJson(
          topology(
            objects: {
              'a': {
                'type': 'LineString',
                'arcs': [~3],
              },
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects rings that do not close', () {
      expect(
        () => Topology.fromJson(
          topology(
            arcs: [
              [
                [0, 0],
                [1, 0],
                [1, 1],
                [0, 1],
              ],
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown geometry types and malformed arcs', () {
      expect(
        () => Topology.fromJson(
          topology(
            objects: {
              'a': {'type': 'Circle', 'arcs': <Object?>[]},
            },
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => Topology.fromJson(
          topology(
            arcs: [
              [
                [0, 0],
              ],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => Topology.fromJson(
          topology(
            arcs: [
              [
                [0, 0],
                ['x', 1],
              ],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => Topology.fromJson(
          topology(
            objects: {
              'a': {'type': 'MultiPolygon', 'arcs': <Object?>[]},
            },
          ),
        ),
        throwsFormatException,
      );
    });
  });
}
