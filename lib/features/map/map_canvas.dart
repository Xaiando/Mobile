import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/geography/coordinates.dart';
import '../../core/geography/geo_layer.dart';
import '../../core/geography/hit_test.dart';
import '../../core/geography/map_view.dart';
import '../../core/geography/web_mercator.dart';
import 'map_painters.dart';
import 'map_presentation.dart';
import 'map_style.dart';

/// An offline vector map for study and quiz formats (geography §8, GEO-12).
///
/// The layers are drawn by a [CustomPainter] inside an [InteractiveViewer],
/// from pictures cached per layer and zoom bucket, with the geometry logic
/// in `lib/core/geography`. Everything is Dart and Flutter, so it behaves
/// the same on Android, iOS and the web, and needs no network (GEO-3).
///
/// - The map opens on [frame], or on [zoomedOutFrame] in the blank mode, and
///   pans and zooms within [bounds] and [maxZoom].
/// - [mode] decides what is drawn and named (geography §4, GEO-8), and
///   [revealed] shows what it hid once the question is answered.
/// - A candidate smaller than 24 logical pixels is drawn as a marker, so
///   every target stays tappable (geography §5).
/// - A tap is hit-tested against the [candidates] on the layers visible at
///   the current zoom, by the inside and near rules of geography §4, and
///   reported to [onTap].
/// - An information button lists the attributions of the visible layers
///   (GEO-14).
class MapCanvas extends StatefulWidget {
  const MapCanvas({
    super.key,
    required this.layers,
    this.mode = MapLabelMode.labelled,
    this.candidates = const {},
    this.parent,
    this.highlights = const {},
    this.revealed = false,
    this.names = const {},
    this.frame,
    this.zoomedOutFrame,
    this.bounds,
    this.maxZoom = 16,
    this.padding = 16,
    this.hitTester = const MapHitTester(),
    this.style,
    this.onTap,
  });

  /// The layers, bottom first.
  final List<MapLayer> layers;

  final MapLabelMode mode;

  /// The feature keys of the possible answers: the same-type siblings in
  /// the frame (geography §5). They are drawn in full, named as [mode]
  /// allows, and they are the only features a tap can hit, while their
  /// layer is within its zoom range.
  final Set<String> candidates;

  /// The feature key of the area the frame shows, named in the outline mode.
  final String? parent;

  /// Features to emphasise: the shape a question asks about, or an answer's
  /// outcome.
  final Map<String, MapHighlight> highlights;

  /// Whether the question is answered, which reveals what [mode] hid.
  final bool revealed;

  /// Names by feature key, from the knowledge graph. A feature without one
  /// uses its own `name` property.
  final Map<String, String> names;

  /// What the map shows first: the question's frame (geography §5).
  /// Defaults to [bounds].
  final GeoBounds? frame;

  /// Where the blank mode starts: the frame one level up. Defaults to
  /// [bounds].
  final GeoBounds? zoomedOutFrame;

  /// How far the map pans and zooms out. Defaults to the extent of the
  /// layers. The frames are always within reach.
  final GeoBounds? bounds;

  /// How far the map zooms in, as a Web Mercator zoom level. It always
  /// reaches the frame.
  final double maxZoom;

  /// Logical pixels kept between a frame and the edges of the map.
  final double padding;

  /// The tap rules: the near distance and the marker rule.
  final MapHitTester hitTester;

  /// Colours and widths. Defaults to [MapStyle.of] the theme.
  final MapStyle? style;

  final ValueChanged<MapTap>? onTap;

  @override
  State<MapCanvas> createState() => MapCanvasState();
}

class MapCanvasState extends State<MapCanvas> {
  final _controller = TransformationController();
  final _detail = MapDetail();
  final _pictures = MapPictureCache();
  final _text = MapTextCache();

  Size? _viewport;
  MapView? _base;
  MapViewLimits? _limits;
  MapScene? _scene;
  MapStyle? _style;
  MapOverlayContents? _overlay;
  bool _reset = true;
  int _revision = 0;

