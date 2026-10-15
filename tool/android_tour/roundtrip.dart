// A backup that restores: the walk behind tool/android/data_roundtrip.sh.
//
// A learner moving to a new phone, or to a build signed with another key, has
// one way to keep the journal: Settings, Your data, export, then import. The
// walk saves a wine with a photo through the journal editor, exports through
// the real Your data screen, damages the data, imports the file, and checks
// that the wine and its photo are back. It then imports a file that is not a
// backup and checks that the data is untouched.
//
// Only the platform's file dialog is replaced, by memory (MemoryBackupFiles):
// the editor, the confirm dialogs, the JSON, the import and the messages are
// the app's own, on whatever runs the walk. Whether Samsung's file dialogs
// accept the export and offer the file for import is for the phone
// (docs/android-acceptance.md, rows G1 to G3).
//
// Two hosts run it, as for the screen tour: an Android emulator through
// `flutter drive` (tool/android_tour/roundtrip_test.dart) and the desktop test
// runner in the normal suite (test/tool/android_roundtrip_test.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sommelier/app/app.dart';
import 'package:sommelier/app/router.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
import 'package:sommelier/core/journal/journal_providers.dart';
import 'package:sommelier/features/settings/your_data.dart';

import 'tour.dart';

/// The file dialogs of [BackupFiles], replaced by memory: saving keeps the
/// bytes and opening hands them back.
class MemoryBackupFiles implements BackupFiles {
  List<int>? contents;
  String? name;
  int saves = 0;
  int opens = 0;

  @override
  Future<bool> save(String name, List<int> bytes) async {
    saves += 1;
    this.name = name;
    contents = List<int>.of(bytes);
    return true;
  }

  @override
  Future<List<int>?> open() async {
    opens += 1;
    return contents;
  }
}

const _producer = 'Round Trip Estate';
const _changed = 'Changed afterwards';

