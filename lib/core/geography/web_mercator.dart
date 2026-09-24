import 'dart:math' as math;

import 'coordinates.dart';

/// The Web Mercator projection (EPSG:3857) of geography §8, scaled to world
/// coordinates: the world is the unit square, x runs east from the
/// antimeridian and y south from the northern cut-off latitude.
///
/// At zoom z a map is 256 · 2^z logical pixels wide, as in web maps, so the
/// zoom ranges of `map_layers` (geography §3) apply unchanged.
abstract final class WebMercator {
  /// The latitude at which the projected world is square. Latitudes beyond
  /// it are clamped; no wine region comes near it.
  static const maxLatitude = 85.05112877980659;

  /// The width of the world at zoom 0, in logical pixels.
  static const tileSize = 256.0;

  static WorldPoint project(LonLat p) => WorldPoint(x(p.lon), y(p.lat));

  static LonLat unproject(WorldPoint p) => LonLat(lon(p.x), lat(p.y));

  static double x(double lon) => (lon + 180) / 360;

  static double y(double lat) {
    final sin = math.sin(lat.clamp(-maxLatitude, maxLatitude) * math.pi / 180);
    return 0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi);
  }

  static double lon(double x) => x * 360 - 180;

  static double lat(double y) =>
      (2 * math.atan(math.exp((0.5 - y) * 2 * math.pi)) - math.pi / 2) *
      180 /
      math.pi;

  /// The world rectangle covered by [bounds].
  static WorldRect projectBounds(GeoBounds bounds) => WorldRect(
    x(bounds.minLon),
    y(bounds.maxLat),
    x(bounds.maxLon),
    y(bounds.minLat),
  );

  /// The geographic box covered by [rect].
  static GeoBounds unprojectRect(WorldRect rect) => GeoBounds(
    minLon: lon(rect.left),
    minLat: lat(rect.bottom),
    maxLon: lon(rect.right),
    maxLat: lat(rect.top),
  );

  /// The zoom level at which one world unit spans [pixelsPerWorld] logical
  /// pixels.
  static double zoomOf(double pixelsPerWorld) =>
      math.log(pixelsPerWorld / tileSize) / math.ln2;

  /// Logical pixels per world unit at [zoom].
  static double scaleOf(double zoom) => tileSize * math.pow(2, zoom);
}
