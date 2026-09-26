import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

/// Backlog Q1: typed recall, graded by the app (QF-4).
void main() {
  late AppDatabase db;
  late ExercisePresenter presenter;
  const typed = TypedFormat();

  setUp(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    presenter = ExercisePresenter(db);
  });
  tearDown(() => db.close());

  Future<TypedQuestion> question(String itemId, String template) async =>
      await presenter.present(itemId, template, seed: 1) as TypedQuestion;

  fsrs.Rating ratingOf(TypedQuestion q, String answer) =>
      typed.grade(q, answer).single.rating;

  test('an exact answer is Good, whatever its case and accents', () async {
    final chablis = await question(
      'ki_chablis_grape',
      'qt_principal_grape_fwd_typed',
    );
    expect(chablis.prompt, 'Type a principal grape variety of Chablis.');
    expect(chablis.options, isEmpty);
    for (final answer in ['Chardonnay', 'chardonnay', '  CHARDONNAY ']) {
      expect(ratingOf(chablis, answer), fsrs.Rating.good, reason: answer);
    }
    final condrieu = await question(
      'ki_condrieu_location',
      'qt_located_in_fwd_typed',
    );
    expect(condrieu.answer.name, 'Northern Rhône');
    expect(ratingOf(condrieu, 'northern rhone'), fsrs.Rating.good);
  });

  test('a synonym or another correct answer counts (QF-8)', () async {
    final cornas = await question(
      'ki_cornas_grape',
      'qt_principal_grape_fwd_typed',
    );
    expect(ratingOf(cornas, 'Shiraz'), fsrs.Rating.good);
    final grade = typed.grade(cornas, 'Shiraz').single;
    expect(grade.payload, containsPair('matched', 'Syrah'));

    final chablis = await question(
      'ki_chablis_location',
      'qt_located_in_fwd_typed',
    );
    expect(ratingOf(chablis, 'Bourgogne'), fsrs.Rating.good);

    // Champagne has three principal varieties: any of them answers.
    final champagne = await question(
      'ki_champagne_chardonnay',
      'qt_principal_grape_fwd_typed',
    );
    for (final answer in ['Chardonnay', 'Pinot Noir', 'Pinot Meunier']) {
      expect(ratingOf(champagne, answer), fsrs.Rating.good, reason: answer);
    }
  });

  test('one slip is Hard; another grape, or anything else, is Again', () async {
    final chablis = await question(
      'ki_chablis_grape',
      'qt_principal_grape_fwd_typed',
    );
    final slip = typed.grade(chablis, 'Chardonay').single;
    expect(slip.rating, fsrs.Rating.hard);
    expect(slip.payload, containsPair('outcome', 'near'));
    expect(slip.payload, containsPair('matched', 'Chardonnay'));
    expect(ratingOf(chablis, 'Chardonnay grape wine'), fsrs.Rating.again);
    expect(ratingOf(chablis, 'Pinot Noir'), fsrs.Rating.again);
    expect(ratingOf(chablis, ''), fsrs.Rating.again);
    expect(chablis.rivals, contains('pinot noir'));
    expect(chablis.rivals, isNot(contains('chardonnay')));
    expect(() => typed.grade(chablis, 3), throwsArgumentError);
  });

  test('an answer may add or leave out the words of its type', () async {
    final muscadet = await question(
      'ki_muscadet_sevre_et_maine_climate',
      'qt_climate_fwd_typed',
    );
    expect(muscadet.answer.name, 'Oceanic');
    for (final answer in [
      'Oceanic climate',
      'maritime',
      'the maritime climate',
    ]) {
      expect(ratingOf(muscadet, answer), fsrs.Rating.good, reason: answer);
    }
    final soil = await question('ki_champagne_soil', 'qt_soil_fwd_typed');
    expect(ratingOf(soil, 'chalk soils'), fsrs.Rating.good);
    expect(ratingOf(soil, 'chalky soil'), fsrs.Rating.hard, reason: 'a slip');
    final method = await question('ki_champagne_method', 'qt_method_fwd_typed');
    for (final answer in ['traditional', 'Méthode champenoise']) {
      expect(ratingOf(method, answer), fsrs.Rating.good, reason: answer);
    }
    expect(ratingOf(method, 'tank method'), fsrs.Rating.again);
  });

  test('part of the answer is Hard, unless it names something else', () async {
    final frost = await question('ki_chablis_frost', 'qt_hazard_fwd_typed');
    final part = typed.grade(frost, 'frost').single;
    expect(part.rating, fsrs.Rating.hard);
    expect(part.payload, containsPair('outcome', 'partial'));
    expect(part.payload, containsPair('matched', 'Spring frost'));

    final marl = await question('ki_chablis_soil', 'qt_soil_fwd_typed');
    expect(ratingOf(marl, 'Kimmeridgian'), fsrs.Rating.hard);
    expect(ratingOf(marl, 'marl'), fsrs.Rating.again, reason: 'Tortonian marl');

    final condrieu = await question(
      'ki_condrieu_location',
      'qt_located_in_fwd_typed',
    );
    expect(
      ratingOf(condrieu, 'Rhône'),
      fsrs.Rating.again,
      reason: 'the Southern Rhône, the Rhône Valley',
    );
    final melon = await question(
      'ki_muscadet_sevre_et_maine_grape',
      'qt_principal_grape_fwd_typed',
    );
    expect(ratingOf(melon, 'Melon de Bourgogne'), fsrs.Rating.good);
    expect(ratingOf(melon, 'Bourgogne'), fsrs.Rating.again, reason: 'Burgundy');

    final climate = await question(
      'ki_chablis_climate',
      'qt_climate_fwd_typed',
    );
    expect(climate.answer.name, 'Oceanic with continental influences');
    expect(ratingOf(climate, 'Continental'), fsrs.Rating.again);
    expect(ratingOf(climate, 'continental influences'), fsrs.Rating.hard);
  });

  test('the former flashcard-only items gain typed recall', () async {
    for (final item in [
      'ki_chablis_climate',
      'ki_chablis_frost',
      'ki_champagne_soil',
      'ki_chianti_classico_climate',
      'ki_muscadet_sevre_et_maine_climate',
    ]) {
      final questions = await (db.select(
        db.questions,
      )..where((q) => q.knowledgeItemId.equals(item))).get();
      expect(
        [for (final q in questions) q.questionTemplateId],
        contains(endsWith('_typed')),
        reason: item,
      );
    }
  });

  test(
    'typed recall is objective recall, at depth 2 forward and 3 reverse',
    () {
      final format = appFormats.require('typed');
      expect(format.isObjective, isTrue);
      expect(format.requiredDepth('forward'), 2);
      expect(format.requiredDepth('reverse'), 3);
    },
  );
}
