import 'dart:math' as math;

import 'coordinates.dart';
import 'geo_layer.dart';

/// How a tap relates to a candidate (geography §4).
enum HitKind {
  /// The tap is on the feature: inside its polygon, or on its marker.
  inside,

  /// The tap is within the near distance of its outline or marker.
  near,
}

/// A candidate under a tap.
final class MapHit {
  const MapHit({
    required this.shape,
    required this.kind,
    required this.distance,
  });

  final GeoShape shape;

  /// The candidate's feature key.
  String get key => shape.key!;

  final HitKind kind;

  /// Logical pixels from the tap to the candidate's outline or marker edge.
  /// For an inside hit it is how far inside the tap fell; for a marker it
  /// is measured from the marker's edge, 0 at the edge.
  final double distance;

  @override
  String toString() =>
      'MapHit($key, ${kind.name}, ${distance.toStringAsFixed(1)} px)';
}

/// The small-feature rule of geography §5: a feature smaller than
/// [minimumSize] logical pixels at the current zoom is drawn as a marker of
/// [radius] at its label point, so every target stays tappable. Point
/// features are always markers (GEO-9).
final class MarkerRule {
  const MarkerRule({this.minimumSize = 24, this.radius = 8});

  final double minimumSize;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is MarkerRule &&
      other.minimumSize == minimumSize &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(minimumSize, radius);

  /// Whether [shape] is drawn as a marker at [pixelsPerWorld] logical pixels
  /// per world unit. Its size is its longest bounding-box side: a long,
  /// thin feature keeps its shape.
  bool appliesTo(GeoShape shape, double pixelsPerWorld) =>
      shape.kind == GeometryKind.point ||
      math.max(shape.bounds.width, shape.bounds.height) * pixelsPerWorld <
          minimumSize;
}

/// The tap rules of geography §4.
///
/// - A tap is **inside** a candidate if it hits its polygon, or its marker
///   when the candidate is drawn as one ([MarkerRule]).
/// - It is **near** a candidate within [nearDistance] logical pixels of its
///   outline or marker. Lines have no inside, so they are only ever near.
/// - When the tap is inside or near several candidates, the one hit exactly
///   wins, and failing that the one whose outline is nearest. If several are
///   hit exactly, where registers overlap (GEO-16) or a marker sits over a
///   neighbour, the smallest wins: it is the one drawn on top.
///
/// Tests use the full geometry, never a simplified outline, so the result
/// does not depend on the level of detail drawn.
final class MapHitTester {
  const MapHitTester({
    this.nearDistance = 12,
    this.markers = const MarkerRule(),
  });

  /// The near distance, in logical pixels.
  final double nearDistance;

  final MarkerRule markers;

  @override
  bool operator ==(Object other) =>
      other is MapHitTester &&
      other.nearDistance == nearDistance &&
      other.markers == markers;

  @override
  int get hashCode => Object.hash(nearDistance, markers);

  /// The [candidates] under [point], best first; empty when the tap is
  /// outside every candidate.
  ///
  /// [pixelsPerWorld] is the scale of the view. [drawnAsMarker] tells which
  /// candidates the map draws as markers; by default those the [markers]
  /// rule applies to. A mode that hides the candidates draws none, so a
  /// small feature is then only as large as its shape.
  List<MapHit> hitTest(
    Iterable<GeoShape> candidates,
    WorldPoint point,
    double pixelsPerWorld, {
    bool Function(GeoShape shape)? drawnAsMarker,
  }) {
    final hits = <MapHit>[];
    final reach = (nearDistance + markers.radius) / pixelsPerWorld;
    for (final shape in candidates) {
      if (shape.key == null) continue;
      final asMarker =
          drawnAsMarker?.call(shape) ??
          markers.appliesTo(shape, pixelsPerWorld);
      if (!asMarker &&
          !shape.bounds.inflate(reach).contains(point.x, point.y)) {
        continue;
      }
      var inside = shape.contains(point);
      var distance = shape.distanceTo(point) * pixelsPerWorld;
      if (asMarker) {
        final fromMarker =
            shape.labelPoint.distanceTo(point) * pixelsPerWorld -
            markers.radius;
        if (fromMarker <= 0) {
          inside = true;
          distance = -fromMarker;
        } else if (!inside) {
          distance = math.min(distance, fromMarker);
        }
      }
      if (inside) {
        hits.add(
          MapHit(shape: shape, kind: HitKind.inside, distance: distance),
        );
      } else if (distance <= nearDistance) {
        hits.add(MapHit(shape: shape, kind: HitKind.near, distance: distance));
      }
    }
    return hits..sort(_rank);
  }

  /// Inside before near; inside hits by size, then deepest first; near hits
  /// nearest first; ties by key, so the order is the same on every platform.
  static int _rank(MapHit a, MapHit b) {
    if (a.kind != b.kind) return a.kind == HitKind.inside ? -1 : 1;
    final int byGeometry;
    if (a.kind == HitKind.inside) {
      final bySize = a.shape.area.compareTo(b.shape.area);
      byGeometry = bySize != 0 ? bySize : b.distance.compareTo(a.distance);
    } else {
      byGeometry = a.distance.compareTo(b.distance);
    }
    return byGeometry != 0 ? byGeometry : a.key.compareTo(b.key);
  }
}

/// A tap on the map, hit-tested against the candidates (geography §4).
///
/// It carries what `answer_payload` logs: the tapped coordinate, the view
/// and the node hit, so a later miss can say what was tapped.
final class MapTap {
  const MapTap({
    required this.position,
    required this.hits,
    required this.zoom,
    required this.visibleBounds,
  });

  /// Where the tap fell.
  final LonLat position;

  /// Every candidate hit, best first.
  final List<MapHit> hits;

  /// The candidate the tap selects, or null when it is outside every one.
  MapHit? get hit => hits.isEmpty ? null : hits.first;

  /// The Web Mercator zoom of the view.
  final double zoom;

  /// The area shown when the learner tapped.
  final GeoBounds visibleBounds;
}
