import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/features/map/map_canvas.dart';
import 'package:sommelier/features/map/map_painters.dart';
import 'package:sommelier/features/map/map_presentation.dart';

import '../../support/geography_fixture.dart';

/// The map's overlay: its markers, names and icons.
final overlay = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is MapOverlayPainter,
);

void main() {
  final fixture = FixtureLayers();
  final layers = [
    MapLayer.base(fixture.country),
    MapLayer(fixture.regions),
    MapLayer(fixture.areas),
    MapLayer.base(fixture.rivers),
    MapLayer(fixture.places),
  ];
  final northBox = GeoBounds(minLon: 3, minLat: 47.5, maxLon: 4, maxLat: 48.5);

  late List<MapTap> taps;
  setUp(() => taps = []);

  Future<MapCanvasState> pumpMap(
    WidgetTester tester, {
    MapLabelMode mode = MapLabelMode.labelled,
    Map<String, MapHighlight> highlights = const {},
    bool revealed = false,
    GeoBounds? frame,
    List<MapLayer>? mapLayers,
    Set<String> mapCandidates = fixtureCandidates,
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Directionality(textDirection: textDirection, child: child!),
        ),
        home: Scaffold(
          body: MapCanvas(
            layers: mapLayers ?? layers,
            mode: mode,
            candidates: mapCandidates,
            parent: 'n_fx_region',
            highlights: highlights,
            revealed: revealed,
            frame: frame ?? fixture.regionFrame,
            zoomedOutFrame: fixture.countryFrame,
            onTap: taps.add,
          ),
        ),
      ),
    );
    return tester.state<MapCanvasState>(find.byType(MapCanvas));
  }

  /// Where [p] is on screen, moved by [by] logical pixels.
  Offset onScreen(WidgetTester tester, LonLat p, [Offset by = Offset.zero]) {
    final view = tester.state<MapCanvasState>(find.byType(MapCanvas)).debugView;
    final world = WebMercator.project(p);
    return tester.getTopLeft(find.byType(MapCanvas)) +
        Offset(view.screenX(world.x), view.screenY(world.y)) +
        by;
  }

  Future<MapTap> tap(
    WidgetTester tester,
    LonLat p, [
    Offset by = Offset.zero,
  ]) async {
    final before = taps.length;
    await tester.tapAt(onScreen(tester, p, by));
    await tester.pump();
    expect(taps, hasLength(before + 1));
    return taps.last;
  }

  /// Scrolls the mouse wheel over [position]: the InteractiveViewer zooms in
  /// for a negative [dy] and out for a positive one, about the pointer.
  Future<void> wheel(
    WidgetTester tester,
    Offset position,
    double dy, {
    int times = 1,
  }) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(position));
    for (var i = 0; i < times; i++) {
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pump();
    }
  }

  group('taps', () {
    testWidgets('inside a candidate', (tester) async {
      await pumpMap(tester);
      final tapped = await tap(tester, const LonLat(3.2, 48.3));
      expect(tapped.hit?.key, 'n_fx_north');
      expect(tapped.hit?.kind, HitKind.inside);
      expect(tapped.position.lon, closeTo(3.2, 1e-6));
      expect(tapped.position.lat, closeTo(48.3, 1e-6));
      expect(tapped.visibleBounds.contains(tapped.position), isTrue);
      expect(tapped.zoom, closeTo(7.8, 0.1));
    });

    testWidgets('near a candidate: within 12 logical pixels', (tester) async {
      await pumpMap(tester);
      final tapped = await tap(tester, const LonLat(4, 48), const Offset(8, 0));
      expect(tapped.hit?.key, 'n_fx_north');
      expect(tapped.hit?.kind, HitKind.near);
      expect(tapped.hit?.distance, closeTo(8, 0.01));
    });

    testWidgets('outside every candidate', (tester) async {
      await pumpMap(tester);
      expect(
        (await tap(tester, const LonLat(4, 48), const Offset(20, 0))).hit,
        isNull,
      );
      // In the middle of North Hills' hole, 16 pixels from its edge.
      expect((await tap(tester, const LonLat(3.5, 48))).hit, isNull);
      // East Slope is drawn, but it is not a candidate.
      expect((await tap(tester, const LonLat(5.4, 48.4))).hit, isNull);
    });

    testWidgets('ignores candidates on zoom-hidden layers', (tester) async {
      final hiddenAreas = GeoLayer.fromTopology(
        fixture.topology,
        id: 'ml_fx_hidden_areas',
        object: 'areas',
        maxZoom: 0,
      );
      final state = await pumpMap(
        tester,
        mapLayers: [MapLayer.base(fixture.country), MapLayer(hiddenAreas)],
        mapCandidates: const {'n_fx_north'},
      );
      expect(hiddenAreas.isVisibleAt(state.debugView.zoom), isFalse);
      expect((await tap(tester, const LonLat(3.2, 48.3))).hit, isNull);
    });

    testWidgets('an exact hit wins over a near one', (tester) async {
      await pumpMap(tester);
      final tapped = await tap(
        tester,
        const LonLat(3.5, 47.5),
        const Offset(0, 4),
      );
      expect(tapped.hits.map((h) => (h.key, h.kind)), [
        ('n_fx_south', HitKind.inside),
        ('n_fx_north', HitKind.near),
      ]);
    });

    testWidgets('the same after zooming and panning', (tester) async {
      await pumpMap(tester);
      await wheel(tester, onScreen(tester, const LonLat(3.5, 47)), -150);
      // Slowly, so the pan has no inertia.
      await tester.timedDrag(
        find.byType(MapCanvas),
        const Offset(-40, 30),
        const Duration(seconds: 2),
      );
      await tester.pumpAndSettle();
      final zoom = tester
          .state<MapCanvasState>(find.byType(MapCanvas))
          .debugView
          .zoom;
      expect(zoom, greaterThan(8.5));
      final tapped = await tap(tester, const LonLat(3.4, 47.1));
      expect(tapped.hit?.key, 'n_fx_south');
      expect(tapped.hit?.kind, HitKind.inside);
      expect(tapped.zoom, closeTo(zoom, 1e-9));
      final near = await tap(tester, const LonLat(4, 47), const Offset(10, 0));
      expect(near.hit?.key, 'n_fx_south');
      expect(near.hit?.kind, HitKind.near);
      expect(near.hit?.distance, closeTo(10, 0.01));
    });
  });

  group('markers', () {
    testWidgets('replace candidates too small to tap', (tester) async {
      final state = await pumpMap(tester);
      final markers = state.debugOverlay!.markers;
      expect(markers.keys, unorderedEquals(['n_fx_tiny', 'n_fx_village']));
      final origin = tester.getTopLeft(find.byType(MapCanvas));
      final centre = markers['n_fx_tiny']!;
      expect(
        centre,
        offsetMoreOrLessEquals(
          onScreen(tester, _tinyCentre) - origin,
          epsilon: 0.5,
        ),
      );
      // A halo ring, then the marker.
      expect(
        overlay,
        paints
          ..circle(x: centre.dx, y: centre.dy, radius: 9.5)
          ..circle(x: centre.dx, y: centre.dy, radius: 8),
      );
    });

    testWidgets('can be tapped, and near them counts', (tester) async {
      await pumpMap(tester);
      final marker = await tap(tester, _tinyCentre, const Offset(5, 0));
      expect(marker.hit?.key, 'n_fx_tiny');
      expect(marker.hit?.kind, HitKind.inside);
      final near = await tap(tester, _tinyCentre, const Offset(0, -17));
      expect(near.hit?.key, 'n_fx_tiny');
      expect(near.hit?.kind, HitKind.near);
      expect(
        (await tap(tester, _tinyCentre, const Offset(0, -22))).hit,
        isNull,
      );
    });

    testWidgets('give way to the shape when zoomed in', (tester) async {
      final state = await pumpMap(tester);
      await wheel(tester, onScreen(tester, _tinyCentre), -200, times: 3);
      expect(state.debugView.zoom, greaterThan(11.5));
      expect(state.debugOverlay!.markers.keys, isNot(contains('n_fx_tiny')));
      expect(
        state.debugOverlay!.markers.keys,
        isNot(contains('n_fx_village')),
        reason: 'out of view',
      );
      final inside = await tap(tester, _tinyCentre);
      expect(inside.hit?.key, 'n_fx_tiny');
      expect(inside.hit?.kind, HitKind.inside);
    });

    testWidgets('are hidden with the candidates in minimal mode', (
      tester,
    ) async {
      final state = await pumpMap(tester, mode: MapLabelMode.minimal);
      expect(state.debugOverlay!.markers, isEmpty);
      // A tap is graded against the tiny shape itself, not a marker.
      final tapped = await tap(tester, _tinyCentre, const Offset(5, 0));
      expect(tapped.hit?.kind, HitKind.near);
    });
  });

  group('label modes', () {
    const candidateNames = [
      'North Hills',
      'South Plain',
      'Twin Isles',
      'Tiny Clos',
      'Fixture Village',
    ];

    testWidgets('labelled: every candidate outlined and named', (tester) async {
      final state = await pumpMap(tester);
      final names = state.debugOverlay!.names;
      expect(
        names,
        containsAll([...candidateNames, 'Fixture Region', 'Fixture River']),
      );
      expect(
        names,
        isNot(contains('East Slope')),
        reason: 'context is never named',
      );
      expect(state.debugLookOf('n_fx_north').drawn, isTrue);
      expect(state.debugLookOf('n_fx_east').drawn, isTrue);
      expect(state.debugLookOf('n_fx_east').isDimmed, isTrue);
    });

    testWidgets('repaints labels when inherited text settings change', (
      tester,
    ) async {
      final state = await pumpMap(tester);
      final beforeOverlay = state.debugOverlay;
      final before = state.debugOverlay!.labels
          .singleWhere((label) => label.text == 'North Hills')
          .rect;

      final scaled = await pumpMap(
        tester,
        textScaler: TextScaler.linear(1.5),
        textDirection: TextDirection.rtl,
      );
      final after = scaled.debugOverlay!.labels
          .singleWhere((label) => label.text == 'North Hills')
          .rect;

      expect(scaled.debugOverlay, isNot(same(beforeOverlay)));
      expect(after.height, greaterThan(before.height));
    });

    testWidgets(
      'outline: candidates outlined but unnamed; parent and rivers named',
      (tester) async {
        final state = await pumpMap(tester, mode: MapLabelMode.outline);
        final names = state.debugOverlay!.names;
        for (final name in candidateNames) {
          expect(names, isNot(contains(name)));
        }
        expect(names, containsAll(['Fixture Region', 'Fixture River']));
        expect(state.debugLookOf('n_fx_north').drawn, isTrue);
        expect(state.debugLookOf('n_fx_north').named, isFalse);
        expect(state.debugOverlay!.markers.keys, contains('n_fx_tiny'));
      },
    );

    testWidgets('minimal: only the base map, nothing named', (tester) async {
      final state = await pumpMap(tester, mode: MapLabelMode.minimal);
      expect(state.debugOverlay!.names, isEmpty);
      expect(state.debugOverlay!.markers, isEmpty);
      for (final key in fixtureCandidates) {
        expect(state.debugLookOf(key).drawn, isFalse, reason: key);
      }
      expect(state.debugLookOf('n_fx_region').drawn, isFalse);
      expect(state.debugLookOf('n_fx_east').drawn, isFalse);
      expect(state.debugLookOf('n_fx_country').drawn, isTrue);
      expect(state.debugLookOf('n_fx_river').drawn, isTrue);
      expect(overlay, isNot(paints..paragraph()));
    });

    testWidgets('blank: minimal, zoomed out one level', (tester) async {
      final state = await pumpMap(tester, mode: MapLabelMode.blank);
      expect(state.debugOverlay!.names, isEmpty);
      expect(state.debugLookOf('n_fx_north').drawn, isFalse);
      final visible = state.debugView.visibleRect(800, 600);
      expect(
        visible.containsRect(
          WebMercator.projectBounds(fixture.countryFrame),
          tolerance: 1e-12,
        ),
        isTrue,
      );
      final blankScale = state.debugView.scale;
      await pumpMap(tester, mode: MapLabelMode.minimal);
      expect(blankScale, lessThan(state.debugView.scale));
    });

    testWidgets('revealing shows the candidates as labelled mode does', (
      tester,
    ) async {
      final state = await pumpMap(
        tester,
        mode: MapLabelMode.minimal,
        revealed: true,
      );
      expect(state.debugOverlay!.names, containsAll(candidateNames));
      expect(state.debugOverlay!.markers.keys, contains('n_fx_tiny'));
      expect(state.debugLookOf('n_fx_north').drawn, isTrue);
    });
  });

  group('highlighting', () {
    testWidgets(
      'a highlighted shape is drawn in every mode, unnamed until revealed',
      (tester) async {
        final state = await pumpMap(
          tester,
          mode: MapLabelMode.minimal,
          highlights: const {'n_fx_south': MapHighlight.focus},
        );
        final south = state.debugLookOf('n_fx_south');
        expect(south.drawn, isTrue);
        expect(south.highlight, MapHighlight.focus);
        expect(south.named, isFalse);
        expect(state.debugLookOf('n_fx_north').drawn, isFalse);
        expect(state.debugOverlay!.names, isEmpty);
      },
    );

    testWidgets('outcomes are marked by icon as well as colour', (
      tester,
    ) async {
      final state = await pumpMap(
        tester,
        mode: MapLabelMode.outline,
        revealed: true,
        highlights: const {
          'n_fx_north': MapHighlight.correct,
          'n_fx_tiny': MapHighlight.incorrect,
        },
      );
      expect(state.debugOverlay!.icons, {
        'n_fx_north': MapHighlight.correct,
        'n_fx_tiny': MapHighlight.incorrect,
      });
      expect(
        state.debugOverlay!.names,
        containsAll(['North Hills', 'Tiny Clos']),
      );
    });
  });

  group('pan and zoom', () {
    testWidgets('open on the frame', (tester) async {
      final state = await pumpMap(tester, frame: northBox);
      final visible = state.debugView.visibleRect(800, 600);
      final frame = WebMercator.projectBounds(northBox);
      expect(visible.containsRect(frame, tolerance: 1e-12), isTrue);
      // The frame fills the height, inside 16 pixels of padding.
      expect(frame.height * state.debugView.scale, closeTo(568, 0.01));
    });

    testWidgets('panning stops at the limits', (tester) async {
      final state = await pumpMap(tester, frame: northBox);
      for (final drag in const [Offset(3000, 2000), Offset(-6000, -4000)]) {
        await tester.drag(find.byType(MapCanvas), drag);
        await tester.pumpAndSettle();
        expect(
          state.debugLimits.allows(
            state.debugView,
            width: 800,
            height: 600,
            tolerance: 1e-6,
          ),
          isTrue,
        );
      }
      final visible = state.debugView.visibleRect(800, 600);
      expect(visible.right, closeTo(state.debugLimits.bounds.right, 1e-9));
      expect(visible.bottom, closeTo(state.debugLimits.bounds.bottom, 1e-9));
    });

    testWidgets('zooming stops at the limits', (tester) async {
      final state = await pumpMap(tester, frame: northBox);
      final centre = tester.getCenter(find.byType(MapCanvas));
      await wheel(tester, centre, 400, times: 6);
      expect(state.debugView.scale, closeTo(state.debugLimits.minScale, 1e-6));
      expect(
        state.debugLimits.allows(
          state.debugView,
          width: 800,
          height: 600,
          tolerance: 1e-6,
        ),
        isTrue,
      );
      await wheel(tester, centre, -400, times: 12);
      expect(state.debugView.scale, closeTo(state.debugLimits.maxScale, 1e-3));
      expect(state.debugView.zoom, closeTo(16, 1e-6));
      expect(
        state.debugLimits.allows(
          state.debugView,
          width: 800,
          height: 600,
          tolerance: 1e-6,
        ),
        isTrue,
      );
    });

    testWidgets('a resize keeps the centre and scale, and redraws', (
      tester,
    ) async {
      final state = await pumpMap(tester, frame: northBox);
      final before = state.debugView;
      final centre = before.toWorld(400, 300);
      final recorded = state.debugPictureRecordings;

      // Portrait, 400 × 800 logical pixels.
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(tester.view.reset);
      await tester.pump();

      final after = state.debugView;
      expect(after.scale, before.scale);
      expect(after.toWorld(200, 400).x, closeTo(centre.x, 1e-12));
      expect(after.toWorld(200, 400).y, closeTo(centre.y, 1e-12));
      expect(state.debugLimits.allows(after, width: 400, height: 800), isTrue);
      // The pictures are drawn on the sheet, which the resize changed.
      expect(state.debugPictureRecordings, greaterThan(recorded));
      final tapped = await tap(tester, const LonLat(3.2, 48.3));
      expect(tapped.hit?.key, 'n_fx_north');
    });

    testWidgets('pinching zooms within the limits too', (tester) async {
      final state = await pumpMap(tester, frame: northBox);
      final centre = tester.getCenter(find.byType(MapCanvas));
      final a = await tester.startGesture(
        centre - const Offset(20, 0),
        pointer: 7,
      );
      final b = await tester.startGesture(
        centre + const Offset(20, 0),
        pointer: 8,
      );
      for (var i = 1; i <= 20; i++) {
        await a.moveTo(centre - Offset(20.0 + 15 * i, 0));
        await b.moveTo(centre + Offset(20.0 + 15 * i, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(state.debugView.scale, greaterThan(WebMercator.scaleOf(9)));
      expect(
        state.debugLimits.allows(
          state.debugView,
          width: 800,
          height: 600,
          tolerance: 1e-6,
        ),
        isTrue,
      );
    });

    testWidgets(
      'panning reuses the cached pictures; a new zoom bucket records',
      (tester) async {
        final state = await pumpMap(tester);
        final recorded = state.debugPictureRecordings;
        expect(recorded, layers.length);
        await tester.drag(find.byType(MapCanvas), const Offset(-60, 40));
        await tester.pumpAndSettle();
        expect(state.debugPictureRecordings, recorded);
        await wheel(tester, tester.getCenter(find.byType(MapCanvas)), -60);
        final zoomed = state.debugPictureRecordings;
        expect(zoomed, greaterThan(recorded));
        await tester.drag(find.byType(MapCanvas), const Offset(-60, 40));
        await tester.pumpAndSettle();
        expect(state.debugPictureRecordings, zoomed);
      },
    );
  });

  testWidgets('the information button lists the attributions', (tester) async {
    await pumpMap(tester);
    await tester.tap(find.byTooltip('Map data sources'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture country data'), findsOneWidget);
    expect(find.text('Fixture area data'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Map data'), findsNothing);
  });

  testWidgets('the dark theme gets the dark style', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: MapCanvas(layers: layers)),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MapCanvas), findsOneWidget);
  });
}

/// The centre of Tiny Clos, where its marker sits.
const _tinyCentre = LonLat(5.505, 47.505);
