import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _templateId = 'qt_wset_l3_winemaking_special_principles_47';
const _ids = <String>{
  'ki_wset_sf_adelaide_spark',
  'ki_wset_sf_alsace_cremant',
  'ki_wset_sf_anderson_spark',
  'ki_wset_sf_asti_cost',
  'ki_wset_sf_asti_current',
  'ki_wset_sf_asti_environment',
  'ki_wset_sf_beaumes_cost',
  'ki_wset_sf_beaumes_fresh',
  'ki_wset_sf_beaumes_origin',
  'ki_wset_sf_bourgogne_cremant',
  'ki_wset_sf_bourgogne_environment',
  'ki_wset_sf_bourgogne_styles',
  'ki_wset_sf_cap_environment',
  'ki_wset_sf_cava_aging',
  'ki_wset_sf_cava_cost',
  'ki_wset_sf_cava_guarda',
  'ki_wset_sf_cava_sites',
  'ki_wset_sf_champagne_cost',
  'ki_wset_sf_champagne_cru',
  'ki_wset_sf_champagne_districts',
  'ki_wset_sf_champagne_white_black',
  'ki_wset_sf_cremant_cellar_cost',
  'ki_wset_sf_loire_cremant',
  'ki_wset_sf_newworld_spark_cost',
  'ki_wset_sf_port_age_label',
  'ki_wset_sf_port_autovinifier',
  'ki_wset_sf_port_cost',
  'ki_wset_sf_port_grapes',
  'ki_wset_sf_port_mechanical',
  'ki_wset_sf_prosecco_cost',
  'ki_wset_sf_prosecco_environment',
  'ki_wset_sf_prosecco_hills',
  'ki_wset_sf_rutherglen_climate',
  'ki_wset_sf_rutherglen_tiers',
  'ki_wset_sf_saumur_spark',
  'ki_wset_sf_sekt_cost',
  'ki_wset_sf_sekt_environment',
  'ki_wset_sf_sekt_method',
  'ki_wset_sf_sekt_origin',
  'ki_wset_sf_sherry_climate',
  'ki_wset_sf_sherry_cost',
  'ki_wset_sf_sherry_current_route',
  'ki_wset_sf_sherry_manzanilla',
  'ki_wset_sf_sherry_palo_cortado',
  'ki_wset_sf_vouvray_environment',
  'ki_wset_sf_vouvray_spark',
  'ki_wset_sf_yarra_spark',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == _templateId,
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(template);
  late AppDatabase db;

  setUpAll(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime.utc(2026, 9, 29, 18)),
    ).ingest(dataset);
  });

  tearDownAll(() async => db.close());

  test('47 distinct core principles have cited, cue-resistant choices', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(template.mode, AuthoredChoiceFormat.formatId);
    expect(template.relationType, 'PRINCIPLE_EXPLANATION');
    expect(choices.keys.toSet(), _ids);
    final earlierChoiceIds = <String>{};
    for (final other in dataset.questionTemplates) {
      if (other.mode != AuthoredChoiceFormat.formatId ||
          other.id == _templateId) {
        continue;
      }
      earlierChoiceIds.addAll(AuthoredChoiceFormat.itemChoicesOf(other).keys);
    }
    expect(_ids.intersection(earlierChoiceIds), isEmpty);

    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final mappings = {
      for (final row in dataset.certificationKnowledgeMappings)
        if (row.certificationId == 'WSET_L3') row.knowledgeItemId: row,
    };
    final citations = {
      for (final row in dataset.knowledgeItemCitations)
        (row.knowledgeItemId, row.sourceCitationId),
    };
    final sources = {
      for (final source in dataset.sourceCitations) source.id: source,
    };
    final positions = <int, int>{};
    final prompts = <String>{};
    final optionSets = <String>{};
    for (final entry in choices.entries) {
      final id = entry.key;
      final choice = entry.value;
      final answer = choice.options[choice.correctIndex];
      final lengths = choice.options.map((option) => option.length).toList();
      expect(items[id]!.domainId, 'winemaking', reason: id);
      expect(items[id]!.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(items[id]!.verificationStatus, 'unverified', reason: id);
      expect(items[id]!.mcqDisabled, isTrue, reason: id);
      expect(mappings[id]!.importance, 'core', reason: id);
      expect(citations, contains((id, choice.sourceCitationId)), reason: id);
      final source = sources[choice.sourceCitationId]!;
      final sourceUrl = Uri.parse(source.url!);
      expect(sourceUrl.scheme, 'https', reason: id);
      expect(sourceUrl.host, isNotEmpty, reason: id);
      expect(sourceUrl.path.length, greaterThan(1), reason: id);
      expect(choice.prompt.length, greaterThan(75), reason: id);
      expect(choice.explanation.length, greaterThan(75), reason: id);
      expect(choice.options, hasLength(4), reason: id);
      expect(choice.options.toSet(), hasLength(4), reason: id);
      expect(
        choice.prompt.toLowerCase(),
        isNot(contains(answer.toLowerCase())),
        reason: 'prompt reveals answer for $id',
      );
      expect(
        choice.options.any(
          (option) => RegExp(
            r'\b(always|never|every|only|all|guaranteed|guarantee|solely|impossible|cannot)\b',
            caseSensitive: false,
          ).hasMatch(option),
        ),
        isFalse,
        reason: 'absolute wording cue for $id',
      );
      expect(
        lengths[choice.correctIndex] ==
                lengths.reduce((a, b) => a > b ? a : b) &&
            lengths
                    .where((length) => length == lengths[choice.correctIndex])
                    .length ==
                1,
        isFalse,
        reason: 'key uniquely longest: $id',
      );
      expect(
        lengths[choice.correctIndex] ==
                lengths.reduce((a, b) => a < b ? a : b) &&
            lengths
                    .where((length) => length == lengths[choice.correctIndex])
                    .length ==
                1,
        isFalse,
        reason: 'key uniquely shortest: $id',
      );
      expect(prompts.add(choice.prompt), isTrue, reason: id);
      optionSets.add(choice.options.join('|'));
      positions[choice.correctIndex] =
          (positions[choice.correctIndex] ?? 0) + 1;
    }
    expect(positions, {0: 12, 1: 12, 2: 12, 3: 11});
    expect(optionSets, hasLength(47));
    expect(
      choices.values.map((choice) => choice.sourceCitationId).toSet(),
      hasLength(34),
    );
  });

  test(
    'each choice is generated and available in Level 3 study cards',
    () async {
      final questions = await db.select(db.questions).get();
      final generated = questions
          .where((row) => row.questionTemplateId == _templateId)
          .map((row) => row.knowledgeItemId)
          .toSet();
      expect(generated, _ids);
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L3'))
          card.itemId: card,
      };
      for (final id in _ids) {
        expect(
          cards[id]!.formats.map((format) => format.mode),
          contains('authored_choice'),
          reason: id,
        );
      }
    },
  );

  test('useful-practice coverage closes 47 winemaking principles', () async {
    const path = 'assets/curriculum/coverage_policy.yaml';
    final report = await CoverageChecker(
      db,
      CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
    ).check('WSET_L3', on: '2026-09-29');
    final byId = {for (final item in report.items) item.id: item};
    for (final id in _ids) {
      expect(byId[id]!.hasUsefulPractice, isTrue, reason: id);
      expect(byId[id]!.servedFormats, contains('authored_choice'), reason: id);
    }
    final remaining = report.items.where(
      (row) =>
          row.item.domainId == 'winemaking' &&
          row.isCore &&
          row.item.relationType == 'PRINCIPLE_EXPLANATION' &&
          !row.hasUsefulPractice,
    );
    expect(remaining, isEmpty);
    expect(remaining.any((row) => _ids.contains(row.id)), isFalse);
  });

  test(
    'regional, regulatory and process questions present and grade',
    () async {
      for (final id in [
        'ki_wset_sf_asti_current',
        'ki_wset_sf_cava_guarda',
        'ki_wset_sf_sekt_origin',
        'ki_wset_sf_sherry_current_route',
      ]) {
        final exercise = await ExercisePresenter(db).present(
          id,
          _templateId,
          seed: 17,
          certificationId: 'WSET_L3',
        ) as AuthoredChoiceQuestion;
        expect(
          exercise.answer.name,
          choices[id]!.options[choices[id]!.correctIndex],
        );
        expect(exercise.options, hasLength(4));
        expect(exercise.sourceCitationId, choices[id]!.sourceCitationId);
        expect(
          const AuthoredChoiceFormat()
              .grade(exercise, exercise.answer)
              .single
              .rating,
          fsrs.Rating.good,
        );
      }
    },
  );
}
