import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/journal_photo_store.dart';
import 'package:sommelier/core/journal/wine_journal.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late WineJournal journal;
  late JournalPhotoStore photos;

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    db = openTestDatabase();
    journal = WineJournal(db, clock: time.clock, random: Random(2));
    photos = JournalPhotoStore(db, clock: time.clock, random: Random(3));
  });
  tearDown(() => db.close());

  Uint8List png({String? privateText}) {
    final photo = image.Image(width: 2, height: 2);
    if (privateText != null) {
      photo.textData = {'Comment': privateText};
    }
    return image.encodePng(photo);
  }

  test(
    'stores only private bytes and watches metadata, replacing by kind',
    () async {
      final entry = await journal.create(
        const JournalDraft(producerName: 'Example'),
      );
      final photo = await photos.put(
        entryId: entry.id,
        kind: PhotoKind.label,
        bytes: png(privateText: 'PRIVATE_GPS_LOCATION'),
      );
      expect(photo.key, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(photo.mimeType, 'image/png');
      final stored = (await photos.read(photo.key))!;
      expect(image.decodePng(stored)!.textData ?? {}, isEmpty);
      expect(
        String.fromCharCodes(stored),
        isNot(contains('PRIVATE_GPS_LOCATION')),
      );
      final listed = await photos.watchForEntry(entry.id).first;
      expect(listed, hasLength(1));
      expect(listed.single.key, photo.key);
      expect(listed.single.kind, PhotoKind.label);

      time.advance(const Duration(minutes: 1));
      final replacement = await photos.put(
        entryId: entry.id,
        kind: PhotoKind.label,
        bytes: png(),
      );
      expect(replacement.key, photo.key);
      expect(replacement.createdAt.isAfter(photo.createdAt), isTrue);
      expect(await db.select(db.wineJournalPhotos).get(), hasLength(1));

      final glass = await photos.put(
        entryId: entry.id,
        kind: PhotoKind.glass,
        bytes: png(),
      );
      expect(glass.key, isNot(photo.key));
      expect(await photos.watchForEntry(entry.id).first, hasLength(2));
      await photos.delete(photo.key);
      expect(await photos.read(photo.key), isNull);
      expect(await photos.read(glass.key), isNotNull);
    },
  );

  test('bakes JPEG orientation and removes all EXIF before storage', () async {
    final entry = await journal.create(
      const JournalDraft(producerName: 'Example'),
    );
    final source = image.Image(width: 2, height: 1);
    source.exif.imageIfd.orientation = 6;
    final saved = await photos.put(
      entryId: entry.id,
      kind: PhotoKind.label,
      bytes: image.encodeJpg(source),
    );
    final clean = image.decodeJpg((await photos.read(saved.key))!)!;
    expect((clean.width, clean.height), (1, 2));
    expect(clean.exif.isEmpty, isTrue);
    expect(clean.textData ?? {}, isEmpty);
  });

  test(
    'resizes and strips a desktop import larger than the stored byte cap',
    () {
      final source = image.Image(width: 4000, height: 1);
      final privateBytes = Uint8List(JournalPhotoStore.maxBytes + 1024)
        ..fillRange(0, JournalPhotoStore.maxBytes + 1024, 65);
      source.textData = {'Comment': String.fromCharCodes(privateBytes)};
      final raw = image.encodePng(source);
      expect(raw.length, greaterThan(JournalPhotoStore.maxBytes));

      final clean = JournalPhotoStore.sanitize(raw);
      expect(clean.length, lessThanOrEqualTo(JournalPhotoStore.maxBytes));
      final result = image.decodePng(clean)!;
      expect((result.width, result.height), (3000, 1));
      expect(result.textData ?? {}, isEmpty);
    },
  );

  test('bad inputs leave the previous photo intact', () async {
    final entry = await journal.create(
      const JournalDraft(producerName: 'Example'),
    );
    final saved = await photos.put(
      entryId: entry.id,
      kind: PhotoKind.label,
      bytes: png(),
    );
    final before = await photos.read(saved.key);
    for (final bytes in [
      Uint8List.fromList([1, 2, 3]),
      Uint8List(JournalPhotoStore.maxBytes + 1),
    ]) {
      await expectLater(
        photos.put(entryId: entry.id, kind: PhotoKind.label, bytes: bytes),
        throwsA(isA<PhotoStoreException>()),
      );
    }
    expect(await photos.read(saved.key), before);
    expect(await db.select(db.wineJournalPhotos).get(), hasLength(1));
  });

  test('journal and two photos share one caller-owned transaction', () async {
    final cleanLabel = JournalPhotoStore.sanitize(png());
    final cleanGlass = JournalPhotoStore.sanitize(png());
    await expectLater(
      db.transaction(() async {
        final entry = await journal.createInTransaction(
          const JournalDraft(producerName: 'Rolled back'),
        );
        await photos.putBatchInTransaction(
          entryId: entry.id,
          photos: {PhotoKind.label: cleanLabel, PhotoKind.glass: cleanGlass},
          alreadySanitized: true,
        );
        throw StateError('Cancel this save');
      }),
      throwsStateError,
    );
    expect(await db.select(db.wineJournalEntries).get(), isEmpty);
    expect(await db.select(db.wineJournalPhotos).get(), isEmpty);

    final saved = await db.transaction(() async {
      final entry = await journal.createInTransaction(
        const JournalDraft(producerName: 'Saved'),
      );
      final both = await photos.putBatchInTransaction(
        entryId: entry.id,
        photos: {PhotoKind.label: cleanLabel, PhotoKind.glass: cleanGlass},
        alreadySanitized: true,
      );
      return (entry, both);
    });
    expect(saved.$2.keys.toSet(), {PhotoKind.label, PhotoKind.glass});
    expect(await db.select(db.wineJournalEntries).get(), hasLength(1));
    expect(await db.select(db.wineJournalPhotos).get(), hasLength(2));
  });

  test(
    'journal save facade commits or rolls back photo changes together',
    () async {
      await expectLater(
        journal.saveWithPhotos(
          const JournalDraft(producerName: 'Do not keep'),
          photos: {
            PhotoKind.label: Uint8List.fromList([1, 2, 3]),
          },
        ),
        throwsA(isA<PhotoStoreException>()),
      );
      expect(await db.select(db.wineJournalEntries).get(), isEmpty);

      final clean = JournalPhotoStore.sanitize(png());
      final entry = await journal.saveWithPhotos(
        const JournalDraft(producerName: 'Keep'),
        photos: {PhotoKind.label: clean, PhotoKind.glass: clean},
      );
      expect(await photos.watchForEntry(entry.id).first, hasLength(2));

      await journal.saveWithPhotos(
        const JournalDraft(producerName: 'Keep edited'),
        id: entry.id,
        removedKinds: {PhotoKind.label},
      );
      expect((await journal.entry(entry.id))!.producerName, 'Keep edited');
      final remaining = await photos.watchForEntry(entry.id).first;
      expect(remaining.map((photo) => photo.kind), [PhotoKind.glass]);
    },
  );

  test('a journal deletion cascades to both private photos', () async {
    final entry = await journal.create(
      const JournalDraft(producerName: 'Example'),
    );
    final label = await photos.put(
      entryId: entry.id,
      kind: PhotoKind.label,
      bytes: png(),
    );
    final glass = await photos.put(
      entryId: entry.id,
      kind: PhotoKind.glass,
      bytes: png(),
    );
    await journal.delete(entry.id);
    expect(await photos.read(label.key), isNull);
    expect(await photos.read(glass.key), isNull);
    expect(await db.select(db.wineJournalPhotos).get(), isEmpty);
  });
}
