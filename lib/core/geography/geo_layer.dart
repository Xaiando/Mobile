import 'dart:math' as math;
import 'dart:typed_data';

import 'coordinates.dart';
import 'label_point.dart';
import 'level_of_detail.dart';
import 'planar.dart';
import 'topojson.dart';
import 'web_mercator.dart';

/// The geometry kinds of `map_layers.geometry_kind` (geography §3).
enum GeometryKind { area, line, point }

/// A map layer in world coordinates: the features of one TopoJSON object,
/// with the zoom range and attribution of its `map_layers` row
/// (geography §3).
final class GeoLayer {
  GeoLayer._({
    required this.id,
    required this.shapes,
    required this.minZoom,
    required this.maxZoom,
    required this.attribution,
  }) : bounds = shapes.isEmpty
           ? null
           : shapes.map((s) => s.bounds).reduce((a, b) => a.union(b)),
       _byKey = {for (final shape in shapes) ?shape.key: shape};

  /// The layer made of [object] in [topology], or of its only object.
  ///
  /// [labelPoints] gives the label point of a feature by key, as
  /// `node_geometries` stores it; other features get their pole of
  /// inaccessibility. Throws a [FormatException] if two features share a
  /// key: `feature_key` is unique within a layer.
  factory GeoLayer.fromTopology(
    Topology topology, {
    required String id,
    String? object,
    double minZoom = 0,
    double maxZoom = double.infinity,
    String? attribution,
    Map<String, LonLat> labelPoints = const {},
  }) {
    final name = object ?? _onlyObject(topology);
    final features = topology.objects[name];
    if (features == null) {
      throw ArgumentError.value(object, 'object', 'not in the topology');
    }
    final arcs = _ArcStore.project(topology, features);
    final keys = <String>{};
    final shapes = <GeoShape>[];
    for (final feature in features) {
      final key = feature.id;
      if (key != null && !keys.add(key)) {
        throw FormatException('Feature key $key appears twice in $name');
      }
      final label = key == null ? null : labelPoints[key];
      shapes.add(
        GeoShape._(
          feature,
          arcs,
          label == null ? null : WebMercator.project(label),
        ),
      );
    }
    return GeoLayer._(
      id: id,
      shapes: List.unmodifiable(shapes),
      minZoom: minZoom,
      maxZoom: maxZoom,
      attribution: attribution,
    );
  }

  /// The `map_layers` ID.
  final String id;

  final List<GeoShape> shapes;

  /// The zoom range in which the layer is drawn, Web Mercator zoom levels
  /// from [minZoom] inclusive to [maxZoom] exclusive (geography §5).
  final double minZoom;
  final double maxZoom;

  /// The attribution its source requires (GEO-14), if any.
  final String? attribution;

  /// The bounding box of every feature, or null for an empty layer.
  final WorldRect? bounds;

  final Map<String, GeoShape> _byKey;

  /// The feature with [key], if this layer has it.
  GeoShape? shapeFor(String key) => _byKey[key];

  bool isVisibleAt(double zoom) => zoom >= minZoom && zoom < maxZoom;

  static String _onlyObject(Topology topology) {
    if (topology.objects.length == 1) return topology.objects.keys.single;
    throw ArgumentError(
      'Name the object to use: ${topology.objects.keys.join(', ')}',
    );
  }
}

/// A feature in world coordinates, ready to draw and hit-test.
final class GeoShape {
  GeoShape._(TopoFeature feature, this._arcs, this._labelPoint)
    : key = feature.id,
      properties = feature.properties,
      kind = switch (feature.geometry) {
        TopoPolygons() => GeometryKind.area,
        TopoLines() => GeometryKind.line,
        TopoPoints() => GeometryKind.point,
      },
      _polygonRefs = switch (feature.geometry) {
        TopoPolygons(:final polygons) => polygons,
        _ => const [],
      },
      _lineRefs = switch (feature.geometry) {
        TopoLines(:final lines) => lines,
        _ => const [],
      },
      points = switch (feature.geometry) {
        TopoPoints(:final coordinates) => _projectPoints(coordinates),
        _ => Float64List(0),
      } {
    polygons = _polygonsFrom(_arcs.arcs);
    lines = _linesFrom(_arcs.arcs);
    bounds = switch (kind) {
      GeometryKind.area => boundsOf([for (final p in polygons) p.first]),
      GeometryKind.line => boundsOf(lines),
      GeometryKind.point => boundsOf([points]),
    };
    area = polygons.fold(0.0, (sum, polygon) => sum + polygonArea(polygon));
  }

  /// The feature key: the `feature_key` of `node_geometries`.
  final String? key;

  final Map<String, Object?> properties;

  /// The `name` property, which context layers such as rivers carry.
  String? get name => switch (properties['name']) {
    final String name => name,
    _ => null,
  };

  final GeometryKind kind;

  /// An area's polygons, each a list of rings with the exterior first, at
  /// full resolution. Empty for lines and points.
  late final List<List<Float64List>> polygons;

  /// A line's parts at full resolution. Empty for areas and points.
  late final List<Float64List> lines;

  /// A point feature's positions, `[x0, y0, …]`. Empty for areas and lines.
  final Float64List points;

  late final WorldRect bounds;

  /// The area in square world units: 0 for lines and points.
  late final double area;

  final _ArcStore _arcs;
  final List<List<List<int>>> _polygonRefs;
  final List<List<int>> _lineRefs;

