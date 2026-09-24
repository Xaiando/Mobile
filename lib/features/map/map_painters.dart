import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/geography/geo_layer.dart';
import '../../core/geography/hit_test.dart';
import '../../core/geography/level_of_detail.dart';
import '../../core/geography/map_view.dart';
import '../../core/geography/planar.dart';
import '../../core/geography/web_mercator.dart';
import 'map_presentation.dart';
import 'map_style.dart';

/// What the features drawn with one path share: their pass and paint.
typedef _BatchStyle = ({int pass, Color? fill, Color stroke, double width});

/// One configuration of the map: its layers, how each feature looks, the
/// names and the style. [revision] changes whenever what is drawn changes;
/// panning and zooming do not change it.
final class MapScene {
  MapScene({
    required this.layers,
    required this.presentation,
    required this.candidates,
    required this.parent,
    required this.highlights,
    required this.names,
    required this.style,
    required this.markers,
    required this.base,
    required this.revision,
  });

  final List<MapLayer> layers;
  final MapPresentation presentation;
  final Set<String> candidates;
  final String? parent;
  final Map<String, MapHighlight> highlights;
  final Map<String, String> names;
  final MapStyle style;
  final MarkerRule markers;

  /// World coordinates to the map's unzoomed sheet: the limit bounds fitted
  /// to the viewport. The InteractiveViewer scales and moves the sheet.
  final MapView base;

  final int revision;

  final _looks = <GeoShape, FeatureLook>{};

  FeatureLook lookOf(MapLayer layer, GeoShape shape) =>
      _looks[shape] ??= presentation.look(
        switch (shape.key) {
          final key? when candidates.contains(key) => FeatureRole.candidate,
          final key? when key == parent => FeatureRole.parent,
          _ when layer.isBase => FeatureRole.base,
          _ => FeatureRole.context,
        },
        onBaseLayer: layer.isBase,
        highlight: highlights[shape.key],
      );

  /// The name written on [shape]: the question's name for its node, or the
  /// feature's own name, which context layers such as rivers carry.
  String? nameOf(GeoShape shape) => names[shape.key] ?? shape.name;

  /// Whether [shape] is drawn as a marker at [pixelsPerWorld]: a point
  /// feature, or a candidate or highlighted feature too small to tap
  /// (geography §5).
  bool drawsMarker(FeatureLook look, GeoShape shape, double pixelsPerWorld) {
    if (!look.drawn) return false;
    if (shape.kind == GeometryKind.point) return true;
    final isTarget =
        look.role == FeatureRole.candidate || look.highlight != null;
    return isTarget && markers.appliesTo(shape, pixelsPerWorld);
  }

  Color highlightColor(MapHighlight highlight) => switch (highlight) {
    MapHighlight.focus => style.focus,
    MapHighlight.correct => style.correct,
    MapHighlight.incorrect => style.incorrect,
  };
}

/// The zoom bucket and the visible layers of the current view. The geometry
/// painter repaints only when they change, so panning reuses its pictures.
final class MapDetail extends ChangeNotifier {
  int _bucket = 0;
  List<bool> _visible = const [];

  int get bucket => _bucket;

  bool isVisible(int layer) => layer < _visible.length && _visible[layer];

  void update(double pixelsPerWorld, List<MapLayer> layers) {
    final zoom = WebMercator.zoomOf(pixelsPerWorld);
    final bucket = LevelOfDetail.bucketOf(pixelsPerWorld);
    final visible = [for (final l in layers) l.geometry.isVisibleAt(zoom)];
    if (bucket == _bucket && listEquals(visible, _visible)) return;
    _bucket = bucket;
    _visible = visible;
    notifyListeners();
  }
}

/// One recorded picture per layer and zoom bucket (geography §8), kept for
/// the two buckets drawn last so zooming back and forth reuses them.
final class MapPictureCache {
  int? _revision;
  final _pictures = <int, Map<int, ui.Picture>>{};

  /// How many pictures have been recorded.
  int get recordings => _recordings;
  int _recordings = 0;

