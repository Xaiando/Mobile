import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/curriculum/curriculum_providers.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
import 'package:sommelier/core/journal/journal_providers.dart';
import 'package:sommelier/core/journal/journal_scan_recovery.dart';
import 'package:sommelier/core/journal/recovered_scan_storage.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/features/cellar/journal_editor.dart';
import 'package:sommelier/features/cellar/journal_scan_recovery_provider.dart';
import 'package:sommelier/features/cellar/journal_scan_section.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';
import '../support/curriculum_fixture.dart';

class _HeldJournal extends WineJournal {
  _HeldJournal(super.db, {required this.failFirst});

  final bool failFirst;
  final started = Completer<void>();
  final release = Completer<void>();
  var calls = 0;
  late JournalDraft capturedDraft;
  late Map<PhotoKind, Uint8List> capturedPhotos;

  @override
  Future<WineJournalEntry> saveWithPhotos(
    JournalDraft draft, {
    String? id,
    Set<String> nodeIds = const {},
    Map<PhotoKind, Uint8List> photos = const {},
    Set<PhotoKind> removedKinds = const {},
  }) async {
    calls++;
    capturedDraft = draft;
    capturedPhotos = {
      for (final photo in photos.entries)
        photo.key: Uint8List.fromList(photo.value),
    };
    if (!started.isCompleted) started.complete();
    await release.future;
    if (failFirst && calls == 1) throw StateError('controlled save failure');
    return super.saveWithPhotos(
      draft,
      id: id,
      nodeIds: nodeIds,
      photos: photos,
      removedKinds: removedKinds,
    );
  }
}

class _RecoveryStorage extends RecoveredScanStorage {
  static const file = RecoveredScanFile(
    id: '00000000-0000-4000-8000-000000000001',
    path: 'test-recovered-glass.png',
    mimeType: 'image/png',
  );
  Uint8List? bytes;
  int discards = 0;

  @override
  Future<List<RecoveredScanFile>> list() async => bytes == null ? [] : [file];

  @override
  Future<Uint8List> read(String id) async {
    if (id != file.id || bytes == null) throw StateError('Missing photo');
    return bytes!;
  }

  @override
  Future<void> discard(String id) async {
    if (id != file.id || bytes == null) throw StateError('Missing photo');
    bytes = null;
    discards++;
  }
}

