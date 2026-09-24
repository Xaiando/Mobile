import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/fixture.dart';

/// The guarantees of the canonical domain model (docs/domain-model.md §6).
Matcher get rejected => throwsA(isA<SqliteException>());

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
  });
  tearDown(() => db.close());

  group('immutable curriculum', () {
    test('rejects insert, update and delete outside the write lock', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO node_types VALUES ('vessel', 'vessel')",
        ),
        rejected,
      );
      await expectLater(
        db.customStatement(
          "UPDATE knowledge_nodes SET name = 'X' WHERE id = 'n_geo_france'",
        ),
        rejected,
      );
      await expectLater(
        db.customStatement('DELETE FROM question_distractors'),
        rejected,
      );
    });

    test(
      'control: the same statements succeed inside the write lock',
      () async {
        await db.writeCurriculum(
          () => runSql(db, [
            "INSERT INTO node_types VALUES ('vessel', 'vessel')",
            "UPDATE knowledge_nodes SET name = 'X' WHERE id = 'n_geo_france'",
            'DELETE FROM question_distractors',
          ]),
        );
        expect(await db.select(db.questionDistractors).get(), isEmpty);
      },
    );

    test('seed loads through the write lock', () async {
      expect(await db.select(db.knowledgeNodes).get(), hasLength(16));
      expect(await db.select(db.knowledgeRelations).get(), hasLength(13));
      expect(await db.select(db.knowledgeItems).get(), hasLength(3));
    });

    test('a relation must connect existing nodes (§S.1)', () async {
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            'INSERT INTO knowledge_relations VALUES '
            "('n_geo_chablis', 'LOCATED_IN', 'n_geo_nowhere', '1900-01-01', NULL)",
          ),
        ),
        rejected,
      );
    });

    test('an item cannot be its own prerequisite (§S.2)', () async {
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            'INSERT INTO knowledge_item_prerequisites VALUES '
            "('ki_chablis_grape', 'ki_chablis_grape')",
          ),
        ),
        rejected,
      );
    });

    test('an item must assert an existing relation', () async {
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            'INSERT INTO knowledge_items (id, subject_id, relation_type, '
            'object_id, domain_id, assertion_text, last_verified_at) VALUES '
            "('ki_bad', 'n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', "
            "'n_grape_nebbiolo', 'geography', 'x', '2026-09-24T00:00:00.000Z')",
          ),
        ),
        rejected,
      );
    });

    test('quantity values attach only to quantity nodes', () async {
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            'INSERT INTO quantity_values (knowledge_node_id, minimum, unit) '
            "VALUES ('n_grape_chardonnay', 1, 'month')",
          ),
        ),
        rejected,
      );
    });

    test("a question's template must match the item's relation type", () async {
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            "INSERT INTO questions VALUES ('ki_chablis_soil', "
            "'qt_ppg_fwd_mcq', 'HAS_SOIL', 'x')",
          ),
        ),
        rejected,
      );
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            "INSERT INTO questions VALUES ('ki_chablis_soil', "
            "'qt_ppg_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'x')",
          ),
        ),
        rejected,
      );
    });

    test('normalized names are unique per node type', () async {
      await expectLater(
        db.writeCurriculum(
          () => db.customStatement(
            'INSERT INTO knowledge_nodes (id, node_type, name, name_norm) '
            "VALUES ('n_geo_chablis_2', 'appellation', 'CHABLIS', 'chablis')",
          ),
        ),
        rejected,
      );
    });

    test('dates must be canonical YYYY-MM-DD', () async {
      for (final bad in ['2026-13-01', '2026-1-5', '2026/01/05']) {
        await expectLater(
          db.writeCurriculum(
            () => db.customStatement(
              "UPDATE knowledge_relations SET valid_until = '$bad' "
              "WHERE subject_id = 'n_geo_barolo' AND relation_type = 'MIN_AGEING'",
            ),
          ),
          rejected,
          reason: bad,
        );
      }
    });

    test('generated questions rebuild without touching user history', () async {
      await db
          .into(db.reviewEvents)
          .insert(
            _event(
              'ki_chablis_grape',
              'qt_ppg_fwd_mcq',
              t0,
              3,
              t0.add(const Duration(minutes: 10)),
            ),
          );
      await db.writeCurriculum(() async {
        await db.customStatement('DELETE FROM questions');
        expect(
          await db.select(db.questionDistractors).get(),
          isEmpty,
          reason: 'distractors cascade with their question',
        );
        await runSql(db, generatedQuestionSeed);
      });
      expect(await db.select(db.reviewEvents).get(), hasLength(1));
      expect(await db.select(db.questionDistractors).get(), hasLength(3));
    });
  });

  group('mutable user data', () {
    test('is writable while the curriculum is locked', () async {
      await db.into(db.wineJournalEntries).insert(_journal(_uuid(1)));
      expect(await db.select(db.wineJournalEntries).get(), hasLength(1));
    });

    test('timestamps must be UTC with millisecond precision', () async {
      final ok = DateTime.utc(2026, 3, 4, 5, 6, 7, 890);
      await db.into(db.wineJournalEntries).insert(_journal(_uuid(1), at: ok));
      final raw = await db
          .customSelect('SELECT created_at FROM wine_journal_entries')
          .getSingle();
      expect(raw.read<String>('created_at'), '2026-03-04T05:06:07.890Z');

      final micro = DateTime.utc(2026, 3, 4, 5, 6, 7, 890, 123);
      await expectLater(
        db.into(db.wineJournalEntries).insert(_journal(_uuid(2), at: micro)),
        rejected,
      );
      final local = DateTime(2026, 3, 4, 5, 6, 7, 890);
      await expectLater(
        db.into(db.wineJournalEntries).insert(_journal(_uuid(3), at: local)),
        rejected,
      );
    });

    test('review state invariants', () async {
      Future<void> bad(ReviewStatesCompanion row) =>
          expectLater(db.into(db.reviewStates).insert(row), rejected);
      final valid = ReviewStatesCompanion.insert(
        knowledgeItemId: 'ki_chablis_grape',
        state: 2,
        stability: 3,
        difficulty: 5,
        due: t0.add(const Duration(days: 3)),
        lastReview: t0,
        reps: 2,
      );
      await bad(valid.copyWith(step: const Value(0))); // Review has no step.
      await bad(
        valid.copyWith(state: const Value(1)),
      ); // Learning needs a step.
      await bad(valid.copyWith(lapses: const Value(2))); // lapses < reps.
      await bad(valid.copyWith(due: Value(t0))); // due after last review.
      await bad(valid.copyWith(knowledgeItemId: const Value('ki_missing')));
      await db.into(db.reviewStates).insert(valid);
    });

    test('review log is append-only', () async {
      final event = _event(
        'ki_chablis_grape',
        'qt_ppg_fwd_mcq',
        t0,
        3,
        t0.add(const Duration(minutes: 10)),
      );
      await db.into(db.reviewEvents).insert(event);
      await db
          .into(db.reviewEventOptions)
          .insert(
            ReviewEventOptionsCompanion.insert(
              reviewEventId: event.id.value,
              position: 1,
              knowledgeNodeId: 'n_grape_chardonnay',
            ),
          );
      await expectLater(
        db.customStatement('UPDATE review_events SET rating = 4'),
        rejected,
      );
      await expectLater(
        db.customStatement('DELETE FROM review_events'),
        rejected,
      );
      await expectLater(
        db.customStatement('DELETE FROM review_event_options'),
        rejected,
      );
    });

    test(
      'tasting descriptors: own vocabulary only, single-select enforced',
      () async {
        final session = _uuid(1);
        await db
            .into(db.tastingSessions)
            .insert(
              TastingSessionsCompanion.insert(
                id: session,
                tastingGridId: 'tg_wset_sat_l3',
                startedAt: t0,
              ),
            );
        TastingDescriptorsCompanion descriptor(
          String grid,
          String attribute,
          String value,
        ) => TastingDescriptorsCompanion.insert(
          tastingSessionId: session,
          tastingGridId: grid,
          attributeKey: attribute,
          valueKey: value,
        );
        await db
            .into(db.tastingDescriptors)
            .insert(descriptor('tg_wset_sat_l3', 'sweetness', 'dry'));
        await expectLater(
          db
              .into(db.tastingDescriptors)
              .insert(descriptor('tg_wset_sat_l3', 'sweetness', 'off_dry')),
          rejected,
          reason: 'single-selection attribute',
        );
        await expectLater(
          db
              .into(db.tastingDescriptors)
              .insert(
                descriptor('tg_cms_dtm_certified', 'fruit_condition', 'tart'),
              ),
          rejected,
          reason: 'DTM term in a SAT session',
        );
        await db
            .into(db.tastingDescriptors)
            .insert(descriptor('tg_wset_sat_l3', 'primary_aromas', 'lemon'));
        await db
            .into(db.tastingDescriptors)
            .insert(
              descriptor('tg_wset_sat_l3', 'primary_aromas', 'green_apple'),
            );
        expect(await db.select(db.tastingDescriptors).get(), hasLength(3));
      },
    );

    test(
      'journal rules: NV excludes vintage; delete cascades and detaches',
      () async {
        await expectLater(
          db
              .into(db.wineJournalEntries)
              .insert(
                _journal(_uuid(1)).copyWith(
                  isNonVintage: const Value(true),
                  vintage: const Value(2019),
                ),
              ),
          rejected,
        );
        final entry = _uuid(2);
        await db.into(db.wineJournalEntries).insert(_journal(entry));
        await db
            .into(db.wineJournalEntryNodes)
            .insert(
              WineJournalEntryNodesCompanion.insert(
                wineJournalEntryId: entry,
                knowledgeNodeId: 'n_geo_barolo',
              ),
            );
        await db
            .into(db.tastingSessions)
            .insert(
              TastingSessionsCompanion.insert(
                id: _uuid(3),
                tastingGridId: 'tg_wset_sat_l3',
                wineJournalEntryId: Value(entry),
                startedAt: t0,
              ),
            );
        await (db.delete(
          db.wineJournalEntries,
        )..where((e) => e.id.equals(entry))).go();
        expect(await db.select(db.wineJournalEntryNodes).get(), isEmpty);
        final session = await db.select(db.tastingSessions).getSingle();
        expect(session.wineJournalEntryId, isNull);
      },
    );

    test('scheduler config stores exactly 21 FSRS weights', () async {
      await expectLater(
        db
            .into(db.schedulerConfigs)
            .insert(
              SchedulerConfigsCompanion.insert(
                version: const Value(2),
                weights:
                    '[${fsrs.defaultParameters.sublist(0, 20).join(', ')}]',
                desiredRetention: 0.9,
                learningStepsSeconds: '[]',
                relearningStepsSeconds: '[]',
                maximumIntervalDays: 36500,
                enableFuzzing: true,
                createdAt: t0,
              ),
            ),
        rejected,
      );
    });

    test('FSRS reviews: the log is the source, review_states its projection', () async {
      final scheduler = fsrs.Scheduler(enableFuzzing: false);
      var card = fsrs.Card(cardId: 0, due: t0);
      var at = t0;
      var reps = 0, lapses = 0;
      for (final rating in [
        fsrs.Rating.good,
        fsrs.Rating.good,
        fsrs.Rating.again,
        fsrs.Rating.good,
      ]) {
        final wasReview = card.state == fsrs.State.review;
        card = scheduler.reviewCard(card, rating, reviewDateTime: at).card;
        reps++;
        if (wasReview && rating == fsrs.Rating.again) lapses++;
        await db.transaction(() async {
          await db
              .into(db.reviewEvents)
              .insert(
                ReviewEventsCompanion.insert(
                  id: _uuid(100 + reps),
                  knowledgeItemId: 'ki_chablis_grape',
                  questionTemplateId: 'qt_ppg_fwd_mcq',
                  reviewedAt: at,
                  rating: rating.value,
                  schedulerConfigVersion: 1,
                  stateAfter: card.state.value,
                  stepAfter: Value(card.step),
                  stabilityAfter: card.stability!,
                  difficultyAfter: card.difficulty!,
                  dueAfter: card.due,
                ),
              );
          await db
              .into(db.reviewStates)
              .insertOnConflictUpdate(
                ReviewStatesCompanion.insert(
                  knowledgeItemId: 'ki_chablis_grape',
                  state: card.state.value,
                  step: Value(card.step),
                  stability: card.stability!,
                  difficulty: card.difficulty!,
                  due: card.due,
                  lastReview: at,
                  reps: reps,
                  lapses: Value(lapses),
                ),
              );
        });
        at = card.due;
      }
      // The projection equals a replay of the log: latest after-state + counts.
      final replay = await db.customSelect('''
        SELECT e.state_after, e.stability_after, e.due_after,
               (SELECT count(*) FROM review_events x
                 WHERE x.knowledge_item_id = e.knowledge_item_id) AS reps
        FROM review_events e
        WHERE e.knowledge_item_id = 'ki_chablis_grape'
        ORDER BY e.reviewed_at DESC LIMIT 1''').getSingle();
      final state = await db.select(db.reviewStates).getSingle();
      expect(replay.read<int>('state_after'), state.state);
      expect(replay.read<double>('stability_after'), state.stability);
      expect(DateTime.parse(replay.read<String>('due_after')), state.due);
      expect(replay.read<int>('reps'), state.reps);
      expect(state.lapses, 1);
    });
  });
}

/// A syntactically valid UUID for test rows.
String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

ReviewEventsCompanion _event(
  String item,
  String template,
  DateTime at,
  int rating,
  DateTime due,
) => ReviewEventsCompanion.insert(
  id: _uuid(at.millisecondsSinceEpoch % 100000 + rating),
  knowledgeItemId: item,
  questionTemplateId: template,
  reviewedAt: at,
  rating: rating,
  schedulerConfigVersion: 1,
  stateAfter: 1,
  stepAfter: const Value(1),
  stabilityAfter: 2.3,
  difficultyAfter: 5,
  dueAfter: due,
);

WineJournalEntriesCompanion _journal(String id, {DateTime? at}) =>
    WineJournalEntriesCompanion.insert(
      id: id,
      producerName: const Value('Example Producer'),
      vintage: const Value(2019),
      createdAt: at ?? t0,
      updatedAt: at ?? t0,
    );