  ui.Picture picture(
    int revision,
    int layer,
    int bucket,
    ui.Picture Function() record,
  ) {
    if (revision != _revision) {
      clear();
      _revision = revision;
    }
    final byBucket = _pictures.putIfAbsent(layer, () => {});
    final cached = byBucket.remove(bucket);
    if (cached != null) return byBucket[bucket] = cached;
    _recordings++;
    final picture = byBucket[bucket] = record();
    if (byBucket.length > 2) byBucket.remove(byBucket.keys.first)!.dispose();
    return picture;
  }

  void clear() {
    for (final byBucket in _pictures.values) {
      for (final picture in byBucket.values) {
        picture.dispose();
      }
    }
    _pictures.clear();
    _revision = null;
  }
}

/// Paints the layers on the map's unzoomed sheet from cached pictures. It
/// sits inside the InteractiveViewer, which scales and moves the sheet.
final class MapGeometryPainter extends CustomPainter {
  MapGeometryPainter({
    required this.scene,
    required this.detail,
    required this.pictures,
  }) : super(repaint: detail);

  final MapScene scene;
  final MapDetail detail;
  final MapPictureCache pictures;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = scene.style.water);
    final bucket = detail.bucket;
    for (var i = 0; i < scene.layers.length; i++) {
      if (!detail.isVisible(i)) continue;
      canvas.drawPicture(
        pictures.picture(
          scene.revision,
          i,
          bucket,
          () => _record(scene.layers[i], bucket),
        ),
      );
    }
  }

  /// Draws [layer] at the level of detail of [bucket]: context first, then
  /// the base map, the parent, the candidates and the highlights on top.
  ///
  /// Features that look alike share one path, so a layer costs a few draw
  /// calls however many features it has. Exteriors are wound clockwise and
  /// holes the other way, so the non-zero fill rule leaves holes open and
  /// fills where features overlap (GEO-16), and all outlines are stroked
  /// over all fills.
  ui.Picture _record(MapLayer layer, int bucket) {
    // Sheet units per logical pixel at the bucket's smallest scale. Within
    // the bucket, lines grow by at most 2^¼ before the next picture.
    final unit = scene.base.scale / LevelOfDetail.scaleOf(bucket);
    final batches = <_BatchStyle, Path>{};
    for (final shape in layer.geometry.shapes) {
      final look = scene.lookOf(layer, shape);
      if (!look.drawn) continue;
      switch (shape.kind) {
        case GeometryKind.area:
          final polygons = shape.polygonsAt(bucket);
          if (polygons.isEmpty) continue;
          final (fill, stroke, width) = _areaPaint(look);
          final path = batches.putIfAbsent((
            pass: _passOf(look),
            fill: fill,
            stroke: stroke,
            width: width,
          ), Path.new);
          for (final polygon in polygons) {
            for (var i = 0; i < polygon.length; i++) {
              path.addPolygon(_ring(polygon[i], clockwise: i == 0), true);
            }
          }
        case GeometryKind.line:
          final lines = shape.linesAt(bucket);
          if (lines.isEmpty) continue;
          final (color, width) = _linePaint(look);
          final path = batches.putIfAbsent((
            pass: _passOf(look),
            fill: null,
            stroke: color,
            width: width,
          ), Path.new);
          for (final line in lines) {
            path.addPolygon(_line(line), false);
          }
        case GeometryKind.point:
          // Points are markers, drawn by the overlay at a fixed size.
          break;
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final styles = batches.keys.toList();
    final order = List.generate(styles.length, (i) => i)
      ..sort(
        (a, b) => styles[a].pass != styles[b].pass
            ? styles[a].pass.compareTo(styles[b].pass)
            : a.compareTo(b),
      );
    for (final i in order) {
      final style = styles[i];
      final path = batches[style]!;
      if (style.fill case final fill?) {
        canvas.drawPath(path, Paint()..color = fill);
      }
      canvas.drawPath(path, _stroke(style.stroke, style.width * unit));
    }
    return recorder.endRecording();
  }

  static int _passOf(FeatureLook look) {
    if (look.highlight != null) return 4;
    return switch (look.role) {
      FeatureRole.context => 0,
      FeatureRole.base => 1,
      FeatureRole.parent => 2,
      FeatureRole.candidate => 3,
    };
  }

  (Color?, Color, double) _areaPaint(FeatureLook look) {
    final style = scene.style;
    if (look.highlight case final highlight?) {
      final color = scene.highlightColor(highlight);
      return (color.withValues(alpha: 0.35), color, style.highlightWidth);
    }
    return switch (look.role) {
      FeatureRole.candidate => (
        style.candidateFill,
        style.candidateOutline,
        style.outlineWidth,
      ),
      FeatureRole.parent => (null, style.parentOutline, style.parentWidth),
      FeatureRole.base => (style.land, style.border, style.borderWidth),
      FeatureRole.context => (
        style.contextFill,
        style.contextOutline,
        style.outlineWidth,
      ),
    };
  }

  (Color, double) _linePaint(FeatureLook look) {
    final style = scene.style;
    if (look.highlight case final highlight?) {
      return (scene.highlightColor(highlight), style.riverWidth + 2);
    }
    return switch (look.role) {
      FeatureRole.candidate => (style.river, style.riverWidth + 1),
      FeatureRole.context => (
        style.river.withValues(alpha: 0.4),
        style.riverWidth,
      ),
      FeatureRole.base || FeatureRole.parent => (style.river, style.riverWidth),
    };
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..color = color
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// A closed ring on the sheet, without its repeated last point, wound
  /// clockwise on screen or the other way.
  List<Offset> _ring(Float64List ring, {required bool clockwise}) {
    final base = scene.base;
    final n = ring.length ~/ 2 - 1;
    final reverse = (ringArea(ring) > 0) != clockwise;
    final points = <Offset>[];
    for (var k = 0; k < n; k++) {
      final j = reverse ? n - 1 - k : k;
      points.add(
        Offset(base.screenX(ring[2 * j]), base.screenY(ring[2 * j + 1])),
      );
    }
    return points;
  }

  List<Offset> _line(Float64List line) {
    final base = scene.base;
    return [
      for (var i = 0; i + 1 < line.length; i += 2)
        Offset(base.screenX(line[i]), base.screenY(line[i + 1])),
    ];
  }

  @override
  bool shouldRepaint(MapGeometryPainter oldDelegate) =>
      oldDelegate.scene.revision != scene.revision ||
      oldDelegate.scene.base != scene.base;
}

/// What the overlay drew in its last paint, for tests and diagnostics.
@immutable
final class MapOverlayContents {
  const MapOverlayContents({
    required this.labels,
    required this.markers,
    required this.icons,
  });

  /// Each name written, with where.
  final List<({String? key, String text, Rect rect})> labels;

  /// The centre of each marker, by feature key.
  final Map<String, Offset> markers;

  /// Outcome icons, by feature key.
  final Map<String, MapHighlight> icons;

  Iterable<String> get names => labels.map((l) => l.text);
}

/// Paints what keeps its size whatever the zoom: markers, names and outcome
/// icons, in screen coordinates.
final class MapOverlayPainter extends CustomPainter {
  MapOverlayPainter({
    required this.scene,
    required this.view,
    required this.text,
    required this.onPainted,
    required super.repaint,
  });

  final MapScene scene;

  /// The current view, world to screen.
  final MapView Function() view;
  final MapTextCache text;
  final ValueSetter<MapOverlayContents> onPainted;

  @override
  void paint(Canvas canvas, Size size) {
    final v = view();
    final zoom = v.zoom;
    final style = scene.style;
    final radius = scene.markers.radius;
    final screen = (Offset.zero & size).deflate(2);
    final visible = v.visibleRect(size.width, size.height);
    final markers = <String, Offset>{};
    final icons = <String, MapHighlight>{};
    final requests = <_LabelRequest>[];

    for (final layer in scene.layers) {
      if (!layer.geometry.isVisibleAt(zoom)) continue;
      for (final shape in layer.geometry.shapes) {
        final look = scene.lookOf(layer, shape);
        if (!look.drawn) continue;
        final reach = (radius + 2) / v.scale;
        if (!shape.bounds.inflate(reach).overlaps(visible)) continue;
        final asMarker = scene.drawsMarker(look, shape, v.scale);
        final outcome = switch (look.highlight) {
          MapHighlight.correct || MapHighlight.incorrect => look.highlight,
          _ => null,
        };
        final name = look.named ? scene.nameOf(shape) : null;
        if (!asMarker && outcome == null && name == null) continue;

        final p = shape.labelPoint;
        final anchor = Offset(v.screenX(p.x), v.screenY(p.y));
        if (asMarker) {
          _marker(canvas, anchor, look, radius);
          if (shape.key case final key?) markers[key] = anchor;
        }
        if (outcome != null) {
          _icon(canvas, anchor, outcome, asMarker ? radius : 10);
          if (shape.key case final key?) icons[key] = outcome;
        }
        if (name != null) {
          requests.add(
            _LabelRequest(
              order: requests.length,
              key: shape.key,
              text: name,
              kind: switch (look.role) {
                FeatureRole.parent => _LabelKind.parent,
                FeatureRole.base || FeatureRole.context
                    when shape.kind == GeometryKind.line =>
                  _LabelKind.river,
                FeatureRole.base || FeatureRole.context => _LabelKind.area,
                FeatureRole.candidate => _LabelKind.candidate,
              },
              anchor: anchor,
              placement: asMarker
                  ? _Placement.besideMarker
                  : outcome != null
                  ? _Placement.belowIcon
                  : shape.kind == GeometryKind.line
                  ? _Placement.aboveLine
                  : _Placement.centred,
              priority: look.highlight != null
                  ? 0
                  : switch (look.role) {
                      FeatureRole.candidate => 1,
                      FeatureRole.parent => 2,
                      _ => 3,
                    },
            ),
          );
        }
      }
    }

    requests.sort(
      (a, b) => a.priority != b.priority
          ? a.priority.compareTo(b.priority)
          : a.order.compareTo(b.order),
    );
    final grid = _LabelGrid();
    final labels = <({String? key, String text, Rect rect})>[];
    for (final request in requests) {
      final (fill, halo) = text._labelPainters(
        request.text,
        request.kind,
        style,
      );
      final w = fill.width, h = fill.height;
      final a = request.anchor;
      final rect = switch (request.placement) {
        _Placement.centred => Rect.fromCenter(center: a, width: w, height: h),
        _Placement.besideMarker => Rect.fromLTWH(
          a.dx + radius + 4,
          a.dy - h / 2,
          w,
          h,
        ),
        _Placement.belowIcon => Rect.fromLTWH(a.dx - w / 2, a.dy + 12, w, h),
        _Placement.aboveLine => Rect.fromLTWH(a.dx - w / 2, a.dy - h - 3, w, h),
      };
      if (!_contains(screen, rect) || !grid.fits(rect)) continue;
      grid.add(rect);
      halo.paint(canvas, rect.topLeft);
      fill.paint(canvas, rect.topLeft);
      labels.add((key: request.key, text: request.text, rect: rect));
    }
    onPainted(
      MapOverlayContents(labels: labels, markers: markers, icons: icons),
    );
  }

  void _marker(Canvas canvas, Offset centre, FeatureLook look, double radius) {
    final style = scene.style;
    final color = switch (look.highlight) {
      final highlight? => scene.highlightColor(highlight),
      null when look.isDimmed => style.contextOutline,
      null => style.marker,
    };
    canvas
      ..drawCircle(centre, radius + 1.5, Paint()..color = style.labelHalo)
      ..drawCircle(centre, radius, Paint()..color = color);
  }

  void _icon(Canvas canvas, Offset centre, MapHighlight outcome, double r) {
    final style = scene.style;
    canvas
      ..drawCircle(centre, r + 1.5, Paint()..color = style.labelHalo)
      ..drawCircle(centre, r, Paint()..color = scene.highlightColor(outcome));
    final glyph = text._iconPainter(outcome, r * 1.5);
    glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));
  }

  static bool _contains(Rect outer, Rect inner) =>
      inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;

  @override
  bool shouldRepaint(MapOverlayPainter oldDelegate) =>
      oldDelegate.scene.revision != scene.revision ||
      !mapEquals(oldDelegate.scene.names, scene.names) ||
      oldDelegate.scene.base != scene.base;
}

