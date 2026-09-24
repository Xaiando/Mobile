import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/map_view.dart';
import 'package:sommelier/core/geography/web_mercator.dart';

void main() {
  group('Web Mercator', () {
    test('places the origin, the antimeridian and the equator', () {
      expect(
        WebMercator.project(const LonLat(0, 0)),
        const WorldPoint(0.5, 0.5),
      );
      expect(WebMercator.x(-180), 0);
      expect(WebMercator.x(180), 1);
      expect(WebMercator.y(WebMercator.maxLatitude), closeTo(0, 1e-12));
      expect(WebMercator.y(-WebMercator.maxLatitude), closeTo(1, 1e-12));
    });

    test('north is up: y grows southwards', () {
      expect(WebMercator.y(48), lessThan(WebMercator.y(47)));
      expect(WebMercator.y(-33), greaterThan(0.5));
    });

    test('round-trips positions to within a micrometre', () {
      // 1e-11 degrees is about a micrometre on the ground.
      for (var lat = -85.0; lat <= 85; lat += 2.5) {
        for (var lon = -180.0; lon <= 180; lon += 7.5) {
          final back = WebMercator.unproject(
            WebMercator.project(LonLat(lon, lat)),
          );
          expect(back.lon, closeTo(lon, 1e-11), reason: '$lon, $lat');
          expect(back.lat, closeTo(lat, 1e-11), reason: '$lon, $lat');
        }
      }
    });

    test('round-trips wine-region coordinates exactly enough to hit-test', () {
      // Chablis, Ahr, Marlborough, Mendoza: north, south, east and west.
      for (final p in const [
        LonLat(3.8, 47.8),
        LonLat(7.05, 50.53),
        LonLat(173.9, -41.5),
        LonLat(-68.84, -32.89),
      ]) {
        final world = WebMercator.project(p);
        expect(
          WebMercator.project(WebMercator.unproject(world)).x,
          closeTo(world.x, 1e-15),
        );
        expect(
          WebMercator.project(WebMercator.unproject(world)).y,
          closeTo(world.y, 1e-15),
        );
      }
    });

    test('clamps latitudes beyond the cut-off', () {
      expect(WebMercator.y(89), WebMercator.y(WebMercator.maxLatitude));
      expect(WebMercator.y(-90), WebMercator.y(-WebMercator.maxLatitude));
    });

    test('round-trips bounds', () {
      final bounds = GeoBounds(
        minLon: 2.2,
        minLat: 46.2,
        maxLon: 5.8,
        maxLat: 48.8,
      );
      final back = WebMercator.unprojectRect(WebMercator.projectBounds(bounds));
      expect(back.minLon, closeTo(2.2, 1e-11));
      expect(back.minLat, closeTo(46.2, 1e-11));
      expect(back.maxLon, closeTo(5.8, 1e-11));
      expect(back.maxLat, closeTo(48.8, 1e-11));
    });

    test('zoom 0 shows the world in one 256-pixel tile', () {
      expect(WebMercator.scaleOf(0), 256);
      expect(WebMercator.scaleOf(3), 2048);
      expect(WebMercator.zoomOf(2048), closeTo(3, 1e-12));
      expect(
        WebMercator.zoomOf(WebMercator.scaleOf(7.25)),
        closeTo(7.25, 1e-12),
      );
    });

    test('screen and world coordinates round-trip through a view', () {
      final view = MapView.fit(
        WebMercator.projectBounds(
          GeoBounds(minLon: 3, minLat: 47, maxLon: 4, maxLat: 48),
        ),
        width: 400,
        height: 300,
      );
      final p = WebMercator.project(const LonLat(3.5, 47.25));
      final back = view.toWorld(view.screenX(p.x), view.screenY(p.y));
      expect(back.x, closeTo(p.x, 1e-15));
      expect(back.y, closeTo(p.y, 1e-15));
    });
  });

  group('GeoBounds', () {
    test('rejects boxes that cross the antimeridian or are inverted', () {
      expect(
        () => GeoBounds(minLon: 179, minLat: -45, maxLon: -179, maxLat: -40),
        throwsArgumentError,
      );
      expect(
        () => GeoBounds(minLon: 3, minLat: 48, maxLon: 4, maxLat: 47),
        throwsArgumentError,
      );
    });

    test('frames near the antimeridian stay on one side of it', () {
      // New Zealand's wine regions lie west of 180°.
      final frame = GeoBounds(
        minLon: 166,
        minLat: -47,
        maxLon: 178.6,
        maxLat: -34,
      );
      final rect = WebMercator.projectBounds(frame);
      expect(rect.left, lessThan(rect.right));
      expect(rect.right, lessThanOrEqualTo(1));
    });

    test('grows by a margin, a frame around its parent', () {
      final box = GeoBounds(minLon: 3, minLat: 47, maxLon: 4, maxLat: 49);
      final frame = box.expand(0.1);
      expect(frame.minLon, closeTo(2.9, 1e-12));
      expect(frame.minLat, closeTo(46.8, 1e-12));
      expect(frame.maxLon, closeTo(4.1, 1e-12));
      expect(frame.maxLat, closeTo(49.2, 1e-12));
      expect(frame.contains(box.center), isTrue);
      expect(
        GeoBounds(
          minLon: 0,
          minLat: 80,
          maxLon: 1,
          maxLat: 89,
        ).expand(0.5).maxLat,
        90,
      );
    });

    test('bounds points and unions', () {
      final box = GeoBounds.around(const [
        LonLat(4, 47),
        LonLat(3, 49),
        LonLat(3.5, 48),
      ]);
      expect(box, GeoBounds(minLon: 3, minLat: 47, maxLon: 4, maxLat: 49));
      expect(
        box.union(GeoBounds(minLon: 5, minLat: 46, maxLon: 6, maxLat: 47)),
        GeoBounds(minLon: 3, minLat: 46, maxLon: 6, maxLat: 49),
      );
    });
  });
}
