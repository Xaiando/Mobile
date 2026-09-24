import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late StudyPlanner planner;
  late ReviewService reviews;
  late QuestionPresenter presenter;

  Future<void> open([CurriculumDataset? dataset]) async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(dataset ?? bundledDataset());
    planner = StudyPlanner(db, clock: time.clock);
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
    );
    presenter = QuestionPresenter(db);
  }

  setUp(() => time = TestClock(DateTime.utc(2026, 10, 1, 9)));
  tearDown(() => db.close());

  /// Grades the item's forward flashcard.
  Future<ReviewResult> review(String itemId, fsrs.Rating rating) async {
    final template = await db
        .customSelect(
          '''
      SELECT q.question_template_id FROM questions q
      JOIN question_templates t ON t.id = q.question_template_id
      WHERE q.knowledge_item_id = ? AND t.mode = 'flashcard'
        AND t.direction = 'forward' ''',
          variables: [Variable(itemId)],
        )
        .getSingle();
    final shown = await presenter.present(
      itemId,
      template.read<String>('question_template_id'),
      seed: 1,
    );
    return reviews.gradeFlashcard(shown, rating);
  }

  Future<StudyCard> cardOf(String itemId, {String track = 'WSET_L3'}) async =>
      (await planner.cards(track)).singleWhere((c) => c.itemId == itemId);

  group('effective mapping', () {
    setUp(() => open());

    test(
      'the track\'s own mapping wins over an inherited one (CM-3)',
      () async {
        final mappings = await planner.effectiveMappings('WSET_L3');
        final chablis = mappings['ki_chablis_grape']!;
        expect(chablis.certificationId, 'WSET_L3');
        expect(chablis.chainDepth, 0);
        expect(chablis.minimumDepth, 2);
        expect(chablis.relevance, 1.0);
      },
    );

    test(
      'a lower level\'s mapping is inherited along the chain (CM-2, CM-3)',
      () async {
        await db.close();
        final dataset = bundledDatasetMap();
        rowsOf(dataset, 'certification_knowledge_mappings').removeWhere(
          (m) =>
              m['knowledge_item_id'] == 'ki_barolo_grape' &&
              (m['certification_id'] == 'WSET_L3' ||
                  m['certification_id'] == 'CMS_CERTIFIED'),
        );
        await open(datasetOf(dataset));

        final wset = (await planner.effectiveMappings(
          'WSET_L3',
        ))['ki_barolo_grape']!;
        expect(wset.certificationId, 'WSET_L2');
        expect(wset.chainDepth, 1);
        final cms = (await planner.effectiveMappings(
          'CMS_CERTIFIED',
        ))['ki_barolo_grape']!;
        expect(cms.certificationId, 'CMS_INTRODUCTORY');
      },
    );

    test(
      'an item without a mapping on the track is not studied (CM-4)',
      () async {
        await db.close();
        final dataset = bundledDatasetMap();
        rowsOf(dataset, 'certification_knowledge_mappings').removeWhere(
          (m) =>
              m['knowledge_item_id'] == 'ki_champagne_meunier' &&
              m['certification_id'] == 'CMS_CERTIFIED',
        );
        await open(datasetOf(dataset));

        final cms = await planner.cards('CMS_CERTIFIED');
        expect(
          cms.map((c) => c.itemId),
          isNot(contains('ki_champagne_meunier')),
        );
        final wset = await planner.cards('WSET_L3');
        expect(wset.map((c) => c.itemId), contains('ki_champagne_meunier'));
      },
    );
  });

  group('formats served (CM-6)', () {
    const fwdMcq = QuestionFormat(
      questionTemplateId: 'qt_fwd_mcq',
      direction: 'forward',
      mode: 'mcq',
    );
    const fwdCard = QuestionFormat(
      questionTemplateId: 'qt_fwd_flashcard',
      direction: 'forward',
      mode: 'flashcard',
    );
    const revMcq = QuestionFormat(
      questionTemplateId: 'qt_rev_mcq',
      direction: 'reverse',
      mode: 'mcq',
    );
    const revCard = QuestionFormat(
      questionTemplateId: 'qt_rev_flashcard',
      direction: 'reverse',
      mode: 'flashcard',
    );
    const all = [revCard, fwdCard, revMcq, fwdMcq];

    test('depth 1 recognizes, 2 adds forward recall, 3 adds reverse', () {
      expect(StudyPlanner.servedFormats(all, 1), [fwdMcq]);
      expect(StudyPlanner.servedFormats(all, 2), [fwdMcq, fwdCard]);
      expect(StudyPlanner.servedFormats(all, 3), [
        fwdMcq,
        fwdCard,
        revMcq,
        revCard,
      ]);
      expect(StudyPlanner.servedFormats(all, 5), hasLength(4));
    });

    test('an item with no format at its depth falls back to the easiest '
        '(A-10)', () {
      expect(StudyPlanner.servedFormats([fwdCard, revCard], 1), [fwdCard]);
    });

    test('on the bundled track, reverse questions need depth 3', () async {
      await open();
      final barolo = await cardOf('ki_barolo_min_ageing');
      expect(barolo.mapping.minimumDepth, 3);
      expect(barolo.formats.map((f) => f.direction), contains('reverse'));
      final grape = await cardOf('ki_barolo_grape');
      expect(grape.formats.map((f) => f.direction), everyElement('forward'));
      final climate = await cardOf('ki_chablis_climate');
      expect(climate.formats.map((f) => f.mode), ['flashcard']);
    });
  });

  group('session plan', () {
    setUp(() => open());

    test('needs a track', () async {
      expect(await planner.plan(), isNull);
    });

    test('a new learner gets 5 new items, core first (P-4, A-2)', () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final plan = (await planner.plan())!;
      expect(plan.certificationId, 'WSET_L3');
      expect(plan.cards, hasLength(5));
      expect(plan.cards, everyElement(predicate<StudyCard>((c) => c.isNew)));
      expect(plan.cards.map((c) => c.mapping.importance), everyElement('core'));
      expect(plan.dueCount, 0);
      expect(plan.newAvailable, (await planner.cards('WSET_L3')).length);
    });

    test('new items never come before their prerequisites (A-2)', () async {
      final fresh = await planner.cards('WSET_L3');
      final prerequisites = <String, List<String>>{};
      for (final edge in await db.select(db.knowledgeItemPrerequisites).get()) {
        prerequisites
            .putIfAbsent(edge.knowledgeItemId, () => [])
            .add(edge.prerequisiteItemId);
      }
      final order = StudyPlanner.orderNew(
        fresh,
        prerequisites,
      ).map((c) => c.itemId).toList();
      expect(order.toSet(), fresh.map((c) => c.itemId).toSet());
      for (final entry in prerequisites.entries) {
        for (final prerequisite in entry.value) {
          if (!order.contains(entry.key) || !order.contains(prerequisite)) {
            continue;
          }
          expect(
            order.indexOf(prerequisite),
            lessThan(order.indexOf(entry.key)),
            reason: '$prerequisite before ${entry.key}',
          );
        }
      }
      expect(
        order.indexOf('ki_barolo_location'),
        lessThan(order.indexOf('ki_barolo_grape')),
      );
    });

    test(
      'due reviews fill the session first; new items only the room left',
      () async {
        final items = (await planner.cards('WSET_L3')).map((c) => c.itemId);
        for (final itemId in items.take(12)) {
          await review(itemId, fsrs.Rating.easy);
        }
        time.advance(const Duration(days: 40));
        var plan = (await planner.plan(certificationId: 'WSET_L3'))!;
        expect(plan.dueCount, 12);
        expect(plan.cards, hasLength(15));
        expect(plan.cards.where((c) => c.isNew), hasLength(3));
        expect(plan.cards.take(12).every((c) => !c.isNew), isTrue);

        for (final itemId in items.skip(12).take(8)) {
          await review(itemId, fsrs.Rating.easy);
        }
        time.advance(const Duration(days: 40));
        plan = (await planner.plan(certificationId: 'WSET_L3'))!;
        expect(plan.dueCount, 20);
        expect(plan.cards, hasLength(15));
        expect(plan.cards.where((c) => c.isNew), isEmpty);
      },
    );

    test(
      'learning steps come first, then reviews by descending score',
      () async {
        await review('ki_barolo_grape', fsrs.Rating.easy);
        await review('ki_chablis_soil', fsrs.Rating.easy);
        time.advance(const Duration(days: 10));
        await review('ki_cornas_grape', fsrs.Rating.easy);
        time.advance(const Duration(days: 30));
        await review('ki_vouvray_grape', fsrs.Rating.again); // a new item
        time.advance(const Duration(minutes: 5));

        final plan = (await planner.plan(certificationId: 'WSET_L3'))!;
        final due = plan.cards.where((c) => !c.isNew).toList();
        expect(due.first.itemId, 'ki_vouvray_grape');
        expect(due.first.isOnLearningStep, isTrue);
        final scores = [for (final card in due.skip(1)) card.priority!.score];
        expect(
          scores,
          orderedEquals(
            List<double>.of(scores)..sort((a, b) => b.compareTo(a)),
          ),
        );
        // Same review time, so the same R: the core item outranks the
        // secondary one (C).
        expect(
          due.indexWhere((c) => c.itemId == 'ki_barolo_grape'),
          lessThan(due.indexWhere((c) => c.itemId == 'ki_chablis_soil')),
        );
      },
    );

    test('R comes from the package: 0 when new, 1 on the review day', () async {
      expect((await cardOf('ki_barolo_grape')).retrievability, 0);
      await review('ki_barolo_grape', fsrs.Rating.good);
      expect((await cardOf('ki_barolo_grape')).retrievability, 1);
      time.advance(const Duration(days: 3));
      final card = await cardOf('ki_barolo_grape');
      final state = await db.select(db.reviewStates).getSingle();
      expect(
        card.retrievability,
        fsrs.Scheduler().getCardRetrievability(
          fsrs.Card(
            cardId: 0,
            state: fsrs.State.fromValue(state.state),
            step: state.step,
            stability: state.stability,
            difficulty: state.difficulty,
            due: state.due,
            lastReview: state.lastReview,
          ),
          currentDateTime: time.now,
        ),
      );
      expect(card.retrievability, inExclusiveRange(0, 1));
    });
  });

  group('prerequisite repair (A-4)', () {
    setUp(() => open());

    Future<void> graduate(List<String> itemIds) async {
      for (final itemId in itemIds) {
        await review(itemId, fsrs.Rating.easy);
      }
    }

    test('a forgotten dependent boosts its prerequisites, fading with '
        'distance', () async {
      await graduate([
        'ki_barolo_location',
        'ki_barolo_grape',
        'ki_barolo_min_ageing',
      ]);
      time.advance(const Duration(days: 30));
      final before = await cardOf('ki_barolo_grape');

      final lapse = await review('ki_barolo_min_ageing', fsrs.Rating.again);
      expect(lapse.isLapse, isTrue);

      final grape = await cardOf('ki_barolo_grape');
      final location = await cardOf('ki_barolo_location');
      expect(grape.priority!.prerequisiteFactor, 2); // 1 + β·γ¹·1
      expect(location.priority!.prerequisiteFactor, 1.5); // 1 + β·γ²·1
      expect(grape.priority!.score, greaterThan(before.priority!.score));
    });

    test('only reviewed dependents count', () async {
      await graduate(['ki_barolo_grape']);
      time.advance(const Duration(days: 30));
      final grape = await cardOf('ki_barolo_grape');
      // ki_barolo_min_ageing builds on it but is still new (R = 0).
      expect(grape.priority!.prerequisiteFactor, 1);
    });
  });

  group('validity and badges', () {
    test(
      'an expired item keeps its state but leaves the queue (FS-13)',
      () async {
        final dataset = bundledDatasetMap();
        final relation = rowsOf(dataset, 'knowledge_relations')
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (r) =>
                  r['subject_id'] == 'n_geo_chablis' &&
                  r['relation_type'] == 'PERMITS_PRINCIPAL_GRAPE',
            );
        relation['valid_until'] = '2027-01-01';
        await open(datasetOf(dataset));
        await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');

        await review('ki_chablis_grape', fsrs.Rating.easy);
        expect(
          (await planner.cards('WSET_L3')).map((c) => c.itemId),
          contains('ki_chablis_grape'),
        );

        time.now = DateTime.utc(2027, 3, 1, 9);
        expect(
          (await planner.cards('WSET_L3')).map((c) => c.itemId),
          isNot(contains('ki_chablis_grape')),
        );
        expect(await db.select(db.reviewStates).get(), hasLength(1));
        final overview = (await planner.overview())!;
        expect(overview.changed.map((e) => e.itemId), ['ki_chablis_grape']);
      },
    );

    test('unverified and stale items carry badges (P-5, V-4)', () async {
      await open();
      final card = await cardOf('ki_barolo_grape');
      expect(card.isUnverified, isTrue);
      expect(card.isStale, isFalse);

      time.now = DateTime.utc(2029, 1, 1);
      expect((await cardOf('ki_barolo_grape')).isStale, isTrue);
    });
  });

  group('overview', () {
    setUp(() => open());

    test('is null before a track is chosen', () async {
      expect(await planner.overview(), isNull);
    });

    test('counts due, new and studied items', () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final total = (await planner.cards('WSET_L3')).length;
      await review('ki_barolo_grape', fsrs.Rating.easy);
      await review('ki_chablis_grape', fsrs.Rating.easy);
      time.advance(const Duration(days: 60));

      final overview = (await planner.overview())!;
      expect(overview.certification.id, 'WSET_L3');
      expect(overview.dueCount, 2);
      expect(overview.newAvailable, total - 2);
      expect(overview.studied, 2);
      expect(overview.total, total);
      expect(overview.changed, isEmpty);
    });

    test(
      'retention is the share of Review-state recalls that succeeded',
      () async {
        await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
        expect((await planner.overview())!.retention, isNull);

        // Learning-step answers do not count: the item was never recalled
        // from Review state.
        await review('ki_barolo_grape', fsrs.Rating.again);
        await review('ki_chablis_grape', fsrs.Rating.easy);
        await review('ki_cornas_grape', fsrs.Rating.easy);
        await review('ki_vouvray_grape', fsrs.Rating.easy);
        expect(await planner.retention(), isNull);

        time.advance(const Duration(days: 30));
        await review('ki_chablis_grape', fsrs.Rating.good);
        await review('ki_cornas_grape', fsrs.Rating.hard);
        await review('ki_vouvray_grape', fsrs.Rating.again);
        expect(await planner.retention(), closeTo(2 / 3, 1e-12));

        // Older than 30 days: outside the window.
        time.advance(const Duration(days: 31));
        expect(await planner.retention(), isNull);
      },
    );
  });
}
