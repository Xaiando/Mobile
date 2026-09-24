import 'dart:math' as math;
import 'dart:typed_data';

import 'coordinates.dart';

// Planar geometry on flat coordinate lists, `[x0, y0, x1, y1, …]`, in world
// coordinates. A ring is closed: its last point repeats its first. A polygon
// is a list of rings, the exterior first and its holes after it.

/// The signed area of [ring] (the shoelace formula). It is positive when the
/// ring turns clockwise on screen, where y grows downwards.
double ringArea(Float64List ring) {
  var sum = 0.0;
  for (var i = 0; i + 3 < ring.length; i += 2) {
    sum += ring[i] * ring[i + 3] - ring[i + 2] * ring[i + 1];
  }
  return sum / 2;
}

/// The area of [polygon]: its exterior less its holes.
double polygonArea(List<Float64List> polygon) {
  var area = ringArea(polygon.first).abs();
  for (var i = 1; i < polygon.length; i++) {
    area -= ringArea(polygon[i]).abs();
  }
  return math.max(0, area);
}

/// The centroid of the area [ring] encloses, or null if it encloses none.
WorldPoint? ringCentroid(Float64List ring) {
  var area = 0.0, cx = 0.0, cy = 0.0;
  for (var i = 0; i + 3 < ring.length; i += 2) {
    final cross = ring[i] * ring[i + 3] - ring[i + 2] * ring[i + 1];
    cx += (ring[i] + ring[i + 2]) * cross;
    cy += (ring[i + 1] + ring[i + 3]) * cross;
    area += cross;
  }
  if (area == 0) return null;
  return WorldPoint(cx / (3 * area), cy / (3 * area));
}

/// Whether ([x], [y]) lies inside [ring], by the even-odd rule: a ray from
/// the point crosses the ring an odd number of times.
bool ringContains(Float64List ring, double x, double y) {
  var inside = false;
  final n = ring.length;
  for (var i = 0, j = n - 2; i < n; j = i, i += 2) {
    final xi = ring[i], yi = ring[i + 1];
    final xj = ring[j], yj = ring[j + 1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// Whether ([x], [y]) lies inside [polygon]: inside its exterior and outside
/// every hole.
bool polygonContains(List<Float64List> polygon, double x, double y) {
  if (!ringContains(polygon.first, x, y)) return false;
  for (var i = 1; i < polygon.length; i++) {
    if (ringContains(polygon[i], x, y)) return false;
  }
  return true;
}

/// Whether ([x], [y]) lies inside any polygon of a multipolygon.
bool polygonsContain(List<List<Float64List>> polygons, double x, double y) {
  for (final polygon in polygons) {
    if (polygonContains(polygon, x, y)) return true;
  }
  return false;
}

/// The squared distance from ([px], [py]) to the segment from ([ax], [ay])
/// to ([bx], [by]).
double segmentDistanceSquared(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  var t = 0.0;
  if (lengthSquared > 0) {
    t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
  }
  final ex = ax + t * dx - px, ey = ay + t * dy - py;
  return ex * ex + ey * ey;
}

/// The distance from ([x], [y]) to the nearest point of [line], a polyline
/// or a closed ring.
double lineDistance(Float64List line, double x, double y) {
  if (line.length == 2) {
    final dx = line[0] - x, dy = line[1] - y;
    return math.sqrt(dx * dx + dy * dy);
  }
  var best = double.infinity;
  for (var i = 0; i + 3 < line.length; i += 2) {
    final d = segmentDistanceSquared(
      x,
      y,
      line[i],
      line[i + 1],
      line[i + 2],
      line[i + 3],
    );
    if (d < best) best = d;
  }
  return math.sqrt(best);
}

/// The distance from ([x], [y]) to the outline of [polygons]: to the nearest
/// exterior or hole boundary of any part.
double outlineDistance(List<List<Float64List>> polygons, double x, double y) {
  var best = double.infinity;
  for (final polygon in polygons) {
    for (final ring in polygon) {
      best = math.min(best, lineDistance(ring, x, y));
    }
  }
  return best;
}

/// The bounding box of the points of [lines].
WorldRect boundsOf(Iterable<Float64List> lines) {
  var left = double.infinity, top = double.infinity;
  var right = -double.infinity, bottom = -double.infinity;
  for (final line in lines) {
    for (var i = 0; i + 1 < line.length; i += 2) {
      final x = line[i], y = line[i + 1];
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return WorldRect(left, top, right, bottom);
}

/// The length of the polyline [line].
double lineLength(Float64List line) {
  var length = 0.0;
  for (var i = 0; i + 3 < line.length; i += 2) {
    final dx = line[i + 2] - line[i], dy = line[i + 3] - line[i + 1];
    length += math.sqrt(dx * dx + dy * dy);
  }
  return length;
}

/// The point halfway along [line], where a river's name is written.
WorldPoint lineMidpoint(Float64List line) {
  var remaining = lineLength(line) / 2;
  for (var i = 0; i + 3 < line.length; i += 2) {
    final dx = line[i + 2] - line[i], dy = line[i + 3] - line[i + 1];
    final segment = math.sqrt(dx * dx + dy * dy);
    if (segment > 0 && remaining <= segment) {
      final t = remaining / segment;
      return WorldPoint(line[i] + t * dx, line[i + 1] + t * dy);
    }
    remaining -= segment;
  }
  return WorldPoint(line[0], line[1]);
}
