import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late TastingPractice tasting;

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9, 30, 15, 123, 456));
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    tasting = TastingPractice(db, clock: time.clock, random: Random(1));
  });
  tearDown(() => db.close());

  /// Answers every required attribute of [session] with its first value.
  Future<void> answerRequired(TastingSession session) async {
    final grid = await tasting.layout(session.tastingGridId);
    for (final attribute in grid.attributes) {
      if (attribute.attribute.isRequired) {
        await tasting.choose(session.id, attribute.key, {
          attribute.values.first.valueKey,
        });
      }
    }
  }

  test('each track tastes with its own grid (T1)', () async {
    expect(await tasting.gridFor('WSET_L3'), 'tg_structured');
    expect(await tasting.gridFor('CMS_CERTIFIED'), 'tg_deductive');
    expect(
      [for (final g in await tasting.grids()) g.id],
      ['tg_deductive', 'tg_structured'],
    );

    final structured = await tasting.layout('tg_structured');
    expect(structured.sections, ['Look', 'Smell', 'Taste', 'Judge']);
    expect(structured.attributes.first.key, 'clarity');
    expect(
      [for (final v in structured.inSection('Taste')[1].values) v.label],
      ['Very low', 'Low', 'Moderate', 'High', 'Very high'],
      reason: 'values come in scale order',
    );
    final deductive = await tasting.layout('tg_deductive');
    expect(deductive.sections, ['Sight', 'Nose', 'Palate', 'Conclusions']);
  });

  test('starts a blind session with a UTC millisecond timestamp', () async {
    final session = await tasting.start('tg_structured');
    expect(session.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(session.isBlind, isTrue);
    expect(session.startedAt, DateTime.utc(2026, 10, 1, 9, 30, 15, 123));
    expect(session.completedAt, isNull);
    expect(await tasting.answers(session.id), isEmpty);
  });

  test('saves answers as they are chosen, and replaces them', () async {
    final session = await tasting.start('tg_structured');
    await tasting.choose(session.id, 'acidity', {'high'});
    await tasting.choose(session.id, 'aromas', {'citrus', 'floral'});
    await tasting.choose(session.id, 'acidity', {'very_high'});
    expect(await tasting.answers(session.id), {
      'acidity': {'very_high'},
      'aromas': {'citrus', 'floral'},
    });

    await tasting.choose(session.id, 'aromas', {});
    expect(await tasting.answers(session.id), {
      'acidity': {'very_high'},
    });
  });

  test('refuses a second value for a single choice, and keeps the first', () {
    return expectLater(() async {
      final session = await tasting.start('tg_structured');
      await tasting.choose(session.id, 'acidity', {'high'});
      try {
        await tasting.choose(session.id, 'acidity', {'high', 'low'});
      } finally {
        expect(await tasting.answers(session.id), {
          'acidity': {'high'},
        });
      }
    }(), throwsA(isA<SqliteException>()));
  });

  test('refuses the vocabulary of another grid (TASK-008)', () async {
    final session = await tasting.start('tg_structured');
    await expectLater(
      tasting.choose(session.id, 'fruit_state', {'ripe'}),
      throwsA(isA<SqliteException>()),
    );
    await expectLater(
      tasting.choose(session.id, 'acidity', {'moderate_plus'}),
      throwsA(isA<SqliteException>()),
    );
    expect(await tasting.answers(session.id), isEmpty);
  });

  test('completes a session only when every required answer is in', () async {
    final session = await tasting.start('tg_deductive', isBlind: false);
    await tasting.choose(session.id, 'clarity', {'clear'});

    final missing = await tasting.complete(session.id);
    expect(missing.first.key, 'brightness');
    expect(
      [for (final a in missing) a.key],
      isNot(contains('fruit')),
      reason: 'a multiple choice is optional',
    );
    expect((await tasting.watchSession(session.id).first)!.completedAt, isNull);

    await answerRequired(session);
    time.advance(const Duration(minutes: 12));
    expect(await tasting.complete(session.id), isEmpty);
    final done = (await tasting.watchSession(session.id).first)!;
    expect(done.completedAt, DateTime.utc(2026, 10, 1, 9, 42, 15, 123));
    expect(done.isBlind, isFalse);
  });

  test('keeps notes, and lists the newest session first', () async {
    final first = await tasting.start('tg_structured');
    time.advance(const Duration(days: 1));
    final second = await tasting.start('tg_deductive');
    await tasting.setNotes(first.id, '  Chalky, taut.  ');
    await tasting.setNotes(second.id, '   ');

    final sessions = await tasting.watchSessions().first;
    expect([for (final s in sessions) s.id], [second.id, first.id]);
    expect(sessions.last.notes, 'Chalky, taut.');
    expect(sessions.first.notes, isNull, reason: 'blank notes are NULL');
  });

  test('links a wine from the journal, which may later leave', () async {
    final journal = WineJournal(db, clock: time.clock, random: Random(2));
    final wine = await journal.create(
      const JournalDraft(appellationText: 'Chablis'),
    );
    final session = await tasting.start(
      'tg_structured',
      journalEntryId: wine.id,
    );
    expect(session.wineJournalEntryId, wine.id);

    await journal.delete(wine.id);
    expect(
      (await tasting.watchSession(session.id).first)!.wineJournalEntryId,
      isNull,
    );

    final other = await journal.create(
      const JournalDraft(appellationText: 'Barolo'),
    );
    await tasting.linkWine(session.id, other.id);
    expect(
      (await tasting.watchSession(session.id).first)!.wineJournalEntryId,
      other.id,
    );
  });

  test('deletes a session with its answers', () async {
    final session = await tasting.start('tg_structured');
    await answerRequired(session);
    await tasting.delete(session.id);
    expect(await tasting.watchSessions().first, isEmpty);
    expect(await db.select(db.tastingDescriptors).get(), isEmpty);
  });

  test('answers stream as they change', () async {
    final session = await tasting.start('tg_structured');
    final seen = tasting.watchAnswers(session.id).take(2).toList();
    await tasting.choose(session.id, 'clarity', {'bright'});
    expect(await seen, [
      <String, Set<String>>{},
      {
        'clarity': {'bright'},
      },
    ]);
    // An unrelated write elsewhere does not disturb the answers.
    await (db.update(db.tastingSessions))
        .write(const TastingSessionsCompanion(notes: Value('x')));
  });
}
