import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/wine_journal.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late WineJournal journal;

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9, 30, 15, 123, 456));
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    journal = WineJournal(db, clock: time.clock, random: Random(1));
  });
  tearDown(() => db.close());

  const barolo = JournalDraft(
    tastedOn: '2026-09-20',
    producerName: 'Example Producer',
    cuveeName: '  ',
    vintage: 2019,
    appellationText: 'Barolo',
    grapesText: 'Nebbiolo',
    abvPercent: 14.5,
    rating: 4,
    tastingNotes: 'Tar and roses.',
  );

  test(
    'creates an entry with UTC millisecond timestamps and its links',
    () async {
      final entry = await journal.create(
        barolo,
        nodeIds: {'n_geo_barolo', 'n_grape_nebbiolo'},
      );
      expect(entry.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(entry.producerName, 'Example Producer');
      expect(entry.cuveeName, isNull, reason: 'blank text is stored as NULL');
      expect(entry.vintage, 2019);
      expect(entry.createdAt, DateTime.utc(2026, 10, 1, 9, 30, 15, 123));
      expect(entry.updatedAt, entry.createdAt);
      expect(await journal.linkedNodeIds(entry.id), {
        'n_geo_barolo',
        'n_grape_nebbiolo',
      });
    },
  );

  test(
    'refuses a draft the database would refuse, and writes nothing',
    () async {
      const drafts = {
        JournalDraft(): 'Name the wine',
        JournalDraft(producerName: 'X', vintage: 1700):
            'A vintage lies between',
        JournalDraft(producerName: 'X', vintage: 2019, isNonVintage: true):
            'A non-vintage wine has no vintage',
        JournalDraft(producerName: 'X', abvPercent: 0): 'Alcohol lies between',
        JournalDraft(producerName: 'X', rating: 6): 'A rating is from 1 to 5',
        JournalDraft(producerName: 'X', tastedOn: '2026-02-30'):
            'The tasting date is not a calendar date',
      };
      for (final MapEntry(key: draft, value: problem) in drafts.entries) {
        expect(draft.problems.join(' '), contains(problem));
        await expectLater(
          journal.create(draft),
          throwsA(isA<JournalDraftException>()),
        );
      }
      expect(await journal.watchAll().first, isEmpty);
    },
  );

  test(
    'updates fields and links, and deletes an entry with its links',
    () async {
      final entry = await journal.create(barolo, nodeIds: {'n_geo_barolo'});
      time.advance(const Duration(hours: 1));
      final updated = await journal.update(
        entry.id,
        const JournalDraft(producerName: 'Example Producer', rating: 5),
        nodeIds: {'n_grape_nebbiolo'},
      );
      expect(updated.rating, 5);
      expect(updated.appellationText, isNull);
      expect(updated.updatedAt, entry.createdAt.add(const Duration(hours: 1)));
      expect(await journal.linkedNodeIds(entry.id), {'n_grape_nebbiolo'});

      await journal.delete(entry.id);
      expect(await journal.entry(entry.id), isNull);
      expect(await journal.linkedNodeIds(entry.id), isEmpty);
    },
  );

  test('lists the most recently tasted first, undated entries last', () async {
    await journal.create(const JournalDraft(producerName: 'Undated'));
    await journal.create(
      const JournalDraft(producerName: 'Older', tastedOn: '2026-01-05'),
    );
    await journal.create(
      const JournalDraft(producerName: 'Newer', tastedOn: '2026-08-01'),
    );
    final names = [
      for (final entry in await journal.watchAll().first) entry.producerName,
    ];
    expect(names, ['Newer', 'Older', 'Undated']);
  });

  test('knows when the learner last met each linked node', () async {
    await journal.create(
      const JournalDraft(producerName: 'A', tastedOn: '2026-05-01'),
      nodeIds: {'n_geo_barolo'},
    );
    await journal.create(
      const JournalDraft(producerName: 'B', tastedOn: '2026-09-20'),
      nodeIds: {'n_geo_barolo', 'n_grape_nebbiolo'},
    );
    await journal.create(
      const JournalDraft(producerName: 'C'),
      nodeIds: {'n_geo_chablis'},
    );
    expect(await journal.lastMetByNode(), {
      'n_geo_barolo': '2026-09-20',
      'n_grape_nebbiolo': '2026-09-20',
      'n_geo_chablis': '2026-10-01',
    });
  });
}
