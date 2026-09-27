import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart'
    show regulatoryRelationTypes;
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/numeric/numeric_format.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/settings/user_settings.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

const _minimumItem = 'ki_numeric_test_minimum';
const _temperatureItem = 'ki_numeric_test_temperature';
const _minimumTemplate = 'qt_numeric_test_minimum';
const _temperatureTemplate = 'qt_numeric_test_temperature';

NumericQuestion _question({
  String relation = 'TEST_TEMPERATURE',
  double minimum = 10,
  double? maximum = 14,
  String canonicalUnit = '°C',
  String displayUnit = '°C',
  double exactTolerance = 0,
  double tolerance = 2,
}) => NumericQuestion(
  knowledgeItemId: _temperatureItem,
  questionTemplateId: _temperatureTemplate,
  prompt: 'Test-only quantity question.',
  answer: const QuestionOption('n_qty_numeric_test_temperature', '10–14 °C'),
  explanation: 'Synthetic fixture; no wine service recommendation.',
  seed: 17,
  relationType: relation,
  canonicalMinimum: minimum,
  canonicalMaximum: maximum,
  canonicalUnit: canonicalUnit,
  displayUnit: displayUnit,
  exactTolerance: exactTolerance,
  tolerance: tolerance,
);

QuestionTemplate _template({
  String relation = 'TEST_TEMPERATURE',
  String direction = 'forward',
  Object? parameters = const {'exact_tolerance': 0, 'tolerance': 2},
}) => QuestionTemplate(
  id: _temperatureTemplate,
  relationType: relation,
  direction: direction,
  mode: 'numeric',
  locale: 'en',
  promptTemplate: 'Give the fixture quantity for {subject.name}.',
  variant: 'test_numeric',
  parameters: parameters == null ? null : jsonEncode(parameters),
);

/// Unshipped technical fixtures: the names and temperatures are not advice.
CurriculumDataset numericTestDataset() {
  final data = copyOf(minimalDataset());
  rowsOf(data, 'node_types').add({'id': 'quantity', 'label': 'quantity'});
  for (final relation in ['MIN_AGEING', 'TEST_TEMPERATURE']) {
    rowsOf(data, 'relation_types').add({
      'id': relation,
      'label': 'has test quantity',
      'reverse_label': 'is the test quantity of',
      'cardinality': 'one',
      'default_domain_id': 'geography',
    });
    rowsOf(data, 'relation_type_signatures').add({
      'relation_type': relation,
      'subject_node_type': 'appellation',
      'object_node_type': 'quantity',
    });
  }
  for (final entry in [
    (
      _minimumItem,
      'n_geo_chablis',
      'MIN_AGEING',
      'n_qty_numeric_test_minimum',
      '38 months',
      38.0,
      null,
      'month',
      _minimumTemplate,
    ),
    (
      _temperatureItem,
      'n_geo_volnay',
      'TEST_TEMPERATURE',
      'n_qty_numeric_test_temperature',
      '10–14 °C',
      10.0,
      14.0,
      '°C',
      _temperatureTemplate,
    ),
  ]) {
    final (
      itemId,
      subjectId,
      relation,
      objectId,
      name,
      minimum,
      maximum,
      unit,
      templateId,
    ) = entry;
    rowsOf(
      data,
      'knowledge_nodes',
    ).add({'id': objectId, 'node_type': 'quantity', 'name': name});
    rowsOf(data, 'quantity_values').add({
      'knowledge_node_id': objectId,
      'minimum': minimum,
      'maximum': maximum,
      'unit': unit,
    });
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': subjectId,
      'relation_type': relation,
      'object_id': objectId,
      'valid_from': '2026-01-01',
    });
    rowsOf(data, 'knowledge_items').add({
      'id': itemId,
      'subject_id': subjectId,
      'relation_type': relation,
      'object_id': objectId,
      'domain_id': 'geography',
      'assertion_text': 'Synthetic numeric test fixture: $name.',
      'last_verified_at': '2026-01-01T00:00:00.000Z',
    });
    rowsOf(data, 'certification_knowledge_mappings').add({
      'certification_id': 'WSET_L2',
      'knowledge_item_id': itemId,
      'importance': 'core',
      'minimum_depth': 2,
    });
    rowsOf(data, 'knowledge_item_citations').add({
      'knowledge_item_id': itemId,
      'source_citation_id': 'src_test_law',
      'locator': 'Synthetic test-only quantity.',
    });
    rowsOf(data, 'question_templates').add({
      'id': templateId,
      'relation_type': relation,
      'direction': 'forward',
      'mode': 'numeric',
      'prompt_template': 'Give the test quantity for {subject.name}.',
      'parameters': {
        'exact_tolerance': 0,
        'tolerance': relation == 'MIN_AGEING' ? 0 : 2,
      },
    });
  }
  return datasetOf(data);
}

