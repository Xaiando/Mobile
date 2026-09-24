import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/features/map/map_canvas.dart';
import 'package:sommelier/features/map/map_presentation.dart';

import '../../support/geography_fixture.dart';

/// The stress layer of geography §10, 2,000 polygons with shared wavy
/// borders, against the budgets of GEO-11: a layer parses in at most 100 ms
/// on a mid-range phone, and a frame paints in at most 8 ms after warm-up.
///
/// The thresholds are generous on purpose. Tests run the Dart VM in JIT
/// mode with assertions on, on shared CI machines, and a widget test
/// records frames without rasterizing them; the budgets are for release
/// builds on a device, which task R2 measures. These thresholds catch a
/// regression of an order of magnitude.
void main() {
  const parseThresholdMs = 500.0;
  const panFrameThresholdMs = 40.0;
  const zoomFrameThresholdMs = 150.0;
  final source = stressTopoJson();

  double medianMs(List<int> micros) {
    final sorted = [...micros]..sort();
    return sorted[sorted.length ~/ 2] / 1000;
  }

  test('the stress layer is about the size of the per-layer budget', () {
    // GEO-11 allows 1.5 MB per layer.
    expect(source.length, inInclusiveRange(1000 * 1000, 1500 * 1000));
    final layer = GeoLayer.fromTopology(Topology.parse(source), id: 'stress');
    expect(layer.shapes, hasLength(2000));
  });

  test('parses within the threshold', () {
    GeoLayer.fromTopology(Topology.parse(source), id: 'warm-up');
    final runs = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      GeoLayer.fromTopology(Topology.parse(source), id: 'stress');
      runs.add(watch.elapsedMicroseconds);
    }
    final median = medianMs(runs);
    debugPrint('Stress layer parse: median ${median.toStringAsFixed(1)} ms');
    expect(median, lessThan(parseThresholdMs));
  });

  testWidgets('pans and zooms within the thresholds', (tester) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layer = GeoLayer.fromTopology(Topology.parse(source), id: 'stress');

    // Every cell a named candidate, zoomed in on the middle of the layer so
    // there is room to pan: the heaviest labelled map.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapCanvas(
            layers: [MapLayer(layer)],
            candidates: {for (final shape in layer.shapes) shape.key!},
            names: {
              for (final shape in layer.shapes)
                shape.key!: 'Cell ${shape.key!.substring(9)}',
            },
            frame: GeoBounds(minLon: 2.5, minLat: 42, maxLon: 7.5, maxLat: 46),
          ),
        ),
      ),
    );
    final state = tester.state<MapCanvasState>(find.byType(MapCanvas));
    expect(state.debugOverlay!.labels, isNotEmpty);

    final centre = tester.getCenter(find.byType(MapCanvas));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final pans = <int>[];
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(-3, 2));
      final watch = Stopwatch()..start();
      await tester.pump();
      pans.add(watch.elapsedMicroseconds);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.debugPictureRecordings, 1, reason: 'panning reuses it');

    // Each wheel step crosses a zoom bucket, so the layer is simplified
    // and recorded again.
    final zooms = <int>[];
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(centre));
    for (var i = 0; i < 8; i++) {
      final watch = Stopwatch()..start();
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
      await tester.pump();
      zooms.add(watch.elapsedMicroseconds);
    }
    expect(state.debugPictureRecordings, greaterThan(8));

    final pan = medianMs(pans.sublist(10));
    final zoom = medianMs(zooms);
    debugPrint(
      'Stress layer frames: pan median ${pan.toStringAsFixed(2)} ms, '
      'zoom-bucket median ${zoom.toStringAsFixed(1)} ms',
    );
    expect(pan, lessThan(panFrameThresholdMs));
    expect(zoom, lessThan(zoomFrameThresholdMs));
  });
}
