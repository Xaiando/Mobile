import 'dart:math' as math;

import 'coordinates.dart';
import 'web_mercator.dart';

/// What a map shows: world coordinates scaled by [scale] logical pixels per
/// world unit, then shifted by ([dx], [dy]) logical pixels.
final class MapView {
  const MapView({required this.scale, this.dx = 0, this.dy = 0});

  /// The view that shows [rect] whole and centred in a [width] × [height]
  /// viewport, [padding] logical pixels inside its edges: frame fitting
  /// (geography §5).
  factory MapView.fit(
    WorldRect rect, {
    required double width,
    required double height,
    double padding = 0,
  }) {
    final innerWidth = math.max(1.0, width - 2 * padding);
    final innerHeight = math.max(1.0, height - 2 * padding);
    final scale = math.min(
      innerWidth / math.max(rect.width, _minimumExtent),
      innerHeight / math.max(rect.height, _minimumExtent),
    );
    final centre = rect.center;
    return MapView(
      scale: scale,
      dx: width / 2 - centre.x * scale,
      dy: height / 2 - centre.y * scale,
    );
  }

  /// Fitting a point or a line would divide by zero. About 4 cm on the
  /// ground; any real frame is larger.
  static const _minimumExtent = 1e-9;

  final double scale;
  final double dx;
  final double dy;

  /// The Web Mercator zoom level of this view.
  double get zoom => WebMercator.zoomOf(scale);

  double screenX(double worldX) => worldX * scale + dx;
  double screenY(double worldY) => worldY * scale + dy;

  WorldPoint toWorld(double x, double y) =>
      WorldPoint((x - dx) / scale, (y - dy) / scale);

  /// The world rectangle a [width] × [height] viewport shows.
  WorldRect visibleRect(double width, double height) => WorldRect(
    -dx / scale,
    -dy / scale,
    (width - dx) / scale,
    (height - dy) / scale,
  );

  /// This view kept within [limits] in a [width] × [height] viewport.
  ///
  /// The scale is clamped about the viewport's centre. Then the view moves
  /// the least needed to keep the visible rectangle inside the limit bounds;
  /// along an axis where the viewport is larger than the bounds, the bounds
  /// are centred.
  MapView clamp(
    MapViewLimits limits, {
    required double width,
    required double height,
  }) {
    final centre = toWorld(width / 2, height / 2);
    final s = scale.clamp(limits.minScale, limits.maxScale);
    final bounds = limits.bounds;
    double origin(double centre, double extent, double min, double max) {
      final visible = extent / s;
      if (visible >= max - min) return (min + max) / 2 - visible / 2;
      return (centre - visible / 2).clamp(min, max - visible);
    }

    final left = origin(centre.x, width, bounds.left, bounds.right);
    final top = origin(centre.y, height, bounds.top, bounds.bottom);
    return MapView(scale: s, dx: -left * s, dy: -top * s);
  }

  @override
  bool operator ==(Object other) =>
      other is MapView &&
      other.scale == scale &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(scale, dx, dy);

  @override
  String toString() => 'MapView(scale: $scale, dx: $dx, dy: $dy)';
}

/// How far a view may pan and zoom: the world rectangle it must stay inside,
/// and its scale range in logical pixels per world unit.
final class MapViewLimits {
  MapViewLimits({
    required this.bounds,
    required this.minScale,
    required this.maxScale,
  }) {
    if (!(minScale > 0 && minScale <= maxScale)) {
      throw ArgumentError('Invalid scale range: $minScale to $maxScale');
    }
  }

  final WorldRect bounds;
  final double minScale;
  final double maxScale;

  /// Whether [view] respects these limits in a [width] × [height] viewport,
  /// allowing [tolerance] for rounding.
  bool allows(
    MapView view, {
    required double width,
    required double height,
    double tolerance = 1e-9,
  }) {
    if (view.scale < minScale * (1 - tolerance) ||
        view.scale > maxScale * (1 + tolerance)) {
      return false;
    }
    final visible = view.visibleRect(width, height);
    final slack = tolerance * math.max(bounds.width, bounds.height);
    bool axis(double lo, double hi, double min, double max) =>
        hi - lo >= max - min
        ? (lo <= min + slack && hi >= max - slack)
        : (lo >= min - slack && hi <= max + slack);
    return axis(visible.left, visible.right, bounds.left, bounds.right) &&
        axis(visible.top, visible.bottom, bounds.top, bounds.bottom);
  }
}
