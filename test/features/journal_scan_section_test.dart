import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
import 'package:sommelier/core/journal/label_proposal.dart';
import 'package:sommelier/features/cellar/journal_scan_section.dart';

class _QueuedPicker extends ImagePicker {
  _QueuedPicker(this._files);

  final List<XFile> _files;

  @override
  bool supportsImageSource(ImageSource source) => true;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => _files.removeAt(0);
}

class _HeldPicker extends ImagePicker {
  final result = Completer<XFile?>();

  @override
  bool supportsImageSource(ImageSource source) => true;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) => result.future;
}

class _RecordingPicker extends ImagePicker {
  final calls =
      <({ImageSource source, double? width, double? height, int? quality})>[];

  @override
  bool supportsImageSource(ImageSource source) => true;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls.add((
      source: source,
      width: maxWidth,
      height: maxHeight,
      quality: imageQuality,
    ));
    return null;
  }
}

XFile _label(String name) => XFile.fromData(
  Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2))),
  path: name,
  mimeType: 'image/png',
);

Finder get _rawField => find.widgetWithText(
  TextField,
  'Recognized or manually transcribed label text',
);

Future<void> _showScan(
  WidgetTester tester, {
  required ImagePicker picker,
  required Future<String> Function(String) recognizeText,
  required void Function(PhotoKind, Uint8List) onPicked,
  ValueChanged<String>? onProducer,
  ValueChanged<String>? onCuvee,
  ValueChanged<String>? onAppellation,
  ValueChanged<String>? onGrapes,
  Set<LabelField> occupiedFields = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JournalScanSection(
            picker: picker,
            recognizeText: recognizeText,
            onPicked: onPicked,
            onVintage: (_) {},
            onNonVintage: () {},
            onAbv: (_) {},
            onProducer: onProducer,
            onCuvee: onCuvee,
            onAppellation: onAppellation,
            onGrapes: onGrapes,
            occupiedFields: occupiedFields,
          ),
        ),
      ),
    ),
  );
}

Future<void> _chooseLabel(WidgetTester tester) async {
  final button = find.text('Choose label');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await _waitForScan(tester);
}

