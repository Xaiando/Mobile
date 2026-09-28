import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
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
}