enum _LabelKind { candidate, parent, area, river }

enum _Placement { centred, besideMarker, belowIcon, aboveLine }

final class _LabelRequest {
  _LabelRequest({
    required this.order,
    required this.key,
    required this.text,
    required this.kind,
    required this.anchor,
    required this.placement,
    required this.priority,
  });

  /// The order in which features were met, which breaks priority ties.
  final int order;
  final String? key;
  final String text;
  final _LabelKind kind;
  final Offset anchor;
  final _Placement placement;

  /// Highlighted features first, then candidates, the parent and the rest.
  final int priority;
}

/// Placed labels, bucketed by screen cell so a new label is checked only
/// against its neighbours.
final class _LabelGrid {
  static const _cell = 64.0;
  final _cells = <int, List<Rect>>{};

  Iterable<int> _keys(Rect rect) sync* {
    final x0 = (rect.left / _cell).floor(), x1 = (rect.right / _cell).floor();
    final y0 = (rect.top / _cell).floor(), y1 = (rect.bottom / _cell).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        yield x * 65536 + y;
      }
    }
  }

  bool fits(Rect rect) => _keys(rect).every(
    (key) => !(_cells[key]?.any((placed) => placed.overlaps(rect)) ?? false),
  );

  void add(Rect rect) {
    for (final key in _keys(rect)) {
      (_cells[key] ??= []).add(rect);
    }
  }
}

