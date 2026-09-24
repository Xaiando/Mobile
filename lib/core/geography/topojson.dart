import 'dart:convert';
import 'dart:typed_data';

/// A TopoJSON topology
/// (https://github.com/topojson/topojson-specification), the format of the
/// map layer assets (geography §7): quantized, delta-encoded arcs, with each
/// border between two features stored once.
///
/// Decoding keeps the arcs and each feature's references to them, so a
/// shared border stays shared: the renderer simplifies it once for both
/// neighbours, and they never drift apart (see `GeoLayer`).
final class Topology {
  Topology._(this.arcs, this.objects);

  /// Parses TopoJSON text.
  ///
  /// Throws a [FormatException] if [source] is not a valid topology.
  factory Topology.parse(String source) =>
      Topology.fromJson(jsonDecode(source));

  /// Decodes a topology from its JSON value.
  ///
  /// Throws a [FormatException] if [json] is not a valid topology.
  factory Topology.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['type'] != 'Topology') {
      throw const FormatException('Not a TopoJSON topology');
    }
    final transform = _Transform.from(json['transform']);
    final rawArcs = json['arcs'];
    if (rawArcs is! List) {
      throw const FormatException('A topology needs its arcs');
    }
    final arcs = [
      for (var i = 0; i < rawArcs.length; i++)
        _decodeArc(rawArcs[i], i, transform),
    ];
    final rawObjects = json['objects'];
    if (rawObjects is! Map<String, Object?>) {
      throw const FormatException('A topology needs its objects');
    }
    final decoder = _GeometryDecoder(arcs, transform);
    return Topology._(List.unmodifiable(arcs), {
      for (final MapEntry(:key, :value) in rawObjects.entries)
        key: List.unmodifiable(decoder.features(value, key)),
    });
  }

  /// Every arc as absolute longitude and latitude pairs,
  /// `[lon0, lat0, lon1, lat1, …]`.
  final List<Float64List> arcs;

  /// The topology's objects by name, each flattened to its features.
  final Map<String, List<TopoFeature>> objects;

  /// The rings of each polygon of [geometry], in longitude and latitude.
  List<List<Float64List>> polygonsOf(TopoPolygons geometry) => [
    for (final polygon in geometry.polygons)
      [for (final ring in polygon) stitchArcs(ring, arcs)],
  ];

  /// The lines of [geometry], in longitude and latitude.
  List<Float64List> linesOf(TopoLines geometry) => [
    for (final line in geometry.lines) stitchArcs(line, arcs),
  ];
}

/// One feature of a topology object.
final class TopoFeature {
  const TopoFeature({
    required this.id,
    required this.properties,
    required this.geometry,
  });

  /// The feature's `id`: the `feature_key` of `node_geometries`
  /// (geography §3). Numeric IDs are written as integers.
  final String? id;

  final Map<String, Object?> properties;

  final TopoGeometry geometry;
}

/// A feature's shape, by reference to the topology's arcs.
///
/// An arc reference `i` is arc i; a negative reference `~i`, that is
/// `-i - 1`, is arc i reversed.
sealed class TopoGeometry {
  const TopoGeometry();
}

/// A Polygon or MultiPolygon: polygons of rings of arc references. The first
/// ring of a polygon is its exterior; the others are its holes.
final class TopoPolygons extends TopoGeometry {
  const TopoPolygons(this.polygons);

  final List<List<List<int>>> polygons;
}

/// A LineString or MultiLineString: lines of arc references.
final class TopoLines extends TopoGeometry {
  const TopoLines(this.lines);

  final List<List<int>> lines;
}

/// A Point or MultiPoint: decoded positions, `[lon0, lat0, lon1, lat1, …]`.
final class TopoPoints extends TopoGeometry {
  const TopoPoints(this.coordinates);

  final Float64List coordinates;
}

/// The index of the arc that [ref] refers to.
int arcIndexOf(int ref) => ref < 0 ? -ref - 1 : ref;

/// Joins the arcs of [refs] into one line of coordinates. Each arc after the
/// first starts where the previous one ends, so that shared point is kept
/// once; a ring's last point repeats its first.
Float64List stitchArcs(List<int> refs, List<Float64List> arcs) {
  var length = 0;
  for (var i = 0; i < refs.length; i++) {
    final points = arcs[arcIndexOf(refs[i])].length;
    length += i == 0 ? points : points - 2;
  }
  final out = Float64List(length);
  var o = 0;
  for (var i = 0; i < refs.length; i++) {
    final ref = refs[i];
    final arc = arcs[arcIndexOf(ref)];
    final n = arc.length ~/ 2;
    for (var k = i == 0 ? 0 : 1; k < n; k++) {
      final j = ref < 0 ? n - 1 - k : k;
      out[o++] = arc[2 * j];
      out[o++] = arc[2 * j + 1];
    }
  }
  return out;
}

/// The quantization transform: position = quantized · scale + translate.
final class _Transform {
  const _Transform(this.sx, this.sy, this.tx, this.ty);

  static _Transform? from(Object? json) {
    if (json == null) return null;
    if (json case {
      'scale': [final num sx, final num sy, ...],
      'translate': [final num tx, final num ty, ...],
    }) {
      return _Transform(
        sx.toDouble(),
        sy.toDouble(),
        tx.toDouble(),
        ty.toDouble(),
      );
    }
    throw const FormatException('Invalid topology transform');
  }

  final double sx;
  final double sy;
  final double tx;
  final double ty;
}

