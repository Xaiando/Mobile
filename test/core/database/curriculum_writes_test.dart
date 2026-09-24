import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> insertNodeType(String id) =>
      db.customStatement("INSERT INTO node_types VALUES ('$id', '$id')");

  test('unlocks the curriculum only for the duration of the call', () async {
    await db.writeCurriculum(() => insertNodeType('grape'));
    expect(await db.select(db.curriculumIngestions).get(), isEmpty);
    await expectLater(insertNodeType('soil'), throwsA(isA<SqliteException>()));
  });

  test(
    'a failure rolls back the writes and leaves the curriculum locked',
    () async {
      await expectLater(
        db.writeCurriculum(() async {
          await insertNodeType('grape');
          throw StateError('validation failed');
        }),
        throwsStateError,
      );
      expect(await db.select(db.nodeTypes).get(), isEmpty);
      expect(await db.select(db.curriculumIngestions).get(), isEmpty);
    },
  );

  test('a nested call reuses the outer lock', () async {
    await db.writeCurriculum(() async {
      await insertNodeType('grape');
      await db.writeCurriculum(() => insertNodeType('soil'));
      await insertNodeType('climate');
    });
    expect(await db.select(db.nodeTypes).get(), hasLength(3));
    expect(await db.select(db.curriculumIngestions).get(), isEmpty);
  });

  test('records the start time in storage form (UTC, milliseconds)', () async {
    final fixed = Clock.fixed(DateTime.utc(2026, 5, 6, 7, 8, 9, 123, 456));
    late DateTime startedAt;
    await db.writeCurriculum(() async {
      startedAt =
          (await db.select(db.curriculumIngestions).getSingle()).startedAt;
    }, clock: fixed);
    expect(startedAt, DateTime.utc(2026, 5, 6, 7, 8, 9, 123));
  });
}