  /// Where the feature's label and marker go: the point from the manifest
  /// if there is one. Otherwise, for an area, a point inside its largest
  /// polygon: the centroid when it falls inside, which is quick, or else the
  /// pole of inaccessibility. For a line, the middle of its longest part;
  /// for a point feature, its first point.
  WorldPoint get labelPoint => _labelPoint ??= switch (kind) {
    GeometryKind.area => _insidePoint(
      polygons.reduce((a, b) => polygonArea(b) > polygonArea(a) ? b : a),
    ),
    GeometryKind.line => lineMidpoint(
      lines.reduce((a, b) => lineLength(b) > lineLength(a) ? b : a),
    ),
    GeometryKind.point => WorldPoint(points[0], points[1]),
  };
  WorldPoint? _labelPoint;

  static WorldPoint _insidePoint(List<Float64List> polygon) {
    final centroid = ringCentroid(polygon.first);
    if (centroid != null && polygonContains(polygon, centroid.x, centroid.y)) {
      return centroid;
    }
    return poleOfInaccessibility(polygon);
  }

  /// Whether [p] lies inside an area feature. Lines and points contain
  /// nothing.
  bool contains(WorldPoint p) => polygonsContain(polygons, p.x, p.y);

  /// The distance from [p] to the outline of an area, to a line, or to the
  /// nearest point, in world units.
  double distanceTo(WorldPoint p) => switch (kind) {
    GeometryKind.area => outlineDistance(polygons, p.x, p.y),
    GeometryKind.line => lines.fold(
      double.infinity,
      (best, line) => math.min(best, lineDistance(line, p.x, p.y)),
    ),
    GeometryKind.point => _pointDistance(p),
  };

  double _pointDistance(WorldPoint p) {
    var best = double.infinity;
    for (var i = 0; i + 1 < points.length; i += 2) {
      final dx = points[i] - p.x, dy = points[i + 1] - p.y;
      best = math.min(best, math.sqrt(dx * dx + dy * dy));
    }
    return best;
  }

  /// The polygons at the level of detail of zoom [bucket]
  /// ([LevelOfDetail]). Rings that collapse at that scale are left out, and
  /// so is a polygon whose exterior collapses.
  List<List<Float64List>> polygonsAt(int bucket) =>
      _polygonsFrom(_arcs.at(bucket), dropCollapsed: true);

  /// The lines at the level of detail of zoom [bucket].
  List<Float64List> linesAt(int bucket) => _linesFrom(_arcs.at(bucket));

  List<List<Float64List>> _polygonsFrom(
    List<Float64List> arcs, {
    bool dropCollapsed = false,
  }) {
    final result = <List<Float64List>>[];
    for (final polygon in _polygonRefs) {
      final rings = <Float64List>[];
      for (final ring in polygon) {
        final points = stitchArcs(ring, arcs);
        if (dropCollapsed && points.length < 8) {
          if (rings.isEmpty) break;
          continue;
        }
        rings.add(points);
      }
      if (rings.isNotEmpty) result.add(rings);
    }
    return result;
  }

  List<Float64List> _linesFrom(List<Float64List> arcs) => [
    for (final line in _lineRefs) stitchArcs(line, arcs),
  ];

  static Float64List _projectPoints(Float64List lonLat) {
    final world = Float64List(lonLat.length);
    for (var i = 0; i + 1 < lonLat.length; i += 2) {
      world[i] = WebMercator.x(lonLat[i]);
      world[i + 1] = WebMercator.y(lonLat[i + 1]);
    }
    return world;
  }
}

/// A layer's arcs in world coordinates, with their simplification at the
/// zoom buckets drawn recently.
final class _ArcStore {
  _ArcStore(this.arcs);

  /// Projects the arcs that [features] use. The others stay empty: a
  /// topology may hold several layers' objects.
  factory _ArcStore.project(Topology topology, List<TopoFeature> features) {
    final arcs = List.filled(topology.arcs.length, _empty);
    void use(List<int> refs) {
      for (final ref in refs) {
        final i = arcIndexOf(ref);
        if (identical(arcs[i], _empty)) arcs[i] = _project(topology.arcs[i]);
      }
    }

    for (final feature in features) {
      switch (feature.geometry) {
        case TopoPolygons(:final polygons):
          for (final polygon in polygons) {
            polygon.forEach(use);
          }
        case TopoLines(:final lines):
          lines.forEach(use);
        case TopoPoints():
          break;
      }
    }
    return _ArcStore(arcs);
  }

  static final _empty = Float64List(0);

  /// How many buckets' simplified arcs to keep.
  static const _cachedBuckets = 4;

  final List<Float64List> arcs;
  List<Float64List>? _ranks;
  final _buckets = <int, List<Float64List>>{};

  /// The arcs simplified for [bucket].
  List<Float64List> at(int bucket) {
    final cached = _buckets.remove(bucket);
    if (cached != null) return _buckets[bucket] = cached;
    final ranks = _ranks ??= [for (final arc in arcs) simplificationRanks(arc)];
    final tolerance = LevelOfDetail.toleranceOf(bucket);
    final simplified = [
      for (var i = 0; i < arcs.length; i++)
        simplifyArc(arcs[i], ranks[i], tolerance),
    ];
    if (_buckets.length == _cachedBuckets) {
      _buckets.remove(_buckets.keys.first);
    }
    return _buckets[bucket] = simplified;
  }

  static Float64List _project(Float64List lonLat) {
    final world = Float64List(lonLat.length);
    for (var i = 0; i + 1 < lonLat.length; i += 2) {
      world[i] = WebMercator.x(lonLat[i]);
      world[i + 1] = WebMercator.y(lonLat[i + 1]);
    }
    return world;
  }
}