Uint8List _photo(int red) {
  final pixels = image.Image(width: 2, height: 2);
  pixels.setPixelRgba(0, 0, red, 10, 20, 255);
  return JournalPhotoStore.sanitize(
    Uint8List.fromList(image.encodePng(pixels)),
  );
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(JournalEditor),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final failFirst in [false, true]) {
    testWidgets(
      failFirst
          ? 'failed save unlocks the intact recovered photo and permits an exact retry'
          : 'save snapshot blocks new scanner actions and late form/photo callbacks',
      (tester) async {
        final platform = debugDefaultTargetPlatformOverride;
        final db = openTestDatabase();
        final journal = _HeldJournal(db, failFirst: failFirst);
        final storage = _RecoveryStorage()..bytes = _photo(100);
        final original = Uint8List.fromList(storage.bytes!);
        final recovery = JournalScanRecovery(
          storage: storage,
          androidRuntime: false,
        );
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await pumpApp(
            tester,
            db,
            overrides: [
              curriculumSourceProvider.overrideWithValue(
                () async => datasetOf(minimalDataset()),
              ),
              wineJournalProvider.overrideWithValue(journal),
              journalScanRecoveryProvider.overrideWithValue(recovery),
            ],
          );
          await tester.tap(find.text('Cellar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Log a wine'));
          await tester.pumpAndSettle();
          for (final (label, text) in [
            ('Producer', 'Snapshot Estate'),
            ('Vintage', '2019'),
            ('Alcohol %', '13.5'),
          ]) {
            final field = find.widgetWithText(TextField, label);
            await _reveal(tester, field);
            await tester.enterText(field, text);
            await tester.pump();
          }
          final use = find.text('Use as glass');
          await _reveal(tester, use);
          await tester.tap(use);
          await tester.pumpAndSettle();
          final scanner = tester.widget<JournalScanSection>(
            find.byType(JournalScanSection),
          );
          final remove = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == 'Discard new glass photo',
          );
          await _reveal(tester, remove);
          final staleRemove = tester.widget<IconButton>(remove).onPressed!;
          await _reveal(tester, find.widgetWithText(TextButton, 'Clear'));
          final staleDate = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Clear'))
              .onPressed!;
          final star = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '5 of 5',
          );
          final staleRating = tester.widget<IconButton>(star).onPressed!;
          final staleNonVintage = tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Non-vintage'),
              )
              .onChanged!;
          await tester.tap(find.widgetWithText(TextButton, 'Save'));
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => journal.started.future.timeout(const Duration(seconds: 5)),
          );
          expect(journal.capturedDraft.vintage, 2019);
          expect(journal.capturedDraft.abvPercent, 13.5);
          expect(
            journal.capturedPhotos[PhotoKind.glass],
            orderedEquals(original),
          );
          expect(storage.discards, 0);

          // The saving gate is visible as well as guarding callbacks captured
          // before the snapshot, including photo replacement and removal.
          await _reveal(tester, find.text('Choose label'));
          for (final label in [
            'Choose label',
            'Scan label',
            'Choose glass',
            'Photograph glass',
          ]) {
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, label),
                  )
                  .onPressed,
              isNull,
            );
          }
          for (final label in ['Use as label', 'Use as glass', 'Dismiss']) {
            expect(
              tester
                  .widget<TextButton>(find.widgetWithText(TextButton, label))
                  .onPressed,
              isNull,
            );
          }
          scanner.onPicked(PhotoKind.label, _photo(200));
          scanner.onRecoveredPicked!(
            PhotoKind.glass,
            _photo(200),
            _RecoveryStorage.file.id,
          );
          scanner.onVintage(2022);
          scanner.onNonVintage();
          scanner.onAbv(12);
          staleRemove();
          staleDate();
          staleRating();
          staleNonVintage(true);
          await tester.pumpAndSettle();
          expect(find.text('New glass'), findsOneWidget);
          expect(find.text('New label'), findsNothing);
          await _reveal(tester, find.widgetWithText(TextField, 'Vintage'));
          for (final (label, value) in [
            ('Producer', 'Snapshot Estate'),
            ('Vintage', '2019'),
            ('Alcohol %', '13.5'),
          ]) {
            final field = find.widgetWithText(TextField, label);
            await _reveal(tester, field);
            expect(tester.widget<TextField>(field).enabled, isFalse);
            expect(tester.widget<TextField>(field).controller!.text, value);
          }
          expect(
            tester
                .widget<SwitchListTile>(
                  find.widgetWithText(SwitchListTile, 'Non-vintage'),
                )
                .value,
            isFalse,
          );
          expect(
            tester
                .widget<SwitchListTile>(
                  find.widgetWithText(SwitchListTile, 'Non-vintage'),
                )
                .onChanged,
            isNull,
          );
          journal.release.complete();
          await tester.pumpAndSettle();
          if (failFirst) {
            expect(
              find.textContaining('controlled save failure'),
              findsOneWidget,
            );
            expect(await recovery.pending(), hasLength(1));
            expect(storage.discards, 0);
            expect(await tester.runAsync(() => journal.entries()), isEmpty);
            final producer = find.widgetWithText(TextField, 'Producer');
            await _reveal(tester, producer);
            expect(tester.widget<TextField>(producer).enabled, isTrue);
            await _reveal(tester, find.text('Choose label'));
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Choose label'),
                  )
                  .onPressed,
              isNotNull,
            );
            await tester.tap(find.widgetWithText(TextButton, 'Save'));
          }
          await tester.runAsync(
            () => journal
                .watchAll()
                .firstWhere((rows) => rows.isNotEmpty)
                .timeout(const Duration(seconds: 10)),
          );
          await tester.pumpAndSettle();
          final saved = (await tester.runAsync(() => journal.entries()))!
              .single;
          expect(
            (
              saved.producerName,
              saved.vintage,
              saved.isNonVintage,
              saved.abvPercent,
            ),
            ('Snapshot Estate', 2019, false, 13.5),
          );
          final photos = JournalPhotoStore(db);
          final metadata = (await tester.runAsync(
            () => photos.watchForEntry(saved.id).first,
          ))!;
          expect(metadata.map((row) => row.kind), [PhotoKind.glass]);
          expect(
            await tester.runAsync(() => photos.read(metadata.single.key)),
            orderedEquals(original),
          );
          expect(await recovery.pending(), isEmpty);
          expect(saved.tastedOn, journal.capturedDraft.tastedOn);
          expect(saved.rating, isNull);
          expect(storage.discards, 1);
          expect(journal.calls, failFirst ? 2 : 1);
          expect(tester.takeException(), isNull);
        } finally {
          if (!journal.release.isCompleted) journal.release.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          debugDefaultTargetPlatformOverride = platform;
          tester.view.reset();
          await tester.runAsync(
            () => db.close().timeout(const Duration(seconds: 10)),
          );
        }
      },
    );
  }
}
