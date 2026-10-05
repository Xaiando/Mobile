import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/study_explorer.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/wine_history_catalog.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late StudyExplorer explorer;
  late List<StudyTopic> topics;
  late Set<String> basicIds;
  late Set<String> referenceIds;

  setUpAll(() async {
    db = openTestDatabase();
    final time = TestClock(DateTime.utc(2026, 10, 4, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    explorer = StudyExplorer(db, clock: time.clock);
    topics = await explorer.topics();
    basicIds = (await StudyPlanner(db, clock: time.clock).cards('WSET_L2'))
        .map((c) => c.itemId)
        .toSet();
    referenceIds = (await StudyPlanner(db, clock: time.clock).cards('WSET_L4'))
        .map((c) => c.itemId)
        .toSet();
  });
  tearDownAll(() => db.close());

  test('exactly 30 real grape topics with profile facts and exercises', () {
    final grapes = topics
        .where((t) => t.category == StudyCategory.grapes)
        .toList();
    expect(grapes, hasLength(30));
    expect(grapes.map((t) => t.nodeId).toSet(), coreStudyGrapeIds);
    for (final topic in grapes) {
      expect(topic.cards, isNotEmpty, reason: topic.title);
      expect(topic.questionCards, isNotEmpty, reason: topic.title);
      expect(topic.mapCards, isNotEmpty, reason: '${topic.title} locations');
      final foundation = topic.cards
          .where((c) => basicIds.contains(c.itemId))
          .toList();
      expect(
        topic.cards.take(foundation.length).map((c) => c.itemId).toSet(),
        foundation.map((c) => c.itemId).toSet(),
        reason: '${topic.title} foundation first',
      );
      expect(topic.cards.every((c) => referenceIds.contains(c.itemId)), isTrue);
    }
    final chardonnay = grapes.singleWhere(
      (t) => t.nodeId == 'n_grape_chardonnay',
    );
    expect(
      chardonnay.cards.any((c) => c.itemId.contains('chardonnay_beginner')),
      isTrue,
    );
    expect(chardonnay.mapCards, isNotEmpty);
  });

  test('regions and wines stay inside actual served Level 1–2 scope', () {
    for (final topic in topics.where(
      (t) =>
          t.category == StudyCategory.regions ||
          t.category == StudyCategory.wines,
    )) {
      expect(topic.trackId, 'WSET_L2');
      expect(
        [
          ...topic.cards,
          ...topic.mapCards,
        ].every((c) => basicIds.contains(c.itemId)),
        isTrue,
        reason: topic.title,
      );
    }
    final burgundy = topics.singleWhere(
      (t) => t.id == 'regions-n_geo_burgundy',
    );
    expect(
      burgundy.mapCards.any((c) => c.item.subjectId == 'n_geo_chablis'),
      isTrue,
    );
    expect(
      burgundy.cards.any((c) => c.item.subjectId == 'n_geo_barolo'),
      isFalse,
    );
  });

  test('all requested appellations provide facts, quizzes and maps', () {
    for (final id in [
      'chablis',
      'soave',
      'chianti',
      'chianti_classico',
      'barolo',
      'barbaresco',
    ]) {
      final topic = topics.singleWhere((t) => t.id == 'wines-n_geo_$id');
      expect(topic.cards, isNotEmpty, reason: id);
      expect(topic.questionCards, isNotEmpty, reason: id);
      expect(topic.mapCards, isNotEmpty, reason: id);
    }
  });

  test('grape aliases are searchable without conflating different grapes', () {
    final pinot = topics.singleWhere(
      (t) => t.id == 'grapes-n_grape_pinot_noir',
    );
    expect(pinot.matches('spatburgunder'), isTrue);
    expect(pinot.matches('pinot nero'), isTrue);
    expect(pinot.matches('pinot gris'), isFalse);
    expect(
      topics
          .singleWhere((t) => t.id == 'wines-n_grape_pinot_noir')
          .matches('Spätburgunder'),
      isTrue,
    );
    expect(
      topics
          .singleWhere((t) => t.id == 'grapes-n_grape_syrah')
          .matches('Shiraz'),
      isTrue,
    );
  });

  test('history is chronological, complete and excludes sake and cigars', () {
    final history = topics
        .where((t) => t.category == StudyCategory.history)
        .toList();
    final ids = history.expand((t) => t.cards).map((c) => c.itemId).toSet();
    expect(ids, referenceIds.where(isWineHistoryItem).toSet());
    final chapters = history.map((t) => t.id).toList();
    expect(
      chapters.indexOf('history-early-evidence'),
      lessThan(chapters.indexOf('history-roman')),
    );
    expect(
      chapters.indexOf('history-roman'),
      lessThan(chapters.indexOf('history-napoleon-i')),
    );
    expect(chapters, contains('history-oiv-current'));
    expect(
      ids.any((id) => id.contains('sake') || id.contains('cigar')),
      isFalse,
    );
  });

  test(
    'present and grade real quizzes and location drills without user writes',
    () async {
      final before = await db.customSelect('SELECT * FROM review_states').get();
      final reviewCount = await db
          .customSelect('SELECT count(*) AS n FROM review_events')
          .getSingle();
      final profile = await db.select(db.userProfiles).get();
      final samples = topics.where(
        (t) =>
            t.category == StudyCategory.grapes ||
            const {
              'wines-n_geo_chablis',
              'wines-n_geo_soave',
              'wines-n_geo_chianti',
              'wines-n_geo_chianti_classico',
              'wines-n_geo_barolo',
              'wines-n_geo_barbaresco',
              'wines-n_grape_pinot_noir',
              'history-early-evidence',
              'history-roman',
              'history-napoleon-i',
            }.contains(t.id),
      );
      for (final topic in samples) {
        final card = topic.questionCards.first;
        final format = card.formats.firstWhere(
          (f) => const {'mcq', 'authored_choice', 'typed'}.contains(f.mode),
        );
        final exercise = await explorer.present(
          topic,
          card,
          format,
          seed: 73,
        ) as PresentedQuestion;
        final Object right = exercise.isMultipleChoice
            ? exercise.options.singleWhere((o) => o == exercise.answer)
            : exercise.answer.name;
        final Object wrong = exercise.isMultipleChoice
            ? exercise.options.firstWhere((o) => o != exercise.answer)
            : 'zz_unrelated_answer_98372';
        expect(explorer.grade(exercise, right).single.rating, fsrs.Rating.good);
        expect(
          explorer.grade(exercise, wrong).single.rating,
          fsrs.Rating.again,
        );
        if (topic.mapCards.isNotEmpty) {
          final mapCard = topic.mapCards.first;
          final format = mapCard.formats.firstWhere(
            (f) => f.mode == 'map_locate',
          );
          final map = await explorer.present(
            topic,
            mapCard,
            format,
            seed: 73,
          ) as MapExercise;
          expect(
            explorer
                .grade(map, MapLocateAnswer.fromList(map.nodeId))
                .single
                .rating,
            fsrs.Rating.good,
          );
          final wrongId = map.names.keys.firstWhere(
            (id) => !map.correctNodeIds.contains(id),
          );
          expect(
            explorer
                .grade(map, MapLocateAnswer.fromList(wrongId))
                .single
                .rating,
            fsrs.Rating.again,
          );
        }
      }
      expect(await db.select(db.userProfiles).get(), profile);
      expect(
        (await db.customSelect('SELECT * FROM review_states').get()).length,
        before.length,
      );
      expect(
        (await db
                .customSelect('SELECT count(*) AS n FROM review_events')
                .getSingle())
            .read<int>('n'),
        reviewCount.read<int>('n'),
      );
    },
  );

  test('cross-topic exercises are refused', () async {
    final chablis = topics.singleWhere((t) => t.id == 'wines-n_geo_chablis');
    final barolo = topics.singleWhere((t) => t.id == 'wines-n_geo_barolo');
    final foreign = barolo.cards.firstWhere(
      (c) => ![
        ...chablis.cards,
        ...chablis.mapCards,
      ].any((own) => own.itemId == c.itemId),
    );
    expect(
      () => explorer.present(chablis, foreign, foreign.formats.first, seed: 1),
      throwsArgumentError,
    );
  });
}
