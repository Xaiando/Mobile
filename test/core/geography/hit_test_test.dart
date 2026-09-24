import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/map_view.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';

import '../../support/geography_fixture.dart';

void main() {
  final fixture = FixtureLayers();
  const tester = MapHitTester();
  // The region fitted to an 800 × 600 view: 1° of longitude is about 169
  // logical pixels, so the 12-pixel near distance is about 0.07°.
  final scale = MapView.fit(
    WebMercator.projectBounds(fixture.regionFrame),
    width: 800,
    height: 600,
  ).scale;

  final candidates = [
    for (final layer in [fixture.areas, fixture.places])
      for (final shape in layer.shapes)
        if (fixtureCandidates.contains(shape.key)) shape,
  ];

  /// The world point [dx], [dy] logical pixels from ([lon], [lat]).
  WorldPoint at(double lon, double lat, {double dx = 0, double dy = 0}) {
    final p = WebMercator.project(LonLat(lon, lat));
    return WorldPoint(p.x + dx / scale, p.y + dy / scale);
  }

  List<(String, HitKind)> hitsAt(
    WorldPoint point, {
    Iterable<GeoShape>? among,
    bool markersShown = true,
  }) => [
    for (final hit in tester.hitTest(
      among ?? candidates,
      point,
      scale,
      drawnAsMarker: markersShown ? null : (_) => false,
    ))
      (hit.key, hit.kind),
  ];

  test('the fixture view has the scale these tests assume', () {
    expect(scale / 360, closeTo(168.6, 0.5));
  });

  group('inside, near and outside', () {
    test('a tap inside a polygon hits it', () {
      expect(hitsAt(at(3.2, 48.3)), [('n_fx_north', HitKind.inside)]);
      expect(hitsAt(at(3.5, 47)), [('n_fx_south', HitKind.inside)]);
    });

    test('a tap within 12 pixels of an outline is near it', () {
      final hits = tester.hitTest(candidates, at(4, 48, dx: 8), scale);
      expect(hits.single.key, 'n_fx_north');
      expect(hits.single.kind, HitKind.near);
      expect(hits.single.distance, closeTo(8, 1e-6));
      expect(hitsAt(at(4, 48, dx: 11.9)), [('n_fx_north', HitKind.near)]);
    });

    test('a tap farther than 12 pixels from every candidate is outside', () {
      expect(hitsAt(at(4, 48, dx: 12.1)), isEmpty);
      expect(hitsAt(at(4.3, 48)), isEmpty);
    });

    test('a hole is outside its polygon, and its edge is an outline', () {
      // The hole is 0.2° wide, so its centre is 17 pixels from its edge.
      expect(hitsAt(at(3.5, 48)), isEmpty);
      expect(hitsAt(at(3.43, 48)), [('n_fx_north', HitKind.near)]);
    });

    test('each part of a multipolygon counts', () {
      expect(hitsAt(at(4.8, 48.2)), [('n_fx_isles', HitKind.inside)]);
      expect(hitsAt(at(4.8, 47)), [('n_fx_isles', HitKind.inside)]);
      expect(hitsAt(at(4.8, 47.6)), isEmpty, reason: 'between the isles');
      expect(hitsAt(at(4.8, 47.2, dy: -6)), [('n_fx_isles', HitKind.near)]);
    });
  });

  group('several candidates', () {
    test('the one hit exactly wins over a near one', () {
      // Three pixels north of the border North shares with South.
      expect(hitsAt(at(3.5, 47.5, dy: -3)), [
        ('n_fx_north', HitKind.inside),
        ('n_fx_south', HitKind.near),
      ]);
      expect(hitsAt(at(3.5, 47.5, dy: 3)), [
        ('n_fx_south', HitKind.inside),
        ('n_fx_north', HitKind.near),
      ]);
    });

    test('failing that, the one whose outline is nearest', () {
      // Zoomed out, North and the northern isle are 20 pixels apart.
      final far = 20 / (0.6 / 360);
      final hits = tester.hitTest(
        candidates,
        WorldPoint(WebMercator.x(4) + 9 / far, WebMercator.y(48.2)),
        far,
      );
      expect(hits.map((h) => (h.key, h.kind)), [
        ('n_fx_north', HitKind.near),
        ('n_fx_isles', HitKind.near),
      ]);
      expect(hits[0].distance, closeTo(9, 1e-6));
      expect(hits[1].distance, closeTo(11, 1e-6));
      final other = tester.hitTest(
        candidates,
        WorldPoint(WebMercator.x(4) + 11 / far, WebMercator.y(48.2)),
        far,
      );
      expect(other.map((h) => h.key), ['n_fx_isles', 'n_fx_north']);
    });

    test('of overlapping candidates hit exactly, the smallest wins', () {
      final nested = [
        fixture.regions.shapes.single,
        fixture.areas.shapeFor('n_fx_north')!,
      ];
      expect(hitsAt(at(3.2, 48.3), among: nested), [
        ('n_fx_north', HitKind.inside),
        ('n_fx_region', HitKind.inside),
      ]);
    });

    test('features without a key are never hit', () {
      final keyless = GeoLayer.fromTopology(
        Topology.fromJson({
          'type': 'Topology',
          'arcs': [
            [
              [3, 47.5],
              [4, 47.5],
              [4, 48.5],
              [3, 47.5],
            ],
          ],
          'objects': {
            'a': {
              'type': 'Polygon',
              'arcs': [
                [0],
              ],
            },
          },
        }),
        id: 'x',
      );
      expect(hitsAt(at(3.8, 47.7), among: keyless.shapes), isEmpty);
    });
  });

  group('markers', () {
    final tiny = fixture.areas.shapeFor('n_fx_tiny')!;
    final village = fixture.places.shapes.single;

    WorldPoint beside(GeoShape shape, double pixels) =>
        WorldPoint(shape.labelPoint.x + pixels / scale, shape.labelPoint.y);

    test('the rule: points always, areas under 24 pixels', () {
      const rule = MarkerRule();
      expect(rule.appliesTo(village, 1e9), isTrue);
      expect(rule.appliesTo(tiny, scale), isTrue);
      expect(
        rule.appliesTo(fixture.areas.shapeFor('n_fx_north')!, scale),
        isFalse,
      );
      // Tiny Clos spans 0.01° of latitude at 47.5° N, which Web Mercator
      // draws 24 pixels tall at about 1,620 pixels per degree of longitude.
      expect(rule.appliesTo(tiny, 1600 * 360), isTrue);
      expect(rule.appliesTo(tiny, 1650 * 360), isFalse);
    });

    test('a long, thin feature keeps its shape', () {
      final strip = GeoLayer.fromTopology(
        Topology.fromJson({
          'type': 'Topology',
          'arcs': [
            [
              [3, 47.5],
              [4, 47.5],
              [4, 47.505],
              [3, 47.505],
              [3, 47.5],
            ],
          ],
          'objects': {
            'a': {
              'type': 'Polygon',
              'id': 'strip',
              'arcs': [
                [0],
              ],
            },
          },
        }),
        id: 'x',
      ).shapes.single;
      expect(const MarkerRule().appliesTo(strip, scale), isFalse);
    });

    test('a tap on a marker hits it; within 12 pixels of it, near it', () {
      expect(hitsAt(beside(tiny, 4)), [('n_fx_tiny', HitKind.inside)]);
      final near = tester.hitTest(candidates, beside(tiny, 18), scale);
      expect(near.single.key, 'n_fx_tiny');
      expect(near.single.kind, HitKind.near);
      expect(near.single.distance, closeTo(10, 1e-6));
      expect(hitsAt(beside(tiny, 21)), isEmpty);
      expect(hitsAt(beside(village, 5)), [('n_fx_village', HitKind.inside)]);
    });

    test('without markers, a small feature is only as large as its shape', () {
      expect(hitsAt(beside(tiny, 4), markersShown: false), [
        ('n_fx_tiny', HitKind.near),
      ]);
      expect(hitsAt(beside(tiny, 18), markersShown: false), isEmpty);
      expect(hitsAt(beside(village, 5), markersShown: false), [
        ('n_fx_village', HitKind.near),
      ]);
      expect(hitsAt(beside(village, 13), markersShown: false), isEmpty);
    });

    test('a marker drawn over a neighbour wins: it is smaller', () {
      // At zoom 3 the tiny square's marker covers 8 pixels of the country.
      final zoom3 = WebMercator.scaleOf(3);
      final hits = tester.hitTest(
        [fixture.country.shapes.single, tiny],
        WorldPoint(tiny.labelPoint.x + 3 / zoom3, tiny.labelPoint.y),
        zoom3,
      );
      expect(hits.map((h) => h.key), ['n_fx_tiny', 'n_fx_country']);
    });
  });

  test('lines are only ever near', () {
    final river = fixture.rivers.shapes.single;
    final onIt = tester.hitTest([river], river.labelPoint, scale);
    expect(onIt.single.kind, HitKind.near);
    expect(onIt.single.distance, closeTo(0, 1e-6));
    expect(tester.hitTest([river], at(2.8, 48, dx: 20), scale), isEmpty);
  });
}
