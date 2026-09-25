import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/wine_journal.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/priority.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

/// The journal factor J (audit A-5, backlog J2).
void main() {
  test('J is 1 without a wine, 2 on the day, and fades over τ', () {
    expect(journalFactor(null), 1);
    expect(journalFactor(0), 2);
    expect(journalFactor(30), closeTo(1 + exp(-1), 1e-12));
    expect(journalFactor(-3), 2, reason: 'a date ahead counts as today');
    expect(
      Priority.of(
        retrievability: 0.5,
        relevance: 1,
        lapses: 0,
        prerequisiteFactor: 1,
        journalFactor: 2,
      ).score,
      1.0,
    );
  });

  group('the queue', () {
    late AppDatabase db;
    late TestClock time;
    late StudyPlanner planner;

    setUp(() async {
      time = TestClock(DateTime.utc(2026, 10, 1, 9));
      db = openTestDatabase();
      await CurriculumIngester(
        db,
        clock: time.clock,
      ).ensureCurrent(bundledDataset());
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      planner = StudyPlanner(db, clock: time.clock);
    });
    tearDown(() => db.close());

    Future<List<String>> newOrder() async => [
      for (final card in (await planner.plan(
        sessionSize: 100,
        newItems: 100,
      ))!.cards)
        card.itemId,
    ];

    Future<void> logBarolo({String tastedOn = '2026-09-30'}) =>
        WineJournal(db, clock: time.clock).create(
          JournalDraft(producerName: 'A producer', tastedOn: tastedOn),
          nodeIds: {'n_geo_barolo'},
        );

    test('logging a Barolo brings its items forward (spec Phase 5)', () async {
      final before = await newOrder();
      final firstBefore = before.indexWhere((id) => id.startsWith('ki_barolo'));
      expect(firstBefore, greaterThan(0));

      await logBarolo();
      final after = await newOrder();
      expect(after.first, startsWith('ki_barolo'));
      // An item still waits for a new prerequisite of its own, so each
      // Barolo item moves forward or stays; none moves back.
      for (final id in before.where((id) => id.startsWith('ki_barolo'))) {
        expect(
          after.indexOf(id),
          lessThanOrEqualTo(before.indexOf(id)),
          reason: id,
        );
      }
      expect(
        after.toSet(),
        before.toSet(),
        reason: 'the same items, reordered',
      );
    });

    test(
      'a logged wine raises the priority of reviewed items about it',
      () async {
        final reviews = ReviewService(
          db,
          clock: time.clock,
          schedulerFactory: unfuzzedScheduler,
        );
        final presenter = QuestionPresenter(db);
        for (final item in ['ki_barolo_grape', 'ki_barbaresco_grape']) {
          final template = (await planner.cards('WSET_L3'))
              .singleWhere((c) => c.itemId == item)
              .formats
              .first;
          final shown = await presenter.present(
            item,
            template.questionTemplateId,
            seed: 1,
          );
          await (shown.isMultipleChoice
              ? reviews.answerMultipleChoice(shown, shown.answer)
              : reviews.gradeFlashcard(shown, fsrs.Rating.good));
        }
        time.advance(const Duration(days: 20));
        await logBarolo(tastedOn: '2026-10-21');

        StudyCard card(List<StudyCard> cards, String id) =>
            cards.singleWhere((c) => c.itemId == id);
        final cards = await planner.cards('WSET_L3');
        final barolo = card(cards, 'ki_barolo_grape');
        final barbaresco = card(cards, 'ki_barbaresco_grape');
        expect(barolo.priority!.journalFactor, 2);
        expect(barbaresco.priority!.journalFactor, 1);
        expect(
          barolo.priority!.score,
          closeTo(2 * barbaresco.priority!.score, 1e-9),
          reason: 'both were reviewed alike, and only Barolo is in the journal',
        );
      },
    );
  });
}