  /// Each candidate shape, with its layer.
  List<(MapLayer, GeoShape)> _candidates = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_viewChanged);
    _candidates = _findCandidates();
  }

  @override
  void didUpdateWidget(MapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    final layersChanged = !listEquals(old.layers, widget.layers);
    if (layersChanged ||
        old.frame != widget.frame ||
        old.zoomedOutFrame != widget.zoomedOutFrame ||
        old.bounds != widget.bounds ||
        old.maxZoom != widget.maxZoom ||
        old.padding != widget.padding ||
        (old.mode == MapLabelMode.blank) !=
            (widget.mode == MapLabelMode.blank)) {
      _reset = true;
    }
    if (layersChanged ||
        old.mode != widget.mode ||
        old.revealed != widget.revealed ||
        !setEquals(old.candidates, widget.candidates) ||
        old.parent != widget.parent ||
        !mapEquals(old.highlights, widget.highlights) ||
        old.hitTester != widget.hitTester) {
      _revision++;
    }
    if (layersChanged || !setEquals(old.candidates, widget.candidates)) {
      _candidates = _findCandidates();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_viewChanged)
      ..dispose();
    _detail.dispose();
    _pictures.clear();
    _text.clear();
    super.dispose();
  }

  List<(MapLayer, GeoShape)> _findCandidates() => [
    for (final layer in widget.layers)
      for (final shape in layer.geometry.shapes)
        if (widget.candidates.contains(shape.key)) (layer, shape),
  ];

  /// The current view: world coordinates to the canvas's.
  MapView get _view {
    final base = _base!;
    final m = _controller.value.storage;
    final k = m[0];
    return MapView(
      scale: base.scale * k,
      dx: base.dx * k + m[12],
      dy: base.dy * k + m[13],
    );
  }

  /// Shows [view], which must respect the limits. The InteractiveViewer's
  /// matrix maps the sheet, on which [_base] draws the world, to the canvas.
  void _show(MapView view) {
    final base = _base!;
    final k = view.scale / base.scale;
    _controller.value = Matrix4.diagonal3Values(k, k, k)
      ..setTranslationRaw(view.dx - k * base.dx, view.dy - k * base.dy, 0);
  }

  void _viewChanged() {
    if (_base != null) _detail.update(_view.scale, widget.layers);
  }

  /// Fits the map to a new viewport size, or to new frames. The view opens
  /// on the frame; on a resize, it keeps its centre and scale.
  void _layOut(Size size) {
    if (!_reset && size == _viewport) return;
    final previous = _reset || _base == null ? null : _view;
    final previousSize = _viewport;
    _viewport = size;

    final bounds = _limitBounds();
    final base = MapView.fit(
      bounds,
      width: size.width,
      height: size.height,
      padding: widget.padding,
    );
    final opening = widget.mode == MapLabelMode.blank
        ? widget.zoomedOutFrame ?? widget.bounds
        : widget.frame ?? widget.bounds;
    final start = opening == null
        ? base
        : MapView.fit(
            WebMercator.projectBounds(opening),
            width: size.width,
            height: size.height,
            padding: widget.padding,
          );
    final frameScale = widget.frame == null
        ? start.scale
        : MapView.fit(
            WebMercator.projectBounds(widget.frame!),
            width: size.width,
            height: size.height,
            padding: widget.padding,
          ).scale;
    // The cached pictures are drawn on the sheet, so a new sheet needs new
    // pictures.
    if (base != _base) _revision++;
    _base = base;
    _limits = MapViewLimits(
      bounds: base.visibleRect(size.width, size.height),
      minScale: base.scale,
      maxScale: math.max(
        base.scale,
        math.max(WebMercator.scaleOf(widget.maxZoom), frameScale),
      ),
    );

    var target = start;
    if (previous != null && previousSize != null) {
      final centre = previous.toWorld(
        previousSize.width / 2,
        previousSize.height / 2,
      );
      target = MapView(
        scale: previous.scale,
        dx: size.width / 2 - centre.x * previous.scale,
        dy: size.height / 2 - centre.y * previous.scale,
      );
    }
    _show(target.clamp(_limits!, width: size.width, height: size.height));
    _reset = false;
    _viewChanged();
  }

  /// The world rectangle the map may show: [MapCanvas.bounds] or the
  /// layers' extent, and the frames.
  WorldRect _limitBounds() {
    WorldRect? rect = widget.bounds == null
        ? null
        : WebMercator.projectBounds(widget.bounds!);
    if (rect == null) {
      for (final layer in widget.layers) {
        final extent = layer.geometry.bounds;
        if (extent != null) rect = rect?.union(extent) ?? extent;
      }
    }
    for (final frame in [widget.frame, widget.zoomedOutFrame]) {
      if (frame == null) continue;
      final extent = WebMercator.projectBounds(frame);
      rect = rect?.union(extent) ?? extent;
    }
    return rect ?? const WorldRect(0, 0, 1, 1);
  }

  void _tapped(TapUpDetails details) {
    final scene = _scene, size = _viewport;
    if (scene == null || size == null) return;
    final view = _view;
    final world = _base!.toWorld(
      details.localPosition.dx,
      details.localPosition.dy,
    );
    final layerOf = {
      for (final (layer, shape) in _candidates)
        if (layer.geometry.isVisibleAt(view.zoom)) shape: layer,
    };
    final hits = widget.hitTester.hitTest(
      layerOf.keys,
      world,
      view.scale,
      drawnAsMarker: (shape) => scene.drawsMarker(
        scene.lookOf(layerOf[shape]!, shape),
        shape,
        view.scale,
      ),
    );
    widget.onTap?.call(
      MapTap(
        position: WebMercator.unproject(world),
        hits: hits,
        zoom: view.zoom,
        visibleBounds: WebMercator.unprojectRect(
          view.visibleRect(size.width, size.height),
        ),
      ),
    );
  }

  List<String> _visibleAttributions() {
    final zoom = _view.zoom;
    return [
      ...{
        for (final layer in widget.layers)
          if (layer.geometry.isVisibleAt(zoom)) ?layer.geometry.attribution,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? MapStyle.of(context);
    if (style != _style) {
      _style = style;
      _revision++;
    }
    if (_text.configure(
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      DefaultTextStyle.of(context).style,
    )) {
      _revision++;
    }
    final attributed = widget.layers.any((l) => l.geometry.attribution != null);

    return Semantics(
      container: true,
      label: 'Map',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          assert(size.isFinite, 'A MapCanvas needs a bounded size.');
          _layOut(size);
          final scene = _scene = MapScene(
            layers: widget.layers,
            presentation: MapPresentation(
              mode: widget.mode,
              revealed: widget.revealed,
            ),
            candidates: widget.candidates,
            parent: widget.parent,
            highlights: widget.highlights,
            names: widget.names,
            style: style,
            markers: widget.hitTester.markers,
            base: _base!,
            revision: _revision,
          );
          return ClipRect(
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1,
                  maxScale: _limits!.maxScale / _base!.scale,
                  child: RepaintBoundary(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: widget.onTap == null ? null : _tapped,
                      child: CustomPaint(
                        size: size,
                        painter: MapGeometryPainter(
                          scene: scene,
                          detail: _detail,
                          pictures: _pictures,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MapOverlayPainter(
                        scene: scene,
                        view: () => _view,
                        text: _text,
                        onPainted: (contents) => _overlay = contents,
                        repaint: _controller,
                      ),
                    ),
                  ),
                ),
                if (attributed)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _AttributionButton(
                      attributions: _visibleAttributions,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The current view, world coordinates to the canvas's.
  @visibleForTesting
  MapView get debugView => _view;

  /// How far the view may pan and zoom.
  @visibleForTesting
  MapViewLimits get debugLimits => _limits!;

  /// The markers, names and icons of the last paint.
  @visibleForTesting
  MapOverlayContents? get debugOverlay => _overlay;

  /// How the feature with [key] is drawn in the current mode.
  @visibleForTesting
  FeatureLook debugLookOf(String key) {
    for (final layer in widget.layers) {
      if (layer.geometry.shapeFor(key) case final shape?) {
        return _scene!.lookOf(layer, shape);
      }
    }
    throw ArgumentError.value(key, 'key', 'not on the map');
  }

  /// Pictures recorded so far: once per layer, zoom bucket and change of
  /// what is drawn.
  @visibleForTesting
  int get debugPictureRecordings => _pictures.recordings;
}

/// The information button of GEO-14: the attributions of the visible
/// layers.
class _AttributionButton extends StatelessWidget {
  const _AttributionButton({required this.attributions});

  final List<String> Function() attributions;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Map data sources',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.info_outline),
      onPressed: () {
        final sources = attributions();
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Map data'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sources.isEmpty)
                  const Text('The layers in view need no attribution.'),
                for (final source in sources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(source),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}
