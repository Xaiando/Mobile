import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/audio/audio_notes_providers.dart';
import 'package:sommelier/core/audio/tasting_audio.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/export/portable_files_providers.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/features/tasting/audio_notes_panel.dart';
import 'package:sommelier/features/settings/review_export_button.dart';

import '../core/audio/tasting_audio_export_test.dart' show wavFixture;
import '../support/fixture.dart';

class FakeDevice implements AudioNotesDevice {
  final ended = StreamController<void>.broadcast();
  bool denied = false, paused = false, played = false, stopped = false;
  @override
  Future<int> start() async {
    if (denied) throw StateError('Microphone permission denied');
    return 7200;
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<CapturedAudio> stop() async =>
      CapturedAudio(wavFixture(), 'audio/wav', 1000);
  @override
  Future<void> cancel() async {}
  @override
  Future<void> play(Uint8List bytes, String mimeType) async {
    played = true;
  }

  @override
  Future<void> stopPlayback() async {
    stopped = true;
  }

  @override
  Stream<void> get playbackEnded => ended.stream;
  @override
  Future<void> dispose() async {
    await ended.close();
  }
}

class FakeFiles implements PortableFiles {
  String? name, mime;
  Uint8List? bytes;
  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    this.name = name;
    this.bytes = bytes;
    mime = mimeType;
    return true;
  }
}

void main() {
  // Keep all exact persistence, playback and byte comparisons unchanged.
  Future<void> tapAsync(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'record, pause, resume, persist, play and download at phone width',
    (tester) async {
      final db = (await tester.runAsync(() async {
        final database = openTestDatabase();
        await seedCurriculum(database);
        return database;
      }))!;
      final session = (await tester.runAsync(
        () => TastingPractice(db).start('tg_wset_sat_l3'),
      ))!;
      addTearDown(db.close);
      debugPrint('AUDIO_UI_STAGE database-ready');
      final device = FakeDevice();
      final files = FakeFiles();
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            audioNotesDeviceFactoryProvider.overrideWithValue(() => device),
            portableFilesProvider.overrideWithValue(files),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AudioNotesPanel(sessionId: session.id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lecture tasting');
      debugPrint('AUDIO_UI_STAGE panel-ready');
      await tester.tap(find.text('Record audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(device.paused, isTrue);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(device.paused, isFalse);
      await tapAsync(tester, find.text('Stop and save'));
      await tester.pumpAndSettle();
      debugPrint('AUDIO_UI_STAGE capture-saved');
      expect(
        ((await tester.runAsync(
          () => TastingAudioStore(db).watch(session.id).first,
        ))!).single.title,
        'Lecture tasting',
      );
      debugPrint('AUDIO_UI_STAGE persistence-checked');
      await tester.ensureVisible(find.byTooltip('Play recording'));
      await tapAsync(tester, find.byTooltip('Play recording'));
      await tester.pumpAndSettle();
      expect(device.played, isTrue);
      device.ended.add(null);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play recording'), findsOneWidget);
      await tapAsync(tester, find.byTooltip('Download recording'));
      await tester.pumpAndSettle();
      expect(files.bytes, wavFixture());
      expect(files.name, endsWith('.wav'));
      expect(files.mime, 'audio/wav');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
  testWidgets('permission denial does not invent a recording', (tester) async {
    final db = (await tester.runAsync(() async {
      final database = openTestDatabase();
      await seedCurriculum(database);
      return database;
    }))!;
    final session = (await tester.runAsync(
      () => TastingPractice(db).start('tg_wset_sat_l3'),
    ))!;
    final device = FakeDevice()..denied = true;
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioNotesDeviceFactoryProvider.overrideWithValue(() => device),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AudioNotesPanel(sessionId: session.id),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Microphone permission denied'), findsOneWidget);
    expect(
      (await tester.runAsync(
        () => TastingAudioStore(db).watch(session.id).first,
      ))!,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('failed save preserves audio for retry or download', (
    tester,
  ) async {
    final db = (await tester.runAsync(() async {
      final database = openTestDatabase();
      await seedCurriculum(database);
      return database;
    }))!;
    final device = FakeDevice();
    final files = FakeFiles();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioNotesDeviceFactoryProvider.overrideWithValue(() => device),
          portableFilesProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AudioNotesPanel(
                sessionId: '00000000-0000-4000-8000-000000000000',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await tester.pumpAndSettle();
    await tapAsync(tester, find.text('Stop and save'));
    await tester.pumpAndSettle();
    expect(find.text('Retry saving'), findsOneWidget);
    await tapAsync(tester, find.text('Download unsaved audio'));
    await tester.pumpAndSettle();
    expect(files.bytes, wavFixture());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets(
    'review export confirms scope and leaves audio unchecked by default',
    (tester) async {
      final db = (await tester.runAsync(() async {
        final database = openTestDatabase();
        await seedCurriculum(database);
        return database;
      }))!;
      final files = FakeFiles();
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            portableFilesProvider.overrideWithValue(files),
          ],
          child: const MaterialApp(home: Scaffold(body: ReviewExportButton())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download test results for review'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tapAsync(tester, find.text('Download ZIP'));
      await tester.pumpAndSettle();
      expect(files.name, endsWith('.zip'));
      expect(files.mime, 'application/zip');
      expect(files.bytes!.take(2), [0x50, 0x4b]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
