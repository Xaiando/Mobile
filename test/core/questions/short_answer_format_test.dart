import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

/// Backlog Q1: short written answers, checked against key points (QF-14).
void main() {
  late AppDatabase db;
  late TestClock time;
  late GenerationReport generated;
  late ExercisePresenter presenter;
  late ReviewService reviews;
  const profile = 'qt_profile_short_answer';
  const format = ShortAnswerFormat();

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    db = openTestDatabase();
    generated = await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    presenter = ExercisePresenter(db, clock: time.clock);
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(5),
    );
  });
  tearDown(() => db.close());

  Future<ShortAnswerExercise> present(String itemId, {int seed = 1}) async =>
      await presenter.present(itemId, profile, seed: seed)
          as ShortAnswerExercise;

  /// Reviews each of [items], a pair of the item and a template, once.
  Future<void> study(List<(String, String)> items) async {
    for (final (item, template) in items) {
      await reviews.record(
        knowledgeItemId: item,
        questionTemplateId: template,
        rating: fsrs.Rating.good,
      );
    }
  }

  /// Chablis's key points other than its soil, studied.
  Future<void> studyChablis() => study([
    ('ki_chablis_grape', 'qt_principal_grape_fwd_flashcard'),
    ('ki_chablis_climate', 'qt_climate_fwd_flashcard'),
    ('ki_chablis_frost', 'qt_hazard_fwd_flashcard'),
  ]);

  test('one pool per appellation with two key points or more', () async {
    expect(generated.pools, 13);
    final pools = await db.select(db.exercisePools).get();
    final chablis = pools.singleWhere((p) => p.scopeNodeId == 'n_geo_chablis');
    expect(
      chablis.promptText,
      'Write a short profile of Chablis: its grapes, growing environment '
      'and rules.',
    );
    final items = await (db.select(
      db.exercisePoolItems,
    )..where((i) => i.exercisePoolId.equals(chablis.id))).get();
    expect(
      {for (final i in items) i.knowledgeItemId},
      {
        'ki_chablis_grape',
        'ki_chablis_climate',
        'ki_chablis_soil',
        'ki_chablis_frost',
      },
      reason: 'its location is not a key point',
    );
    expect(
      pools.where((p) => p.scopeNodeId == 'n_geo_vouvray'),
      isEmpty,
      reason: 'Vouvray has one key point',
    );
  });

  test('checks the planned item with its key points, in the template '
      'order', () async {
    await studyChablis();
    final exercise = await present('ki_chablis_soil');
    expect(exercise.primaryItemId, 'ki_chablis_soil');
    expect(exercise.itemIds.first, 'ki_chablis_soil');
    expect(exercise.prompt, startsWith('Write a short profile of Chablis'));
    expect(
      [for (final point in exercise.keyPoints) point.title],
      [
        'Principal grape: Chardonnay',
        'Climate: Oceanic with continental influences',
        'Soil: Kimmeridgian marl',
        'Vineyard hazard: Spring frost',
      ],
    );
    expect(exercise.keyPoints[2].statement, contains('fossil oysters'));
    expect(exercise.itemIds.toSet(), hasLength(4));
  });

  test('checks four studied key points at most, due ones first', () async {
    // Of Champagne's six points: two studied yesterday and due, two studied
    // just now, one new, and the soil planned.
    await study([
      ('ki_champagne_method', 'qt_method_fwd_flashcard'),
      ('ki_champagne_min_ageing', 'qt_min_ageing_fwd_flashcard'),
    ]);
    time.advance(const Duration(days: 1));
    await study([
      ('ki_champagne_chardonnay', 'qt_principal_grape_fwd_flashcard'),
      ('ki_champagne_pinot_noir', 'qt_principal_grape_fwd_flashcard'),
    ]);
    final seen = <String>{};
    for (var seed = 0; seed < 8; seed++) {
      final exercise = await present('ki_champagne_soil', seed: seed);
      expect(exercise.keyPoints, hasLength(ShortAnswerFormat.maxKeyPoints));
      expect(
        exercise.itemIds,
        containsAll([
          'ki_champagne_soil',
          'ki_champagne_method',
          'ki_champagne_min_ageing',
        ]),
      );
      seen.addAll(exercise.itemIds);
    }
    expect(seen, {
      'ki_champagne_soil',
      'ki_champagne_method',
      'ki_champagne_min_ageing',
      'ki_champagne_chardonnay',
      'ki_champagne_pinot_noir',
    }, reason: 'the seed draws among the studied; Meunier is new');
  });

  test('a new key point joins only when none has been studied (A-2)', () async {
    final seen = <String>{};
    for (var seed = 0; seed < 30; seed++) {
      final exercise = await present('ki_chablis_soil', seed: seed);
      expect(exercise.keyPoints, hasLength(2));
      seen.addAll(exercise.itemIds);
    }
    expect(seen, hasLength(4), reason: 'the seed draws the new one');
  });

  test('a ticked point is Good, the others Again; the text is kept', () async {
    await studyChablis();
    final exercise = await present('ki_chablis_soil');
    const text = 'Kimmeridgian marl with fossil oysters; a cool climate.';
    final grades = format.grade(
      exercise,
      const ShortAnswerResponse(text, {
        'ki_chablis_soil',
        'ki_chablis_climate',
      }),
    );
    expect(
      {for (final grade in grades) grade.itemId: grade.rating},
      {
        'ki_chablis_soil': fsrs.Rating.good,
        'ki_chablis_grape': fsrs.Rating.again,
        'ki_chablis_climate': fsrs.Rating.good,
        'ki_chablis_frost': fsrs.Rating.again,
      },
    );
    expect(grades.first.payload, {'text': text, 'covered': true});
    expect(grades.last.payload, {'covered': false});
    expect(() => format.grade(exercise, text), throwsArgumentError);
    expect(
      () => format.grade(
        exercise,
        const ShortAnswerResponse(text, {'ki_barolo_soil'}),
      ),
      throwsArgumentError,
      reason: 'not a point of this exercise',
    );

    await reviews.recordExercise(exercise, grades);
    final events = [
      for (final event in await db.select(db.reviewEvents).get())
        if (event.questionTemplateId == profile) event,
    ];
    expect(events, hasLength(4));
    expect(
      {for (final event in events) event.exerciseId},
      hasLength(1),
      reason: 'one exercise (QF-3)',
    );
    final written = events.singleWhere(
      (e) => e.knowledgeItemId == 'ki_chablis_soil',
    );
    expect(jsonDecode(written.answerPayload!), containsPair('text', text));
  });

  test('the validator checks the key points', () {
    Set<String> problems(void Function(Map<String, dynamic> template) change) {
      final data = bundledDatasetMap();
      change(
        rowsOf(
          data,
          'question_templates',
        ).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == profile),
      );
      return {
        for (final issue in validateDataset(datasetOf(data)).errors)
          if (issue.rule == 'template-parameters') issue.message,
      };
    }

    expect(problems((_) {}), isEmpty);
    expect(problems((t) => t.remove('parameters')), {
      '$profile: its parameters need key_points: a mapping from each '
          'relation type to the label of its key points',
    });
    expect(
      problems(
        (t) => t['parameters'] = {
          'key_points': {'HAS_SOIL': 'Soil', 'HAS_FOG': 'Fog'},
        },
      ),
      {
        '$profile: key_points leaves out its own relation type, '
            'PERMITS_PRINCIPAL_GRAPE',
        '$profile: key_points names HAS_FOG, which is no relation type',
      },
    );
    expect(
      problems((t) => t['prompt_template'] = 'What grows in {object.name}?'),
      {'$profile: a short-answer prompt names only {subject.name}'},
    );
    expect(appFormats.require('short_answer').isObjective, isFalse);
  });
}