/// Laid-out names and icons, kept while the style and text settings stay.
final class MapTextCache {
  MapStyle? _style;
  TextScaler _scaler = TextScaler.noScaling;
  TextDirection _direction = TextDirection.ltr;
  TextStyle _typeface = const TextStyle();
  final _labels = <(String, _LabelKind), (TextPainter, TextPainter)>{};
  final _icons = <(MapHighlight, double), TextPainter>{};

  /// Applies the context's text settings: the text scale, the direction and
  /// the typeface of [ambient], the surrounding text style. Clears the cache
  /// if they changed.
  bool configure(
    TextScaler scaler,
    TextDirection direction,
    TextStyle ambient,
  ) {
    final typeface = TextStyle(
      fontFamily: ambient.fontFamily,
      fontFamilyFallback: ambient.fontFamilyFallback,
    );
    if (scaler == _scaler && direction == _direction && typeface == _typeface) {
      return false;
    }
    clear();
    _scaler = scaler;
    _direction = direction;
    _typeface = typeface;
    return true;
  }

  (TextPainter, TextPainter) _labelPainters(
    String text,
    _LabelKind kind,
    MapStyle style,
  ) {
    if (style != _style) {
      clear();
      _style = style;
    }
    final label = _typeface.merge(_labelStyle(kind, style));
    return _labels[(text, kind)] ??= (
      _layout(text, label),
      _layout(
        text,
        label.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round
            ..color = style.labelHalo,
        ),
      ),
    );
  }

  TextPainter _iconPainter(MapHighlight outcome, double size) {
    final data = outcome == MapHighlight.correct ? Icons.check : Icons.close;
    return _icons[(outcome, size)] ??= _layout(
      String.fromCharCode(data.codePoint),
      TextStyle(
        fontFamily: data.fontFamily,
        package: data.fontPackage,
        fontSize: size,
        height: 1,
        color: const Color(0xFFFFFFFF),
      ),
    );
  }

  TextPainter _layout(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: _direction,
    textScaler: _scaler,
    maxLines: 1,
  )..layout();

  static TextStyle _labelStyle(_LabelKind kind, MapStyle style) =>
      switch (kind) {
        _LabelKind.candidate => TextStyle(
          fontSize: style.labelSize,
          fontWeight: FontWeight.w600,
          color: style.label,
        ),
        _LabelKind.parent => TextStyle(
          fontSize: style.labelSize + 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: style.parentOutline,
        ),
        _LabelKind.area => TextStyle(
          fontSize: style.labelSize,
          color: style.border,
        ),
        _LabelKind.river => TextStyle(
          fontSize: style.labelSize - 1,
          fontStyle: FontStyle.italic,
          color: style.river,
        ),
      };

  void clear() {
    for (final (fill, halo) in _labels.values) {
      fill.dispose();
      halo.dispose();
    }
    for (final icon in _icons.values) {
      icon.dispose();
    }
    _labels.clear();
    _icons.clear();
  }
}