/// Runs the walk on the app that is showing, with [files] installed as its
/// backup files, and returns what went wrong.
Future<List<String>> roundTripYourData(
  WidgetTester tester,
  MemoryBackupFiles files,
) async {
  final problems = <String>[];
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SommelierApp)),
    listen: false,
  );
  final router = container.read(routerProvider);
  final db = container.read(appDatabaseProvider);

  void check(bool ok, String what) {
    if (!ok) problems.add(what);
  }

  /// Database work runs outside the test's fake clock, bounded.
  Future<T> onDevice<T>(Future<T> Function() work) async {
    final value = await tester.runAsync(
      () => work().timeout(const Duration(seconds: 30)),
    );
    await tester.pump(Duration.zero);
    return value as T;
  }

  Future<List<String?>> producers() async {
    final rows = await onDevice(
      () => db
          .customSelect('SELECT producer_name FROM wine_journal_entries')
          .get(),
    );
    return [for (final row in rows) row.read<String?>('producer_name')];
  }

  Future<int> photos() async {
    final rows = await onDevice(
      () => db
          .customSelect('SELECT COUNT(*) AS n FROM wine_journal_photos')
          .get(),
    );
    return rows.first.read<int>('n');
  }

  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      problems.add('$name: ${'$error'.split('\n').first}');
    }
    final exception = tester.takeException();
    if (exception != null) {
      problems.add('$name: ${'$exception'.split('\n').first}');
    }
  }

  Future<void> openSettingsRow(String title) async {
    router.go('/settings');
    await settle(tester);
    final row = find.text(title);
    await tester.scrollUntilVisible(row, 300);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await settle(tester);
  }

  Future<String> messageStartingWith(String start) async {
    final message = find.textContaining(start);
    final shown = await pumpUntilFound(
      tester,
      () => message.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    if (!shown) throw StateError('no message starting "$start"');
    return tester.widget<Text>(message.first).data ?? '';
  }

  await step('save a wine', () async {
    router.go('/cellar/new');
    await settle(tester);
    // The list that holds the form, found before anything is typed: its
    // state outlives the typing, and no other screen's list can be mistaken
    // for it.
    final producer = find.widgetWithText(TextField, 'Producer');
    final list = tester.state<ScrollableState>(
      find.ancestor(of: producer, matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(producer, _producer);
    // The soft keyboard slides in and shrinks the window; let that finish.
    await settle(tester);
    final save = find.widgetWithText(FilledButton, 'Save to journal');
    // The list builds only what is near the screen, so go to its end. Jumping
    // there builds the button without a gesture, which an emulator that is
    // dropping frames can lose. The end of a lazy list is an estimate that
    // improves as it builds, so jump until the button is there.
    for (var jump = 0; jump < 8 && save.evaluate().isEmpty; jump++) {
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (save.evaluate().isEmpty) {
      final seen = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .take(12)
          .join(' | ');
      throw StateError(
        'the editor showed no "Save to journal" button; it shows: $seen',
      );
    }
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    var saved = false;
    final started = DateTime.now();
    while (!saved && DateTime.now().difference(started).inSeconds < 30) {
      await tester.pump(const Duration(milliseconds: 300));
      saved = (await producers()).contains(_producer);
    }
    check(saved, 'the editor did not save the wine within 30 s');
    final id = (await onDevice(
      () => db.customSelect('SELECT id FROM wine_journal_entries').get(),
    )).first.read<String>('id');
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 16, height: 16)),
    );
    await onDevice(
      () => container
          .read(journalPhotoStoreProvider)
          .put(entryId: id, kind: PhotoKind.label, bytes: png),
    );
    check(await photos() == 1, 'the label photo was not stored');
  });

  await step('export', () async {
    await openSettingsRow('Export your data');
    await tester.tap(find.widgetWithText(FilledButton, 'Choose a location'));
    final reached = await pumpUntilFound(tester, () => files.saves > 0);
    check(reached, 'the export never reached the file dialog');
    await settle(tester);
    check(
      find.text('Your data is saved.').evaluate().isNotEmpty,
      'the export did not say "Your data is saved."',
    );
    final text = utf8.decode(files.contents ?? const <int>[]);
    check(text.contains(_producer), 'the exported file lacks the wine');
    check(
      (files.name ?? '').startsWith('sommelier-backup-'),
      'the exported file is named "${files.name}"',
    );
  });

  await step('lose the data', () async {
    await onDevice(
      () => db.customStatement(
        "UPDATE wine_journal_entries SET producer_name = '$_changed'",
      ),
    );
    await onDevice(() => db.customStatement('DELETE FROM wine_journal_photos'));
    check(
      (await producers()).contains(_changed) && await photos() == 0,
      'the data was not changed before the import',
    );
  });

  await step('import', () async {
    await openSettingsRow('Import a backup');
    await tester.tap(find.widgetWithText(FilledButton, 'Choose a file'));
    final shown = await messageStartingWith('Imported ');
    check(shown.contains('1 wine'), 'the import said: $shown');
    check(
      (await producers()).contains(_producer),
      'the wine did not come back',
    );
    check(await photos() == 1, 'the photo did not come back');
  });

  await step('refuse a file that is not a backup', () async {
    files.contents = utf8.encode('this is not a backup');
    final before = files.opens;
    await openSettingsRow('Import a backup');
    await tester.tap(find.widgetWithText(FilledButton, 'Choose a file'));
    final reached = await pumpUntilFound(tester, () => files.opens > before);
    check(reached, 'the second import never reached the file dialog');
    // The message names the fault; whatever it says, it does not say Imported.
    await pumpUntilFound(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    await settle(tester);
    check(
      find.textContaining('Imported ').evaluate().isEmpty,
      'a file that is not a backup was reported as imported',
    );
    check(
      (await producers()).contains(_producer) && await photos() == 1,
      'a refused import changed the data',
    );
  });

  return problems;
}
