import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/planar.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';

import '../../support/geography_fixture.dart';

void main() {
  final fixture = FixtureLayers();

  test('a layer holds the features of one object, by key', () {
    final areas = fixture.areas;
    expect(areas.id, 'ml_fx_areas');
    expect(areas.shapes.map((s) => s.key), [
      'n_fx_north',
      'n_fx_south',
      'n_fx_isles',
      'n_fx_tiny',
      'n_fx_east',
    ]);
    expect(areas.shapeFor('n_fx_south')!.name, 'South Plain');
    expect(areas.shapeFor('n_fx_river'), isNull);
    expect(areas.attribution, 'Fixture area data');
  });

  test('kinds follow the geometry types', () {
    expect(fixture.areas.shapeFor('n_fx_isles')!.kind, GeometryKind.area);
    expect(fixture.rivers.shapes.single.kind, GeometryKind.line);
    expect(fixture.places.shapes.single.kind, GeometryKind.point);
  });

  test('features are in world coordinates, with bounds and areas', () {
    final north = fixture.areas.shapeFor('n_fx_north')!;
    final bounds = north.bounds;
    expect(bounds.left, closeTo(WebMercator.x(3), 1e-15));
    expect(bounds.right, closeTo(WebMercator.x(4), 1e-15));
    expect(bounds.top, closeTo(WebMercator.y(48.5), 1e-15));
    expect(bounds.bottom, closeTo(WebMercator.y(47.5), 1e-15));
    expect(north.polygons.single, hasLength(2), reason: 'exterior and hole');
    final withoutHole = ringArea(north.polygons.single.first).abs();
    expect(north.area, lessThan(withoutHole));
    expect(north.area, greaterThan(withoutHole * 0.95));

    final isles = fixture.areas.shapeFor('n_fx_isles')!;
    expect(isles.polygons, hasLength(2));
    expect(isles.bounds.left, closeTo(WebMercator.x(4.6), 1e-15));
    expect(isles.bounds.top, closeTo(WebMercator.y(48.4), 1e-15));
    expect(isles.bounds.bottom, closeTo(WebMercator.y(46.8), 1e-15));

    expect(fixture.rivers.shapes.single.area, 0);
    final village = fixture.places.shapes.single;
    expect(village.points, hasLength(2));
    expect(village.points[0], closeTo(WebMercator.x(5.2), 1e-15));
    expect(village.points[1], closeTo(WebMercator.y(46.6), 1e-15));
  });

  test('a layer bounds its features', () {
    final bounds = fixture.areas.bounds!;
    expect(bounds.left, closeTo(WebMercator.x(3), 1e-15));
    expect(bounds.right, closeTo(WebMercator.x(5.6), 1e-15));
    expect(bounds.top, closeTo(WebMercator.y(48.6), 1e-15));
    expect(bounds.bottom, closeTo(WebMercator.y(46.5), 1e-15));
  });

  test('contains and distanceTo use the full geometry', () {
    final north = fixture.areas.shapeFor('n_fx_north')!;
    expect(
      north.contains(WebMercator.project(const LonLat(3.2, 48.3))),
      isTrue,
    );
    expect(north.contains(WebMercator.project(const LonLat(3.5, 48))), isFalse);
    final east = WebMercator.project(const LonLat(4.1, 48));
    expect(
      north.distanceTo(east),
      closeTo(WebMercator.x(4.1) - WebMercator.x(4), 1e-15),
    );
    final river = fixture.rivers.shapes.single;
    expect(river.contains(WebMercator.project(const LonLat(2.8, 48))), isFalse);
    expect(
      river.distanceTo(WebMercator.project(const LonLat(2.8, 48))),
      closeTo(0, 1e-15),
    );
  });

  group('label points', () {
    test('lie inside their area and outside its holes', () {
      for (final shape in fixture.areas.shapes) {
        final p = shape.labelPoint;
        expect(shape.contains(p), isTrue, reason: shape.key);
      }
      final north = fixture.areas.shapeFor('n_fx_north')!;
      final hole = WorldRect(
        WebMercator.x(3.4),
        WebMercator.y(48.1),
        WebMercator.x(3.6),
        WebMercator.y(47.9),
      );
      expect(hole.contains(north.labelPoint.x, north.labelPoint.y), isFalse);
    });

    test('of a multipolygon go in its largest part', () {
      final isles = fixture.areas.shapeFor('n_fx_isles')!;
      // The northern isle is slightly larger in Web Mercator.
      final north = isles.polygons.first;
      expect(
        polygonContains(north, isles.labelPoint.x, isles.labelPoint.y),
        isTrue,
      );
    });

    test('of a river is halfway along it, of a point is the point', () {
      final river = fixture.rivers.shapes.single;
      expect(river.distanceTo(river.labelPoint), closeTo(0, 1e-15));
      final village = fixture.places.shapes.single;
      final expected = WebMercator.project(const LonLat(5.2, 46.6));
      expect(village.labelPoint.distanceTo(expected), closeTo(0, 1e-15));
    });

    test('come from the manifest when it gives them', () {
      final layer = GeoLayer.fromTopology(
        fixture.topology,
        id: 'ml_fx_areas',
        object: 'areas',
        labelPoints: const {'n_fx_south': LonLat(3.25, 47.25)},
      );
      expect(
        layer.shapeFor('n_fx_south')!.labelPoint,
        WebMercator.project(const LonLat(3.25, 47.25)),
      );
    });
  });

  test('zoom ranges: minimum inclusive, maximum exclusive', () {
    final layer = GeoLayer.fromTopology(
      fixture.topology,
      id: 'ml_fx_areas',
      object: 'areas',
      minZoom: 6,
      maxZoom: 11,
    );
    expect(layer.isVisibleAt(5.99), isFalse);
    expect(layer.isVisibleAt(6), isTrue);
    expect(layer.isVisibleAt(10.99), isTrue);
    expect(layer.isVisibleAt(11), isFalse);
    expect(fixture.areas.isVisibleAt(22), isTrue);
  });

  test('choosing the object', () {
    expect(
      () => GeoLayer.fromTopology(fixture.topology, id: 'x'),
      throwsArgumentError,
      reason: 'the fixture has several objects',
    );
    expect(
      () => GeoLayer.fromTopology(fixture.topology, id: 'x', object: 'lakes'),
      throwsArgumentError,
    );
    final single = Topology.fromJson({
      'type': 'Topology',
      'arcs': <Object?>[],
      'objects': {
        'places': {
          'type': 'Point',
          'id': 'p',
          'coordinates': [1, 2],
        },
      },
    });
    expect(GeoLayer.fromTopology(single, id: 'x').shapes.single.key, 'p');
  });

  test('rejects two features with one key', () {
    final twice = Topology.fromJson({
      'type': 'Topology',
      'arcs': <Object?>[],
      'objects': {
        'places': {
          'type': 'GeometryCollection',
          'geometries': [
            {
              'type': 'Point',
              'id': 'p',
              'coordinates': [1, 2],
            },
            {
              'type': 'Point',
              'id': 'p',
              'coordinates': [3, 4],
            },
          ],
        },
      },
    });
    expect(() => GeoLayer.fromTopology(twice, id: 'x'), throwsFormatException);
  });
}