void main() {
  const format = NumericFormat();

  test('numeric is objective structured practice at depth two', () {
    expect(format.family, FormatFamily.structured);
    expect(format.isObjective, isTrue);
    expect(format.requiredDepth('forward'), 2);
    expect(format.generation, FormatGeneration.single);
    expect(format.needsDistractors, isFalse);
    expect(format.preferredBands('forward'), {
      MemoryBand.young,
      MemoryBand.maturing,
    });
  });

  test(
    'legal minima require the exact lower endpoint with no interval or epsilon',
    () {
      for (final relation in ['MIN_AGEING', 'MIN_WOOD_AGEING']) {
        final question = _question(
          relation: relation,
          minimum: 38,
          maximum: 48,
          canonicalUnit: 'month',
          displayUnit: 'month',
          tolerance: 0,
        );
        expect(question.isLegalMinimum, isTrue);
        expect(question.allowsInterval, isFalse);
        expect(format.grade(question, '38').single.rating, fsrs.Rating.good);
        for (final value in [37.999999999999, 38.000000000001, 48.0]) {
          expect(
            format
                .grade(question, NumericAnswer.scalar(value, unit: 'month'))
                .single
                .rating,
            fsrs.Rating.again,
            reason: '$relation: $value',
          );
        }
        expect(
          format
              .grade(
                question,
                const NumericAnswer.interval(38, 48, unit: 'month'),
              )
              .single
              .rating,
          fsrs.Rating.again,
        );
      }
    },
  );

  test(
    'finite ranges and their total outer band grade Good, Hard or Again',
    () {
      final question = _question(exactTolerance: 0.5);
      for (final value in [9.5, 10.0, 12.0, 14.0, 14.5]) {
        expect(
          NumericFormat.outcome(
            question,
            NumericAnswer.scalar(value, unit: '°C'),
          ),
          NumericOutcome.exact,
        );
        expect(
          format
              .grade(question, NumericAnswer.scalar(value, unit: '°C'))
              .single
              .rating,
          fsrs.Rating.good,
        );
      }
      for (final value in [8.0, 9.0, 15.0, 16.0]) {
        expect(
          NumericFormat.outcome(
            question,
            NumericAnswer.scalar(value, unit: '°C'),
          ),
          NumericOutcome.near,
        );
        expect(
          format
              .grade(question, NumericAnswer.scalar(value, unit: '°C'))
              .single
              .rating,
          fsrs.Rating.hard,
        );
      }
      for (final value in [7.999, 16.001]) {
        expect(
          format
              .grade(question, NumericAnswer.scalar(value, unit: '°C'))
              .single
              .rating,
          fsrs.Rating.again,
          reason: 'tolerance is the total width, not added to exact_tolerance',
        );
      }
      expect(
        format
            .grade(question, const NumericAnswer.interval(10, 14, unit: '°C'))
            .single
            .rating,
        fsrs.Rating.good,
      );
      expect(
        format
            .grade(question, const NumericAnswer.interval(8, 14, unit: '°C'))
            .single
            .rating,
        fsrs.Rating.hard,
      );
      expect(
        format
            .grade(question, const NumericAnswer.interval(7, 14, unit: '°C'))
            .single
            .rating,
        fsrs.Rating.again,
      );
      expect(
        format
            .grade(question, const NumericAnswer.interval(13, 11, unit: '°C'))
            .single
            .rating,
        fsrs.Rating.again,
      );
      final scalar = _question(minimum: 12, maximum: null);
      expect(scalar.allowsInterval, isFalse);
      expect(
        format
            .grade(scalar, const NumericAnswer.interval(12, 12, unit: '°C'))
            .single
            .rating,
        fsrs.Rating.again,
      );
    },
  );

  test('strict parsing accepts finite decimal/scientific values and ordered intervals', () {
    for (final text in ['38', ' 38.0 month ', '3.8e1 month']) {
      final parsed = NumericAnswer.tryParse(text, defaultUnit: 'month');
      expect(parsed, isNotNull, reason: text);
      expect(parsed!.minimum, 38);
      expect(parsed.isInterval, isFalse);
    }
    for (final text in ['10–14 °C', '10-14 °C']) {
      final parsed = NumericAnswer.tryParse(text, defaultUnit: '°C');
      expect(parsed, isNotNull, reason: text);
      expect((parsed!.minimum, parsed.maximum), (10, 14));
    }
    for (final text in [
      '',
      '1,000',
      '12,5',
      'NaN',
      'Infinity',
      '-Infinity',
      '1e309',
      '1e-999',
      '10 to',
      '14–10 °C',
      '12 °C trailing text',
      '12 bananas',
    ]) {
      expect(
        NumericAnswer.tryParse(text, defaultUnit: '°C'),
        isNull,
        reason: text,
      );
    }
    final question = _question();
    for (final answer in <Object>[
      '12 month',
      'NaN',
      '1e309',
      const NumericAnswer.scalar(double.nan, unit: '°C'),
      const NumericAnswer.scalar(double.infinity, unit: '°C'),
      const NumericAnswer.interval(10, double.infinity, unit: '°C'),
      const NumericAnswer.scalar(12, unit: 'unknown'),
    ]) {
      final grade = format.grade(question, answer).single;
      expect(grade.rating, fsrs.Rating.again, reason: '$answer');
      expect(
        () => jsonEncode(grade.payload),
        returnsNormally,
        reason: 'invalid input must not write nonfinite JSON',
      );
    }
    expect(() => format.grade(question, 12), throwsArgumentError);
  });

  test('Celsius and Fahrenheit endpoints preserve exact and near grading', () {
    final celsius = _question();
    final fahrenheit = _question(displayUnit: '°F');
    expect((fahrenheit.displayMinimum, fahrenheit.displayMaximum), (50, 57.2));
    for (final (c, f, rating) in [
      (10.0, 50.0, fsrs.Rating.good),
      (14.0, 57.2, fsrs.Rating.good),
      (8.0, 46.4, fsrs.Rating.hard),
      (16.0, 60.8, fsrs.Rating.hard),
      (7.99, 46.382, fsrs.Rating.again),
      (16.01, 60.818, fsrs.Rating.again),
    ]) {
      for (final question in [celsius, fahrenheit]) {
        expect(
          format
              .grade(question, NumericAnswer.scalar(c, unit: '°C'))
              .single
              .rating,
          rating,
        );
        expect(
          format
              .grade(question, NumericAnswer.scalar(f, unit: '°F'))
              .single
              .rating,
          rating,
        );
      }
    }
    expect(format.grade(fahrenheit, '50–57.2').single.rating, fsrs.Rating.good);
    expect(format.grade(celsius, '50–57.2 °F').single.rating, fsrs.Rating.good);
  });

  test('decimal temperature scalars are exact in either canonical and display unit', () {
    for (final (celsius, fahrenheit) in [(16.4, 61.52), (23.2, 73.76)]) {
      for (final canonicalUnit in ['°C', '°F']) {
        for (final displayUnit in ['°C', '°F']) {
          final question = _question(
            minimum: canonicalUnit == '°C' ? celsius : fahrenheit,
            maximum: null,
            canonicalUnit: canonicalUnit,
            displayUnit: displayUnit,
            tolerance: 0,
          );
          final displayed = displayUnit == '°C' ? celsius : fahrenheit;
          expect(question.displayMinimum, displayed);
          expect(question.displayMaximum, displayed);
          for (final answer in <Object>[
            NumericAnswer.scalar(celsius, unit: '°C'),
            NumericAnswer.scalar(fahrenheit, unit: '°F'),
            '$celsius °C',
            '$fahrenheit °F',
            '$displayed',
          ]) {
            expect(
              NumericFormat.outcome(question, answer),
              NumericOutcome.exact,
              reason: '$canonicalUnit / $displayUnit: $answer',
            );
            expect(
              format.grade(question, answer).single.rating,
              fsrs.Rating.good,
            );
          }
        }
      }
    }
  });

  test(
    'genuine decimal interval endpoints accept the range without widening it',
    () {
      for (final canonicalUnit in ['°C', '°F']) {
        for (final displayUnit in ['°C', '°F']) {
          final question = _question(
            minimum: canonicalUnit == '°C' ? 16.4 : 61.52,
            maximum: canonicalUnit == '°C' ? 23.2 : 73.76,
            canonicalUnit: canonicalUnit,
            displayUnit: displayUnit,
            tolerance: 0,
          );
          expect(question.allowsInterval, isTrue);
          expect((
            question.displayMinimum,
            question.displayMaximum,
          ), displayUnit == '°C' ? (16.4, 23.2) : (61.52, 73.76));
          for (final answer in <Object>[
            const NumericAnswer.scalar(16.4, unit: '°C'),
            const NumericAnswer.scalar(23.2, unit: '°C'),
            const NumericAnswer.scalar(61.52, unit: '°F'),
            const NumericAnswer.scalar(73.76, unit: '°F'),
            const NumericAnswer.interval(16.4, 23.2, unit: '°C'),
            const NumericAnswer.interval(61.52, 73.76, unit: '°F'),
            '16.4–23.2 °C',
            '61.52–73.76 °F',
          ]) {
            expect(
              format.grade(question, answer).single.rating,
              fsrs.Rating.good,
            );
          }
          for (final answer in <Object>[
            const NumericAnswer.scalar(16.399999, unit: '°C'),
            const NumericAnswer.scalar(23.200001, unit: '°C'),
            const NumericAnswer.scalar(61.519999, unit: '°F'),
            const NumericAnswer.scalar(73.760001, unit: '°F'),
            const NumericAnswer.interval(16.399999, 23.2, unit: '°C'),
            const NumericAnswer.interval(16.4, 23.200001, unit: '°C'),
            const NumericAnswer.interval(61.519999, 73.76, unit: '°F'),
            const NumericAnswer.interval(61.52, 73.760001, unit: '°F'),
          ]) {
            expect(
              format.grade(question, answer).single.rating,
              fsrs.Rating.again,
              reason:
                  'a nearby external endpoint is still outside the exact range',
            );
          }
        }
      }
    },
  );

  test(
    'decimal outer tolerance has inclusive boundaries and no extra epsilon',
    () {
      for (final displayUnit in ['°C', '°F']) {
        final question = _question(
          minimum: 16.4,
          maximum: null,
          displayUnit: displayUnit,
          exactTolerance: 0,
          tolerance: 0.2,
        );
        for (final answer in <Object>[
          const NumericAnswer.scalar(16.6, unit: '°C'),
          const NumericAnswer.scalar(16.2, unit: '°C'),
          const NumericAnswer.scalar(61.88, unit: '°F'),
          const NumericAnswer.scalar(61.16, unit: '°F'),
          '16.6 °C',
          '16.2 °C',
          '61.88 °F',
          '61.16 °F',
        ]) {
          expect(NumericFormat.outcome(question, answer), NumericOutcome.near);
          expect(
            format.grade(question, answer).single.rating,
            fsrs.Rating.hard,
          );
        }
        for (final answer in <Object>[
          const NumericAnswer.scalar(16.600001, unit: '°C'),
          const NumericAnswer.scalar(16.199999, unit: '°C'),
          const NumericAnswer.scalar(61.880001, unit: '°F'),
          const NumericAnswer.scalar(61.159999, unit: '°F'),
          '16.600001 °C',
          '16.199999 °C',
          '61.880001 °F',
          '61.159999 °F',
        ]) {
          expect(NumericFormat.outcome(question, answer), NumericOutcome.wrong);
          expect(
            format.grade(question, answer).single.rating,
            fsrs.Rating.again,
          );
        }
      }
    },
  );

  test('raw decimal precision cannot collapse a wrong legal threshold into the answer', () {
    final question = _question(
      relation: 'MIN_AGEING',
      minimum: 38,
      maximum: null,
      canonicalUnit: 'month',
      displayUnit: 'month',
      tolerance: 0,
    );
    for (final text in ['38.0000000000000001', '37.999999999999999']) {
      expect(NumericAnswer.tryParse(text, defaultUnit: 'month'), isNull);
      final grade = format.grade(question, text).single;
      expect(grade.rating, fsrs.Rating.again);
      expect(() => jsonEncode(grade.payload), returnsNormally);
    }
    for (final (text, value) in [
      ('0.10', 0.1),
      ('3.8e1', 38.0),
      ('.5', 0.5),
      ('38.', 38.0),
    ]) {
      final parsed = NumericAnswer.tryParse(text, defaultUnit: 'month');
      expect(parsed, isNotNull, reason: 'equivalent decimal notation: $text');
      expect(parsed!.minimum, value);
    }
    for (final text in ['3.8e1', '38.']) {
      expect(format.grade(question, text).single.rating, fsrs.Rating.good);
    }
  });

  test(
    'large finite temperature conversions avoid an overflowing intermediate',
    () {
      expect(convertTemperature(5e307, fromUnit: '°C', toUnit: '°F'), 9e307);
      expect(convertTemperature(-5e307, fromUnit: '°C', toUnit: '°F'), -9e307);
      expect(convertTemperature(9e307, fromUnit: '°F', toUnit: '°C'), 5e307);
      expect(convertTemperature(-9e307, fromUnit: '°F', toUnit: '°C'), -5e307);
      expect(
        () =>
            convertTemperature(double.maxFinite, fromUnit: '°C', toUnit: '°F'),
        throwsArgumentError,
      );
      expect(
        () =>
            convertTemperature(-double.maxFinite, fromUnit: '°C', toUnit: '°F'),
        throwsArgumentError,
      );
    },
  );

  test('impossible numeric metadata and conversion overflow fail closed', () {
    for (final question in [
      _question(minimum: double.nan),
      _question(maximum: double.infinity),
      _question(minimum: 20, maximum: 10),
      _question(canonicalUnit: ''),
      _question(displayUnit: 'month'),
      _question(exactTolerance: -1),
      _question(exactTolerance: 3, tolerance: 2),
      _question(tolerance: double.infinity),
      _question(
        minimum: double.maxFinite,
        maximum: double.maxFinite,
        displayUnit: '°F',
      ),
      _question(
        relation: 'MIN_AGEING',
        canonicalUnit: 'month',
        displayUnit: 'month',
        tolerance: 1,
      ),
    ]) {
      final grade = format
          .grade(question, const NumericAnswer.scalar(12, unit: '°C'))
          .single;
      expect(grade.rating, fsrs.Rating.again);
      expect(() => jsonEncode(grade.payload), returnsNormally);
    }
    expect(
      () => convertTemperature(double.maxFinite, fromUnit: '°C', toUnit: '°F'),
      throwsArgumentError,
    );
    expect(
      () => convertTemperature(12, fromUnit: 'month', toUnit: '°F'),
      throwsArgumentError,
    );
  });

  test(
    'templates reject reverse, invalid tolerances and regulatory approximation',
    () {
      List<String> problems(QuestionTemplate template) =>
          format.templateProblems(
            template,
            relationTypes: {'TEST_TEMPERATURE', ...regulatoryRelationTypes},
          );
      expect(problems(_template()), isEmpty);
      expect(problems(_template(parameters: null)), isEmpty);
      expect(problems(_template(direction: 'reverse')), isNotEmpty);
      for (final parameters in <Object>[
        {'exact_tolerance': -1, 'tolerance': 2},
        {'exact_tolerance': 3, 'tolerance': 2},
        {'exact_tolerance': '0', 'tolerance': 2},
        {'tolerance': 'Infinity'},
        {'tolerance': null},
        [],
      ]) {
        expect(
          problems(_template(parameters: parameters)),
          isNotEmpty,
          reason: '$parameters',
        );
      }
      expect(
        problems(
          _template(
            relation: 'MIN_AGEING',
            parameters: {'exact_tolerance': 0, 'tolerance': 0},
          ),
        ),
        isEmpty,
      );
      expect(
        problems(
          _template(
            relation: 'MIN_AGEING',
            parameters: {'exact_tolerance': 0, 'tolerance': 0.001},
          ),
        ),
        isNotEmpty,
      );
      expect(
        problems(
          _template(
            relation: 'MIN_AGEING',
            parameters: {'exact_tolerance': 0.001, 'tolerance': 0.001},
          ),
        ),
        isNotEmpty,
      );
      for (final relation in regulatoryRelationTypes) {
        expect(
          problems(
            _template(relation: relation, parameters: {'tolerance': 0.01}),
          ),
          isNotEmpty,
          reason: relation,
        );
      }
    },
  );

  group('numeric generation, settings and durable review', () {
    late AppDatabase db;
    late TestClock time;
    late ExercisePresenter presenter;

    setUp(() async {
      db = openTestDatabase();
      time = TestClock(DateTime.utc(2026, 10, 1, 9));
      await CurriculumIngester(
        db,
        clock: time.clock,
      ).ingest(numericTestDataset());
      presenter = ExercisePresenter(db, clock: time.clock);
    });
    tearDown(() => db.close());

    Future<NumericQuestion> present(String item, String template) async =>
        await presenter.present(item, template, seed: 37) as NumericQuestion;

    test(
      'ingestion generates quantities and Fahrenheit uses the existing setting',
      () async {
        final generated = await db
            .customSelect(
              "SELECT knowledge_item_id FROM questions q JOIN question_templates t ON t.id=q.question_template_id WHERE t.mode='numeric'",
            )
            .get();
        expect(
          generated.map((row) => row.read<String>('knowledge_item_id')).toSet(),
          {_minimumItem, _temperatureItem},
        );
        final legal = await present(_minimumItem, _minimumTemplate);
        expect(legal.options, isEmpty);
        expect(legal.itemIds, [_minimumItem]);
        expect((legal.canonicalMinimum, legal.canonicalUnit), (38, 'month'));
        final celsius = await present(_temperatureItem, _temperatureTemplate);
        await LearnerSettings(
          db,
          clock: time.clock,
        ).setTemperatureUnit(TemperatureUnit.fahrenheit);
        final fahrenheit = await present(
          _temperatureItem,
          _temperatureTemplate,
        );
        expect((celsius.displayUnit, fahrenheit.displayUnit), ('°C', '°F'));
        expect(
          (fahrenheit.displayMinimum, fahrenheit.displayMaximum),
          (50, 57.2),
        );
        expect(
          presenter.grade(celsius, '14').single.rating,
          presenter.grade(fahrenheit, '57.2').single.rating,
        );
        expect(
          (await present(_minimumItem, _minimumTemplate)).displayUnit,
          'month',
        );
      },
    );

    test('an ambiguous current quantity suppresses generation and presentation', () async {
      await db.writeCurriculum(() async {
        await db.customStatement(
          "INSERT INTO knowledge_nodes (id,node_type,name,name_norm) VALUES ('n_qty_numeric_conflict','quantity','15 °C','15 c')",
        );
        await db.customStatement(
          "INSERT INTO quantity_values (knowledge_node_id,minimum,unit) VALUES ('n_qty_numeric_conflict',15,'°C')",
        );
        await db.customStatement(
          "INSERT INTO knowledge_relations VALUES ('n_geo_volnay','TEST_TEMPERATURE','n_qty_numeric_conflict','2026-01-01',NULL)",
        );
        await QuestionGenerator(db, today: '2026-10-01').generate();
      });
      final generated = await db
          .customSelect(
            "SELECT * FROM questions WHERE knowledge_item_id='$_temperatureItem'",
          )
          .get();
      expect(generated, isEmpty);
      await expectLater(
        present(_temperatureItem, _temperatureTemplate),
        throwsA(isA<StateError>()),
      );
      await db.writeCurriculum(() async {
        await db.customStatement(
          "UPDATE knowledge_relations SET valid_until='2026-09-30' WHERE object_id='n_qty_numeric_conflict'",
        );
        await QuestionGenerator(db, today: '2026-10-01').generate();
      });
      expect(
        (await present(
          _temperatureItem,
          _temperatureTemplate,
        )).canonicalMinimum,
        10,
        reason:
            'retired competing evidence no longer blocks the current question',
      );
    });

    test(
      'one numeric answer writes one FSRS update and survives JSON backup',
      () async {
        await LearnerSettings(
          db,
          clock: time.clock,
        ).setTemperatureUnit(TemperatureUnit.fahrenheit);
        final question = await present(_temperatureItem, _temperatureTemplate);
        final grades = presenter.grade(question, '50–57.2');
        expect(grades.single.rating, fsrs.Rating.good);
        final reviews = ReviewService(
          db,
          clock: time.clock,
          schedulerFactory: unfuzzedScheduler,
        );
        final results = await reviews.recordExercise(
          question,
          grades,
          responseTime: const Duration(milliseconds: 1850),
        );
        expect(results, hasLength(1));
        expect(results.single.after.reps, 1);
        expect(results.single.after.lastReview, time.now);
        final events = await db.select(db.reviewEvents).get();
        expect(events, hasLength(1));
        final event = events.single;
        expect(
          (
            event.knowledgeItemId,
            event.questionTemplateId,
            event.seed,
            event.responseMs,
          ),
          (_temperatureItem, _temperatureTemplate, 37, 1850),
        );
        expect(event.rating, fsrs.Rating.good.value);
        expect(event.exerciseId, isNull);
        expect(await db.select(db.reviewEventOptions).get(), isEmpty);
        final payload =
            jsonDecode(event.answerPayload!) as Map<String, dynamic>;
        expect(payload, containsPair('outcome', 'exact'));
        expect(payload['raw'], '50–57.2');
        final canonicalAnswer =
            payload['canonical_answer'] as Map<String, dynamic>;
        expect(canonicalAnswer['minimum'], closeTo(10, 1e-12));
        expect(canonicalAnswer['maximum'], closeTo(14, 1e-12));
        expect(canonicalAnswer['unit'], '°C');
        expect(payload['display_answer'], {
          'minimum': 50,
          'maximum': 57.2,
          'unit': '°F',
          'is_interval': true,
        });
        final backup = await UserDataBackup(db, clock: time.clock).exportJson();
        expect(() => jsonDecode(backup), returnsNormally);
        final destination = openTestDatabase();
        try {
          await CurriculumIngester(
            destination,
            clock: time.clock,
          ).ingest(numericTestDataset());
          final summary = await UserDataBackup(
            destination,
            clock: time.clock,
          ).import(backup);
          expect(summary.reviews, 1);
          expect(
            await destination.select(destination.reviewEvents).getSingle(),
            event,
          );
          expect(
            await destination.select(destination.reviewStates).getSingle(),
            results.single.after,
          );
          expect(
            (await LearnerSettings(destination).current()).temperatureUnit,
            TemperatureUnit.fahrenheit,
          );
        } finally {
          await destination.close();
        }
      },
    );

    test(
      'nonfinite submitted values fail closed and can be backed up',
      () async {
        final question = await present(_temperatureItem, _temperatureTemplate);
        final grades = presenter.grade(
          question,
          const NumericAnswer.scalar(double.infinity, unit: '°C'),
        );
        expect(grades.single.rating, fsrs.Rating.again);
        final reviews = ReviewService(
          db,
          clock: time.clock,
          schedulerFactory: unfuzzedScheduler,
        );
        await reviews.recordExercise(question, grades);
        final event = await db.select(db.reviewEvents).getSingle();
        expect(() => jsonDecode(event.answerPayload!), returnsNormally);
        final payload =
            jsonDecode(event.answerPayload!) as Map<String, dynamic>;
        expect(
          (payload['submitted'] as Map<String, dynamic>)['minimum'],
          isNull,
        );
        expect(payload['canonical_answer'], isNull);
        final backup = await UserDataBackup(db, clock: time.clock).exportJson();
        expect(() => jsonDecode(backup), returnsNormally);
        expect((await db.select(db.reviewStates).getSingle()).reps, 1);
      },
    );
  });

  test('all 21 bundled quantities get one scoped numeric question without an answer leak', () async {
    final db = openTestDatabase();
    final time = TestClock(DateTime.utc(2026, 10, 1, 9));
    try {
      await CurriculumIngester(
        db,
        clock: time.clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(bundledDataset());
      final questions = await db
          .customSelect(
            "SELECT q.knowledge_item_id,q.question_template_id FROM questions q JOIN question_templates t ON t.id=q.question_template_id WHERE t.mode='numeric' ORDER BY q.knowledge_item_id",
          )
          .get();
      expect(questions, hasLength(21));
      final dataset = bundledDataset();
      final quantityNodes = dataset.quantityValues
          .map((value) => value.knowledgeNodeId)
          .toSet();
      final currentItems = await KnowledgeGraph(
        db,
        clock: time.clock,
      ).currentItems();
      final quantityItems = currentItems
          .where((item) => quantityNodes.contains(item.objectId))
          .map((item) => item.id)
          .toSet();
      expect(
        questions.map((row) => row.read<String>('knowledge_item_id')).toSet(),
        quantityItems,
      );
      final presenter = ExercisePresenter(db, clock: time.clock);
      var legalCount = 0;
      var statisticCount = 0;
      for (final row in questions) {
        final question = await presenter.present(
          row.read<String>('knowledge_item_id'),
          row.read<String>('question_template_id'),
          seed: 41,
        ) as NumericQuestion;
        expect(question.prompt, isNot(contains(question.answer.name)));
        expect(question.allowsInterval, isFalse);
        expect((question.exactTolerance, question.tolerance), (0, 0));
        expect(
          presenter
              .grade(
                question,
                NumericAnswer.scalar(
                  question.canonicalMinimum,
                  unit: question.canonicalUnit,
                ),
              )
              .single
              .rating,
          fsrs.Rating.good,
        );
        expect(
          presenter
              .grade(
                question,
                NumericAnswer.scalar(
                  question.canonicalMinimum + 1,
                  unit: question.canonicalUnit,
                ),
              )
              .single
              .rating,
          fsrs.Rating.again,
        );
        if (question.isLegalMinimum) {
          legalCount++;
          if (question.questionTemplateId ==
              'qt_champagne_min_ageing_fwd_numeric') {
            expect(question.prompt, contains('non-vintage'));
            expect(question.prompt, contains('from tirage'));
          } else if (question.questionTemplateId ==
              'qt_min_ageing_fwd_numeric') {
            expect(question.prompt, contains('non-Riserva'));
            expect(question.prompt, contains('1 November'));
          } else if (question.questionTemplateId ==
              'qt_winzersekt_lees_fwd_numeric') {
            expect(question.prompt, contains('uninterrupted time on the lees'));
          } else if (question.knowledgeItemId.startsWith('ki_hu_tokaji_')) {
            expect(
              question.prompt,
              contains('grapes harvested from August 2025'),
            );
            expect(question.prompt, contains('wooden barrels'));
          }
        } else {
          statisticCount++;
          expect(question.relationType, 'STATISTIC_VALUE');
          expect(question.prompt, contains('2024'));
          expect(question.prompt, contains('cited survey'));
        }
      }
      expect((legalCount, statisticCount), (10, 11));
    } finally {
      await db.close();
    }
  });
}
