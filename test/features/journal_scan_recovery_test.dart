import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
import 'package:sommelier/core/journal/journal_scan_recovery.dart';
import 'package:sommelier/core/journal/recovered_scan_storage.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/features/cellar/journal_scan_recovery_provider.dart';
import 'package:sommelier/features/cellar/journal_scan_section.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

class _FakePicker extends ImagePicker {
  _FakePicker(this.result, {this.pickedFile});
  final LostDataResponse result;
  final XFile? pickedFile;
  int calls = 0;

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
  }) async => pickedFile;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    calls++;
    return result;
  }
}

class _MemoryStorage extends RecoveredScanStorage {
  final file = const RecoveredScanFile(
    id: '00000000-0000-4000-8000-000000000001',
    path: 'recovered-photo.png',
    mimeType: 'image/png',
  );
  Uint8List? bytes;
  Future<void>? beforeRead;
  final pickerPaths = <String>{};
  bool lostResultInProgress = false;
  int markerBegins = 0;
  int markerCompletions = 0;

  @override
  Future<bool> beginLostResult() async {
    final wasUnresolved = lostResultInProgress;
    lostResultInProgress = true;
    markerBegins++;
    return wasUnresolved;
  }

  @override
  Future<bool> pickerPathExists(String path) async => pickerPaths.contains(path);

  @override
  Future<void> completeLostResult() async {
    if (!lostResultInProgress) {
      throw StateError('Interrupted picker result marker is missing.');
    }
    lostResultInProgress = false;
    markerCompletions++;
  }

  @override
  Future<String?> recordPickerCachePath(String path) async {
    pickerPaths.add(path);
    return path;
  }

  @override
  Future<List<String>> pendingPickerCachePaths() async {
    if (lostResultInProgress) {
      throw StateError('An interrupted picker result needs manual recovery.');
    }
    return pickerPaths.toList();
  }

  @override
  Future<void> forgetPickerCachePath(String path) async {
    pickerPaths.remove(path);
  }

  @override
  Future<RecoveredScanFile> stage(Uint8List value) async {
    bytes = value;
    return file;
  }

  @override
  Future<List<RecoveredScanFile>> list() async =>
      bytes == null ? const [] : [file];

  @override
  Future<Uint8List> read(String id) async {
    await beforeRead;
    if (id != file.id || bytes == null) throw StateError('Missing photo.');
    return bytes!;
  }

  @override
  Future<void> discard(String id) async {
    if (id != file.id) throw StateError('Missing photo.');
    bytes = null;
  }

  @override
  Future<void> clearAll() async {
    if (lostResultInProgress) {
      throw StateError('An interrupted picker result needs manual recovery.');
    }
    bytes = null;
    pickerPaths.clear();
  }
}

Uint8List _photo() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2)));

