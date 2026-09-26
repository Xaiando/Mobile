import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/format_ladder.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

/// Backlog F4: the presentation difficulty ladder (QF-7).
void main() {
  final now = DateTime.utc(2026, 10, 1, 9);
  const noRandomDraw = FormatLadder(randomEvery: 0);

  /// A state in [band]: on a step while learning, else Review with a
  /// stability inside the band.
  ReviewState? stateIn(MemoryBand? band) => switch (band) {
    null => null,
    _ => ReviewState(
      knowledgeItemId: 'ki_example',
      state: band == MemoryBand.learning
          ? fsrs.State.learning.value
          : fsrs.State.review.value,
      step: band == MemoryBand.learning ? 0 : null,
      stability: switch (band) {
        MemoryBand.learning => 0.5,
        MemoryBand.young => 3,
        MemoryBand.maturing => 12,
        MemoryBand.mature => 60,
      },
      difficulty: 5,
      due: now,
      lastReview: now.subtract(const Duration(days: 3)),
      reps: 3,
      lapses: 0,
    ),
  };

  /// A card of an item the track serves [formats], each `mode` or
  /// `mode reverse`, in the band [band] (new when null).
  StudyCard card(List<String> formats, {MemoryBand? band, String? last}) =>
      StudyCard(
        item: KnowledgeItem(
          id: 'ki_example',
          subjectId: 'n_subject',
          relationType: 'LOCATED_IN',
          objectId: 'n_object',
          domainId: 'geography',
          assertionText: 'An example assertion.',
          revision: 1,
          lastVerifiedAt: now,
          verificationStatus: 'unverified',
          isDistinctive: false,
          mcqDisabled: false,
        ),
        mapping: const EffectiveMapping(
          knowledgeItemId: 'ki_example',
          certificationId: 'WSET_L3',
          importance: 'core',
          minimumDepth: 5,
          chainDepth: 0,
        ),
        formats: StudyPlanner.servedFormats([
          for (final spec in formats)
            QuestionFormat(
              questionTemplateId: 'qt_${spec.replaceAll(' ', '_')}',
              direction: spec.endsWith(' reverse') ? 'reverse' : 'forward',
              mode: spec.split(' ').first,
              format: appFormats.require(spec.split(' ').first),
            ),
        ], 5),
        state: stateIn(band),
        retrievability: 1,
        priority: null,
        isStale: false,
        lastTemplateId: last == null ? null : 'qt_${last.replaceAll(' ', '_')}',
      );

  String spec(QuestionFormat format) =>
      format.isReverse ? '${format.mode} reverse' : format.mode;

  /// The formats chosen for [card] over [seeds] seeds.
  Map<String, int> draws(
    StudyCard card, {
    FormatLadder ladder = const FormatLadder(),
    int seeds = 200,
  }) {
    final counts = <String, int>{};
    for (var seed = 0; seed < seeds; seed++) {
      final format = ladder.choose(card, Random(seed));
      counts.update(spec(format), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  const every = [
    'mcq',
    'flashcard',
    'typed',
    'map_locate',
    'mcq reverse',
    'flashcard reverse',
    'short_answer',
  ];

  group('the bands (question-system §5)', () {
    test('follow stability: 7 and 30 days', () {
      expect(MemoryBand.of(null), MemoryBand.learning);
      for (final band in MemoryBand.values) {
        expect(MemoryBand.of(stateIn(band)), band);
      }
      expect(
        MemoryBand.of(stateIn(MemoryBand.young)!.copyWith(stability: 7)),
        MemoryBand.maturing,
      );
      expect(
        MemoryBand.of(stateIn(MemoryBand.young)!.copyWith(stability: 30)),
        MemoryBand.mature,
      );
    });

    test('a new item starts with its easiest format for learning', () {
      expect(draws(card(every)).keys, ['mcq']);
      expect(draws(card(['flashcard', 'typed', 'map_locate'])).keys, [
        'map_locate',
      ], reason: 'a labelled map, without an MCQ');
      expect(draws(card(['flashcard', 'typed'])).keys, [
        'flashcard',
      ], reason: 'the nearest band, the easiest there (FS-15)');
    });

    test('each band draws its families', () {
      Set<String> chosen(MemoryBand band, {List<String> served = every}) =>
          draws(card(served, band: band), ladder: noRandomDraw).keys.toSet();

      expect(chosen(MemoryBand.learning), {'mcq', 'map_locate'});
      expect(chosen(MemoryBand.young), {'flashcard', 'typed', 'map_locate'});
      expect(chosen(MemoryBand.maturing), {
        'map_locate',
        'mcq reverse',
        'flashcard reverse',
        'short_answer',
      });
      expect(chosen(MemoryBand.mature), {'map_locate', 'short_answer'});
      expect(chosen(MemoryBand.mature, served: ['mcq', 'flashcard', 'typed']), {
        'flashcard',
        'typed',
      }, reason: 'nothing mature: the nearest band that has a format');
    });
  });

  test('never repeats the last format while another is served', () {
    for (final band in MemoryBand.values) {
      for (final last in every) {
        final chosen = draws(card(every, band: band, last: last));
        expect(
          chosen.keys,
          isNot(contains(last)),
          reason: '$last in ${band.name}',
        );
      }
    }
    expect(
      draws(card(['flashcard'], band: MemoryBand.young, last: 'flashcard')),
      {'flashcard': 200},
      reason: 'the only one served',
    );
    expect(
      draws(card(['mcq', 'mcq reverse'], band: MemoryBand.young, last: 'mcq'))
          .keys,
      ['mcq reverse'],
      reason: 'a reverse question is another format',
    );
  });

  test(
    'one presentation in five is a random draw among the served formats',
    () {
      // Young: flashcard and typed are preferred; the MCQ comes only from the
      // random draw, a third of a fifth of the time.
      final chosen = draws(
        card(['mcq', 'flashcard', 'typed'], band: MemoryBand.young),
        seeds: 6000,
      );
      expect(chosen['mcq']! / 6000, closeTo(1 / 15, 0.015));
      expect(chosen['flashcard']! / 6000, closeTo(7 / 15, 0.03));
      expect(chosen['typed']! / 6000, closeTo(7 / 15, 0.03));
      expect(
        draws(
          card(['mcq', 'flashcard', 'typed'], band: MemoryBand.young),
          ladder: noRandomDraw,
          seeds: 1000,
        )['mcq'],
        isNull,
      );
    },
  );

  test('map modes follow the same bands (GEO-8)', () {
    expect(mapModeFor(stateIn(null)), MapMode.labelled);
    expect(mapModeFor(stateIn(MemoryBand.learning)), MapMode.labelled);
    expect(mapModeFor(stateIn(MemoryBand.young)), MapMode.outline);
    expect(mapModeFor(stateIn(MemoryBand.maturing)), MapMode.minimal);
    expect(mapModeFor(stateIn(MemoryBand.mature)), MapMode.blank);
  });

  test('an item recalled for weeks is asked harder and harder', () async {
    final time = TestClock(DateTime.utc(2026, 10, 1, 9));
    final db = openTestDatabase();
    addTearDown(db.close);
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    final planner = StudyPlanner(db, clock: time.clock);
    final presenter = ExercisePresenter(db, clock: time.clock);
    final reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(5),
    );
    const item = 'ki_chablis_location';
    const node = 'n_geo_chablis';
    final random = Random(11);

    final asked = <(MemoryBand, String, MapMode?)>[];
    for (var i = 0; i < 12; i++) {
      final card = (await planner.cards('WSET_L3'))
          .firstWhere((c) => c.itemId == item);
      final format = card.chooseFormat(random, ladder: noRandomDraw);
      final exercise = await presenter.present(
        item,
        format.questionTemplateId,
        seed: i,
      );
      final Object answer = switch (exercise) {
        MapExercise(formatId: 'map_locate') => const MapLocateAnswer(
          nodeId: node,
          fromList: true,
        ),
        MapExercise(:final options) => options.firstWhere(
          (o) => o.nodeId == node,
        ),
        PresentedQuestion(mode: 'flashcard') => fsrs.Rating.good,
        PresentedQuestion(mode: 'typed', :final answer) => answer.name,
        PresentedQuestion(:final answer) => answer,
        _ => fail('unexpected $exercise'),
      };
      final results = await reviews.recordExercise(
        exercise,
        presenter.grade(exercise, answer),
      );
      expect(results.single.rating, isNot(fsrs.Rating.again));
      asked.add((
        MemoryBand.of(card.state),
        spec(format),
        exercise is MapExercise ? exercise.mode : null,
      ));
      time.now = results.single.after.due.add(const Duration(minutes: 1));
    }

    // Recognition or a labelled map while it is learnt; recall or an
    // outline once young; only maps, harder and harder, as it matures.
    final (firstBand, first, firstMode) = asked.first;
    expect((firstBand, first, firstMode), (MemoryBand.learning, 'mcq', null));
    for (final (band, format, mode) in asked) {
      switch (band) {
        case MemoryBand.learning:
          expect(format, isIn(['mcq', 'map_locate', 'map_identify']));
        case MemoryBand.young:
          expect(
            format,
            isIn(['flashcard', 'typed', 'map_locate', 'map_identify']),
          );
        case MemoryBand.maturing || MemoryBand.mature:
          expect(format, isIn(['map_locate', 'map_identify']));
      }
      if (mode != null) {
        // Identify is never labelled, which would name its answer.
        final expected = mapModeFor(stateIn(band));
        expect(
          mode,
          format == 'map_identify' && expected == MapMode.labelled
              ? MapMode.outline
              : expected,
          reason: '$format in ${band.name}',
        );
      }
    }
    final bands = [for (final (band, _, _) in asked) band.index];
    expect(bands, orderedEquals([...bands]..sort()), reason: 'always recalled');
    expect(bands.last, MemoryBand.mature.index);
    expect(asked.last.$3, MapMode.blank, reason: 'a mature item: no labels');
  });
}
