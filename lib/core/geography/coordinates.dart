import 'dart:math' as math;

/// A position on the globe in degrees (WGS 84), longitude first like the
/// `label_lon` and `label_lat` columns of `node_geometries` (geography §3).
final class LonLat {
  const LonLat(this.lon, this.lat);

  final double lon;
  final double lat;

  @override
  bool operator ==(Object other) =>
      other is LonLat && other.lon == lon && other.lat == lat;

  @override
  int get hashCode => Object.hash(lon, lat);

  @override
  String toString() => 'LonLat($lon, $lat)';
}

/// A bounding box in degrees, as `node_geometries` stores it (geography §3).
///
/// Frames never cross the antimeridian (geography §10): [minLon] is never
/// east of [maxLon], and such a box is rejected.
final class GeoBounds {
  GeoBounds({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  }) {
    if (!(minLon <= maxLon && minLat <= maxLat)) {
      throw ArgumentError(
        'Bounds must be west to east and south to north, without crossing '
        'the antimeridian: $this',
      );
    }
  }

  /// The smallest box around [points].
  factory GeoBounds.around(Iterable<LonLat> points) {
    var minLon = double.infinity, minLat = double.infinity;
    var maxLon = -double.infinity, maxLat = -double.infinity;
    for (final p in points) {
      minLon = math.min(minLon, p.lon);
      minLat = math.min(minLat, p.lat);
      maxLon = math.max(maxLon, p.lon);
      maxLat = math.max(maxLat, p.lat);
    }
    if (minLon > maxLon) throw ArgumentError('No points to bound.');
    return GeoBounds(
      minLon: minLon,
      minLat: minLat,
      maxLon: maxLon,
      maxLat: maxLat,
    );
  }

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  double get width => maxLon - minLon;
  double get height => maxLat - minLat;

  LonLat get center => LonLat((minLon + maxLon) / 2, (minLat + maxLat) / 2);

  bool contains(LonLat p) =>
      p.lon >= minLon && p.lon <= maxLon && p.lat >= minLat && p.lat <= maxLat;

  /// This box grown by [fraction] of its width and height on each side. A
  /// question's frame is its parent's box plus such a margin (geography §5).
  GeoBounds expand(double fraction) {
    final dx = width * fraction, dy = height * fraction;
    return GeoBounds(
      minLon: minLon - dx,
      minLat: math.max(-90, minLat - dy),
      maxLon: maxLon + dx,
      maxLat: math.min(90, maxLat + dy),
    );
  }

  GeoBounds union(GeoBounds other) => GeoBounds(
    minLon: math.min(minLon, other.minLon),
    minLat: math.min(minLat, other.minLat),
    maxLon: math.max(maxLon, other.maxLon),
    maxLat: math.max(maxLat, other.maxLat),
  );

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.minLon == minLon &&
      other.minLat == minLat &&
      other.maxLon == maxLon &&
      other.maxLat == maxLat;

  @override
  int get hashCode => Object.hash(minLon, minLat, maxLon, maxLat);

  @override
  String toString() => 'GeoBounds($minLon, $minLat, $maxLon, $maxLat)';
}

/// A point in world coordinates: Web Mercator scaled to the unit square, with
/// y growing southwards like screen coordinates (see `WebMercator`).
final class WorldPoint {
  const WorldPoint(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(WorldPoint other) {
    final dx = x - other.x, dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is WorldPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'WorldPoint($x, $y)';
}

/// An axis-aligned rectangle in world coordinates.
final class WorldRect {
  const WorldRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  WorldPoint get center => WorldPoint((left + right) / 2, (top + bottom) / 2);

  bool contains(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  /// Whether [other] lies inside this rectangle, within [tolerance].
  bool containsRect(WorldRect other, {double tolerance = 0}) =>
      other.left >= left - tolerance &&
      other.top >= top - tolerance &&
      other.right <= right + tolerance &&
      other.bottom <= bottom + tolerance;

  bool overlaps(WorldRect other) =>
      other.left <= right &&
      other.right >= left &&
      other.top <= bottom &&
      other.bottom >= top;

  WorldRect inflate(double delta) =>
      WorldRect(left - delta, top - delta, right + delta, bottom + delta);

  WorldRect union(WorldRect other) => WorldRect(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  @override
  bool operator ==(Object other) =>
      other is WorldRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'WorldRect($left, $top, $right, $bottom)';
}