void main() {
  testWidgets('journal save waits while a recovered photo is being read', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    final db = openTestDatabase();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final storage = _MemoryStorage();
      await storage.stage(JournalPhotoStore.sanitize(_photo()));
      final readReady = Completer<void>();
      storage.beforeRead = readReady.future;
      final recovery = JournalScanRecovery(
        storage: storage,
        androidRuntime: false,
      );
      await pumpApp(
        tester,
        db,
        overrides: [journalScanRecoveryProvider.overrideWithValue(recovery)],
      );
      await tester.tap(find.text('Cellar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log a wine'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Producer'),
        'Slow Photo Estate',
      );
      final editorScroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final use = find.text('Use as glass');
      await tester.scrollUntilVisible(use, 450, scrollable: editorScroll);
      await tester.tap(use);
      await tester.pump();
      final save = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      readReady.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final entries = await tester.runAsync(() => WineJournal(db).entries());
      expect(entries, hasLength(1));
      final photos = await tester.runAsync(
        () => db
            .customSelect(
              'SELECT kind FROM wine_journal_photos WHERE wine_journal_entry_id = ?',
              variables: [Variable.withString(entries!.single.id)],
            )
            .get(),
      );
      expect(photos, hasLength(1));
      expect(photos!.single.read<String>('kind'), 'glass');
      expect(await recovery.pending(), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      debugDefaultTargetPlatformOverride = previousPlatform;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(db.close);
    }
  });

  testWidgets('pending scan waits for startup staging before first read', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final ready = Completer<void>();
      final storage = _MemoryStorage();
      final recovery = JournalScanRecovery(
        storage: storage,
        androidRuntime: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JournalScanSection(
              recovery: recovery,
              recoveryReady: ready.future,
              onPicked: (_, _) {},
              onVintage: (_) {},
              onNonVintage: () {},
              onAbv: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Recovered photo'), findsNothing);
      await storage.stage(JournalPhotoStore.sanitize(_photo()));
      ready.complete();
      await tester.pumpAndSettle();
      expect(find.text('Recovered photo'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets(
    'recovered photo survives section disposal and still supports OCR',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final storage = _MemoryStorage();
        final staged = await storage.stage(
          JournalPhotoStore.sanitize(_photo()),
        );
        final recovery = JournalScanRecovery(
          storage: storage,
          androidRuntime: false,
        );
        final picked = <PhotoKind>[];
        final paths = <String>[];
        final picker = _FakePicker(
          LostDataResponse.empty(),
          pickedFile: XFile.fromData(_photo(), path: 'fresh.png'),
        );

        Future<void> showSection() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: JournalScanSection(
                    recovery: recovery,
                    picker: picker,
                    onPicked: (kind, _) => picked.add(kind),
                    onRecoveredPicked: (kind, _, id) {
                      expect(id, staged.id);
                      picked.add(kind);
                    },
                    onVintage: (_) {},
                    onNonVintage: () {},
                    onAbv: (_) {},
                    recognizeText: (path) async {
                      paths.add(path);
                      return 'Estate 2019 13.5%';
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await showSection();
        expect(find.text('Recovered photo'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(await recovery.pending(), hasLength(1));

        await showSection();
        await tester.tap(find.text('Use as label'));
        await tester.pumpAndSettle();
        expect(picked, [PhotoKind.label]);
        expect(paths, [staged.path]);
        expect(find.text('Use vintage 2019'), findsOneWidget);
        expect(find.text('Recovered photo'), findsOneWidget);
        expect(await recovery.pending(), hasLength(1));

        // The same editor must continue offering the stage after a new pick.
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        await tester.tap(find.text('Choose label'));
        await tester.pumpAndSettle();
        expect(picked, [PhotoKind.label, PhotoKind.label]);
        expect(find.text('Recovered photo'), findsOneWidget);

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await showSection();
        expect(find.text('Recovered photo'), findsOneWidget);
        await tester.tap(find.text('Dismiss'));
        await tester.pumpAndSettle();
        expect(await recovery.pending(), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'startup recovery is visible before editor opens; failed save retains it',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      final db = openTestDatabase();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final picker = _FakePicker(
          LostDataResponse(
            type: RetrieveType.image,
            files: [XFile.fromData(_photo(), path: 'picker-cache.png')],
          ),
        );
        final storage = _MemoryStorage();
        final recovery = JournalScanRecovery(
          picker: picker,
          storage: storage,
          androidRuntime: true,
        );
        await pumpApp(
          tester,
          db,
          overrides: [journalScanRecoveryProvider.overrideWithValue(recovery)],
        );
        expect(picker.calls, 1);
        expect(await recovery.pending(), hasLength(1));
        expect(storage.markerBegins, 1);
        expect(storage.markerCompletions, 1);
        expect(storage.lostResultInProgress, isFalse);

        await tester.tap(find.text('Cellar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log a wine'));
        await tester.pumpAndSettle();
        final editorScroll = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final use = find.text('Use as glass');
        await tester.scrollUntilVisible(use, 450, scrollable: editorScroll);
        await tester.tap(use);
        await tester.pumpAndSettle();
        expect(await recovery.pending(), hasLength(1));

        final discardPreview = find.byTooltip('Discard new glass photo');
        await tester.scrollUntilVisible(
          discardPreview,
          250,
          scrollable: editorScroll,
        );
        await tester.tap(discardPreview);
        await tester.pumpAndSettle();
        expect(find.text('Recovered photo'), findsOneWidget);
        expect(await recovery.pending(), hasLength(1));
        await tester.ensureVisible(use);
        await tester.tap(use);
        await tester.pumpAndSettle();

        final save = find.text('Save');
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          find.text('Name the wine: a producer, cuvée, appellation or grapes.'),
          findsOneWidget,
        );
        expect(await recovery.pending(), hasLength(1));

        final producer = find.widgetWithText(TextField, 'Producer');
        await tester.scrollUntilVisible(
          producer,
          -500,
          scrollable: editorScroll,
        );
        await tester.enterText(producer, 'Recovered Estate');
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.runAsync(
          () => WineJournal(db)
              .watchAll()
              .firstWhere(
                (entries) => entries.any(
                  (entry) => entry.producerName == 'Recovered Estate',
                ),
              )
              .timeout(const Duration(seconds: 10)),
        );
        await tester.pumpAndSettle();
        final entry = (await tester.runAsync(() => WineJournal(db).entries()))!
            .singleWhere((row) => row.producerName == 'Recovered Estate');
        final photos = (await tester.runAsync(
          () => JournalPhotoStore(db).watchForEntry(entry.id).first,
        ))!;
        expect(
          photos.where((photo) => photo.kind == PhotoKind.glass),
          hasLength(1),
        );
        expect(await recovery.pending(), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        debugDefaultTargetPlatformOverride = previousPlatform;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(db.close);
      }
    },
  );
}