/// Decodes arc [index]. In a quantized topology every position after the
/// first is a delta from the previous one.
Float64List _decodeArc(Object? raw, int index, _Transform? transform) {
  if (raw is! List || raw.length < 2) {
    throw FormatException('Arc $index needs at least two positions');
  }
  final coordinates = Float64List(raw.length * 2);
  var x = 0.0, y = 0.0;
  for (var i = 0; i < raw.length; i++) {
    final position = raw[i];
    if (position is! List || position.length < 2) {
      throw FormatException('Arc $index has an invalid position: $position');
    }
    final px = position[0], py = position[1];
    if (px is! num || py is! num) {
      throw FormatException('Arc $index has an invalid position: $position');
    }
    if (transform == null) {
      coordinates[2 * i] = px.toDouble();
      coordinates[2 * i + 1] = py.toDouble();
    } else {
      x += px;
      y += py;
      coordinates[2 * i] = x * transform.sx + transform.tx;
      coordinates[2 * i + 1] = y * transform.sy + transform.ty;
    }
  }
  return coordinates;
}

final class _GeometryDecoder {
  _GeometryDecoder(this.arcs, this.transform);

  final List<Float64List> arcs;
  final _Transform? transform;

  /// The features of object [name]: geometry collections are flattened, and
  /// geometries of null type, which have no shape, are left out.
  List<TopoFeature> features(Object? object, String name) {
    final features = <TopoFeature>[];
    void add(Object? geometry) {
      if (geometry is! Map<String, Object?>) {
        throw FormatException('Object $name has an invalid geometry');
      }
      final type = geometry['type'];
      if (type == 'GeometryCollection') {
        final members = geometry['geometries'];
        if (members is! List) {
          throw FormatException('A collection in $name has no geometries');
        }
        members.forEach(add);
        return;
      }
      if (type == null) return;
      final properties = switch (geometry['properties']) {
        null => const <String, Object?>{},
        final Map<String, Object?> properties => properties,
        _ => throw FormatException('A feature of $name has invalid properties'),
      };
      features.add(
        TopoFeature(
          id: _featureId(geometry['id']),
          properties: properties,
          geometry: _shape(type, geometry, name),
        ),
      );
    }

    add(object);
    return features;
  }

  TopoGeometry _shape(Object type, Map<String, Object?> geometry, String name) {
    final arcRefs = geometry['arcs'];
    final coordinates = geometry['coordinates'];
    return switch (type) {
      'Polygon' => TopoPolygons([_polygon(arcRefs, name)]),
      'MultiPolygon' => TopoPolygons([
        for (final polygon in _parts(arcRefs, name)) _polygon(polygon, name),
      ]),
      'LineString' => TopoLines([_line(arcRefs, name)]),
      'MultiLineString' => TopoLines([
        for (final line in _parts(arcRefs, name)) _line(line, name),
      ]),
      'Point' => TopoPoints(_positions([coordinates], name)),
      'MultiPoint' => TopoPoints(_positions(_parts(coordinates, name), name)),
      _ => throw FormatException('Unknown geometry type $type in $name'),
    };
  }

  /// The parts of a multi-geometry, of which there is at least one.
  static List<Object?> _parts(Object? value, String name) {
    final parts = _list(value, name);
    if (parts.isEmpty) throw FormatException('A geometry of $name is empty');
    return parts;
  }

  List<List<int>> _polygon(Object? rings, String name) {
    final polygon = [for (final ring in _list(rings, name)) _ring(ring, name)];
    if (polygon.isEmpty) throw FormatException('A polygon of $name is empty');
    return polygon;
  }

  /// A ring's arc references. A ring is closed and has at least four
  /// positions, the last repeating the first.
  List<int> _ring(Object? refs, String name) {
    final ring = _line(refs, name);
    var points = 1;
    for (final ref in ring) {
      points += arcs[arcIndexOf(ref)].length ~/ 2 - 1;
    }
    final (x0, y0) = _end(ring.first, start: true);
    final (x1, y1) = _end(ring.last, start: false);
    if (points < 4 || x0 != x1 || y0 != y1) {
      throw FormatException('A ring of $name is not a closed ring: $ring');
    }
    return ring;
  }

  /// The first or last position of the arc that [ref] refers to, in the
  /// direction of the reference.
  (double, double) _end(int ref, {required bool start}) {
    final arc = arcs[arcIndexOf(ref)];
    return start == (ref >= 0)
        ? (arc[0], arc[1])
        : (arc[arc.length - 2], arc[arc.length - 1]);
  }

  List<int> _line(Object? refs, String name) {
    final line = [
      for (final ref in _list(refs, name))
        if (ref is int && arcIndexOf(ref) < arcs.length)
          ref
        else
          throw FormatException('$name refers to a missing arc: $ref'),
    ];
    if (line.isEmpty) throw FormatException('A line of $name has no arcs');
    return line;
  }

  Float64List _positions(List<Object?> positions, String name) {
    final coordinates = Float64List(positions.length * 2);
    for (var i = 0; i < positions.length; i++) {
      final position = positions[i];
      if (position case [final num x, final num y, ...]) {
        final t = transform;
        coordinates[2 * i] = t == null ? x.toDouble() : x * t.sx + t.tx;
        coordinates[2 * i + 1] = t == null ? y.toDouble() : y * t.sy + t.ty;
      } else {
        throw FormatException('A point of $name is invalid: $position');
      }
    }
    return coordinates;
  }

  static List<Object?> _list(Object? value, String name) {
    if (value is List) return value;
    throw FormatException('A geometry of $name is incomplete');
  }
}

/// A feature ID as text. JSON has one number type, so an integral ID reads
/// the same on every platform.
String? _featureId(Object? id) => switch (id) {
  null => null,
  String() => id,
  num() when id == id.truncateToDouble() => '${id.toInt()}',
  num() => '$id',
  _ => throw FormatException('Invalid feature id: $id'),
};