Future<void> _waitForScan(WidgetTester tester) async {
  await tester.pump();
  for (
    var i = 0;
    i < 30 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pump();
  expect(find.byType(LinearProgressIndicator), findsNothing);
}

void _scanTestWidgets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    // Set the platform inside the test callback and restore it before the
    // binding checks debug globals. OCR is injected, so no mobile picker
    // temporary-file cleanup or Android lost-data recovery is needed.
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

void main() {
  testWidgets('Android camera and gallery avoid native image resizing', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final picker = _RecordingPicker();
      await _showScan(
        tester,
        picker: picker,
        recognizeText: (_) async => '',
        onPicked: (_, _) {},
      );

      await tester.tap(find.text('Scan label'));
      await _waitForScan(tester);
      await _chooseLabel(tester);

      expect(picker.calls, [
        (source: ImageSource.camera, width: null, height: null, quality: 100),
        (source: ImageSource.gallery, width: null, height: null, quality: 100),
      ]);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  _scanTestWidgets(
    'a replacement label clears old OCR clues when its OCR fails',
    (tester) async {
      final picked = <PhotoKind>[];
      await _showScan(
        tester,
        picker: _QueuedPicker([_label('label-a.png'), _label('label-b.png')]),
        recognizeText: (path) async {
          if (path == 'label-a.png') return 'Estate 2019 13.5%';
          throw StateError('OCR unavailable');
        },
        onPicked: (kind, _) => picked.add(kind),
      );

      await _chooseLabel(tester);
      expect(
        tester.widget<TextField>(_rawField).controller!.text,
        'Estate 2019 13.5%',
      );
      expect(find.text('Use vintage 2019'), findsOneWidget);
      expect(find.text('Use 13.5% alcohol'), findsOneWidget);

      await _chooseLabel(tester);
      expect(picked, [PhotoKind.label, PhotoKind.label]);
      expect(tester.widget<TextField>(_rawField).controller!.text, isEmpty);
      expect(find.text('Use vintage 2019'), findsNothing);
      expect(find.text('Use 13.5% alcohol'), findsNothing);
      expect(
        find.textContaining('Text recognition was unavailable'),
        findsOneWidget,
      );
    },
  );

  _scanTestWidgets('a manually edited transcript survives a replacement scan', (
    tester,
  ) async {
    final picked = <PhotoKind>[];
    await _showScan(
      tester,
      picker: _QueuedPicker([_label('label-a.png'), _label('label-b.png')]),
      recognizeText: (path) async {
        if (path == 'label-a.png') return 'Estate 2019 13.5%';
        throw StateError('OCR unavailable');
      },
      onPicked: (kind, _) => picked.add(kind),
    );

    await _chooseLabel(tester);
    await tester.ensureVisible(_rawField);
    await tester.enterText(_rawField, 'Manual transcription 2022 12%');
    await tester.pump();

    await _chooseLabel(tester);
    expect(picked, [PhotoKind.label, PhotoKind.label]);
    expect(
      tester.widget<TextField>(_rawField).controller!.text,
      'Manual transcription 2022 12%',
    );
    expect(find.text('Use vintage 2022'), findsOneWidget);
    expect(find.text('Use 12.0% alcohol'), findsOneWidget);
    expect(find.text('Use vintage 2019'), findsNothing);
    expect(find.textContaining('your label text was kept'), findsOneWidget);
  });

  _scanTestWidgets(
    'late OCR cannot overwrite text entered while it was running',
    (tester) async {
      final ocr = Completer<String>();
      final picked = <PhotoKind>[];
      await _showScan(
        tester,
        picker: _QueuedPicker([_label('label-a.png')]),
        recognizeText: (_) => ocr.future,
        onPicked: (kind, _) => picked.add(kind),
      );

      await tester.tap(find.text('Choose label'));
      for (var i = 0; i < 10 && picked.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(picked, [PhotoKind.label]);
      await tester.ensureVisible(_rawField);
      await tester.enterText(_rawField, 'Manual transcription 2022 12%');
      await tester.pump();

      ocr.complete('Estate 2019 13.5%');
      await _waitForScan(tester);
      expect(
        tester.widget<TextField>(_rawField).controller!.text,
        'Manual transcription 2022 12%',
      );
      expect(find.text('Use vintage 2022'), findsOneWidget);
      expect(find.text('Use vintage 2019'), findsNothing);
      expect(find.text('Use 13.5% alcohol'), findsNothing);
    },
  );
  _scanTestWidgets(
    'disabled scanner rejects a pending pick and stale proposal callbacks',
    (tester) async {
      final picker = _HeldPicker();
      final picked = <PhotoKind>[];
      final vintages = <int>[];
      final alcohol = <double>[];
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return JournalScanSection(
                    enabled: enabled,
                    picker: picker,
                    recognizeText: (_) async => 'Estate 2022 12%',
                    onPicked: (kind, _) => picked.add(kind),
                    onVintage: vintages.add,
                    onNonVintage: () {},
                    onAbv: alcohol.add,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(_rawField);
      await tester.enterText(_rawField, 'Manual Estate 2019 13.5%');
      await tester.pump();
      final vintageCallback = tester
          .widget<ActionChip>(
            find.widgetWithText(ActionChip, 'Use vintage 2019'),
          )
          .onPressed!;
      final abvCallback = tester
          .widget<ActionChip>(
            find.widgetWithText(ActionChip, 'Use 13.5% alcohol'),
          )
          .onPressed!;
      await tester.ensureVisible(find.text('Choose label'));
      await tester.tap(find.text('Choose label'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      update(() => enabled = false);
      await tester.pump();
      expect(tester.widget<TextField>(_rawField).enabled, isFalse);
      vintageCallback();
      abvCallback();
      picker.result.complete(_label('late-label.png'));
      await _waitForScan(tester);
      expect(picked, isEmpty);
      expect(vintages, isEmpty);
      expect(alcohol, isEmpty);
      expect(
        tester.widget<TextField>(_rawField).controller!.text,
        'Manual Estate 2019 13.5%',
      );
      for (final label in ['Choose label', 'Choose glass']) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
      for (final label in ['Use vintage 2019', 'Use 13.5% alcohol']) {
        expect(
          tester
              .widget<ActionChip>(find.widgetWithText(ActionChip, label))
              .onPressed,
          isNull,
        );
      }
      update(() => enabled = true);
      await tester.pump();
      await _chooseLabel(tester);
      expect(picked, [PhotoKind.label]);
      expect(
        tester.widget<TextField>(_rawField).controller!.text,
        'Manual Estate 2019 13.5%',
      );
      expect(tester.takeException(), isNull);
    },
  );
  _scanTestWidgets('full-label suggestions require a separate tap per field', (
    tester,
  ) async {
    final accepted = <String>[];
    await _showScan(
      tester,
      picker: _QueuedPicker([_label('label-a.png')]),
      recognizeText: (_) async =>
          'Domaine des Roches\nCuvée Les Pierres\nChablis AOC\n'
          'Grapes: Chardonnay\n2020\n13.5%',
      onPicked: (_, _) {},
      onProducer: (value) => accepted.add('producer:$value'),
      onCuvee: (value) => accepted.add('cuvee:$value'),
      onAppellation: (value) => accepted.add('place:$value'),
      onGrapes: (value) => accepted.add('grapes:$value'),
    );
    await _chooseLabel(tester);
    expect(accepted, isEmpty);
    for (final label in [
      'Use producer Domaine des Roches',
      'Use cuvée Les Pierres',
      'Use region Chablis',
      'Use grapes Chardonnay',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(accepted, [
      'producer:Domaine des Roches',
      'cuvee:Les Pierres',
      'place:Chablis',
      'grapes:Chardonnay',
    ]);
  });

  _scanTestWidgets('occupied fields disable matching scan suggestions', (
    tester,
  ) async {
    final accepted = <String>[];
    await _showScan(
      tester,
      picker: _QueuedPicker([_label('label-a.png')]),
      recognizeText: (_) async =>
          'Producer: Scanned Estate\nCuvée Réserve\nRegion: Barolo\n'
          'Grapes: Nebbiolo\n2020\n13.5%',
      onPicked: (_, _) {},
      onProducer: accepted.add,
      onCuvee: accepted.add,
      onAppellation: accepted.add,
      onGrapes: accepted.add,
      occupiedFields: const {
        LabelField.producer,
        LabelField.appellation,
        LabelField.vintage,
        LabelField.abv,
      },
    );
    await _chooseLabel(tester);
    for (final label in [
      'Use producer Scanned Estate',
      'Use region Barolo',
      'Use vintage 2020',
      'Use 13.5% alcohol',
    ]) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(ActionChip),
      );
      expect(tester.widget<ActionChip>(chip).onPressed, isNull);
    }
    final cuvee = find.text('Use cuvée Réserve');
    await tester.ensureVisible(cuvee);
    await tester.tap(cuvee);
    expect(accepted, ['Réserve']);
  });

  _scanTestWidgets(
    'new proposal callbacks reject later occupancy and a saving editor',
    (tester) async {
      var enabled = true;
      var occupied = <LabelField>{};
      late StateSetter update;
      final accepted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return JournalScanSection(
                    enabled: enabled,
                    occupiedFields: occupied,
                    onPicked: (_, _) {},
                    onVintage: (value) => accepted.add('vintage:$value'),
                    onNonVintage: () => accepted.add('NV'),
                    onAbv: (value) => accepted.add('abv:$value'),
                    onProducer: (value) => accepted.add('producer:$value'),
                    onCuvee: (value) => accepted.add('cuvee:$value'),
                    onAppellation: (value) => accepted.add('place:$value'),
                    onGrapes: (value) => accepted.add('grapes:$value'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        _rawField,
        'Producer: Scanned Estate\nCuvée Réserve\nRegion: Barolo\nGrapes: Nebbiolo\n2020\n13.5%',
      );
      await tester.pump();
      const labels = [
        'Use producer Scanned Estate',
        'Use cuvée Réserve',
        'Use region Barolo',
        'Use grapes Nebbiolo',
        'Use vintage 2020',
        'Use 13.5% alcohol',
      ];
      final callbacks = [
        for (final label in labels)
          tester
              .widget<ActionChip>(find.widgetWithText(ActionChip, label))
              .onPressed!,
      ];
      update(() => occupied = LabelField.values.toSet());
      await tester.pump();
      for (final callback in callbacks) {
        callback();
      }
      expect(accepted, isEmpty);
      for (final label in labels) {
        expect(
          tester
              .widget<ActionChip>(find.widgetWithText(ActionChip, label))
              .onPressed,
          isNull,
        );
      }
      update(() {
        occupied = {};
        enabled = false;
      });
      await tester.pump();
      for (final callback in callbacks) {
        callback();
      }
      expect(accepted, isEmpty);
      update(() {
        enabled = true;
      });
      await tester.pump();
      await tester.ensureVisible(find.text(labels.first));
      await tester.tap(find.text(labels.first));
      expect(accepted, ['producer:Scanned Estate']);
    },
  );
  _scanTestWidgets(
    'a replacement photo clears untouched old producer clues when OCR fails',
    (tester) async {
      final accepted = <String>[];
      await _showScan(
        tester,
        picker: _QueuedPicker([_label('name-a.png'), _label('name-b.png')]),
        recognizeText: (path) async {
          if (path == 'name-a.png') {
            return 'Producer: Old Estate\nCuvée Réserve\nRegion: Barolo\nGrapes: Nebbiolo';
          }
          throw StateError('OCR unavailable');
        },
        onPicked: (_, _) {},
        onProducer: accepted.add,
        onCuvee: accepted.add,
        onAppellation: accepted.add,
        onGrapes: accepted.add,
      );
      await _chooseLabel(tester);
      expect(find.text('Use producer Old Estate'), findsOneWidget);
      expect(find.text('Use cuvée Réserve'), findsOneWidget);
      expect(find.text('Use region Barolo'), findsOneWidget);
      expect(find.text('Use grapes Nebbiolo'), findsOneWidget);
      expect(accepted, isEmpty);
      await _chooseLabel(tester);
      expect(tester.widget<TextField>(_rawField).controller!.text, isEmpty);
      for (final label in [
        'Use producer Old Estate',
        'Use cuvée Réserve',
        'Use region Barolo',
        'Use grapes Nebbiolo',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(accepted, isEmpty);
    },
  );
}
