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

const _templateId = 'qt_wset_l3_winemaking_regional_principles_54';
const _ids = <String>{
  'ki_reg_ah_neusiedler_zweigelt',
  'ki_reg_ah_tokaj_cellar',
  'ki_reg_de_baden_pinot_light',
  'ki_reg_de_baden_pinot_wood',
  'ki_reg_de_franken_muller_fresh',
  'ki_reg_de_rheinhessen_grauburgunder_vessels',
  'ki_reg_de_rheinhessen_silvaner_range',
  'ki_reg_fe_beaujolais_maturation',
  'ki_reg_fe_beaujolais_pressing',
  'ki_reg_fm_bandol_structure',
  'ki_reg_fm_maury_structure',
  'ki_reg_fr_chablis_quality',
  'ki_reg_fs_savennieres_dry',
  'ki_reg_gr_agiorgitiko_young',
  'ki_reg_gr_naoussa_style_choices',
  'ki_reg_gr_nemea_extraction_oak',
  'ki_reg_gr_xinomavro_structure',
  'ki_reg_ib_montsant_controls',
  'ki_reg_na_oregon_series_controls',
  'ki_reg_na_slh_chardonnay_range',
  'ki_reg_sa_leyda_cellar',
  'ki_reg_sa_mendoza_cellar_response',
  'ki_reg_sa_mendoza_source_factor',
  'ki_reg_sa_mendoza_yeast_factor',
  'ki_wset_apply_alentejo_production',
  'ki_wset_apply_levante_white_route',
  'ki_wset_apply_niederosterreich_production',
  'ki_wset_eu_dolcetto_alba_use',
  'ki_wset_eu_frascati_steel_lees',
  'ki_wset_eu_penedes_xarello_oak',
  'ki_wset_nw_goulburn_heat_water',
  'ki_wset_nw_inland_water_costs',
  'ki_wset_nw_lodi_style_choices',
  'ki_wset_nw_ontario_icewine_selection',
  'ki_wset_nw_worcester_wine_context',
  'ki_wset_nwa_aconcagua_red',
  'ki_wset_nwa_cachapoal_carmenere',
  'ki_wset_nwa_canterbury_riesling',
  'ki_wset_nwa_curico_maule_white',
  'ki_wset_nwa_elim_sauvignon',
  'ki_wset_nwa_elqui_syrah',
  'ki_wset_nwa_finger_lakes_riesling',
  'ki_wset_nwa_gisborne_chardonnay',
  'ki_wset_nwa_great_southern_red',
  'ki_wset_nwa_great_southern_riesling',
  'ki_wset_nwa_leyda_san_antonio_white',
  'ki_wset_nwa_limari_chardonnay',
  'ki_wset_nwa_maule_southern_red',
  'ki_wset_nwa_mendocino_chardonnay',
  'ki_wset_nwa_monterey_chardonnay',
  'ki_wset_nwa_nelson_aromatics',
  'ki_wset_nwa_paso_santa_maria_routes',
  'ki_wset_nwa_santa_cruz_pinot',
  'ki_wset_nwa_south_coast_chardonnay',
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

  test('54 distinct core principles have cited, cue-resistant choices', () {
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
    expect(positions, {0: 14, 1: 14, 2: 13, 3: 13});
    expect(optionSets, hasLength(54));
    expect(
      choices.values.map((choice) => choice.sourceCitationId).toSet(),
      hasLength(40),
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

  test('useful-practice coverage leaves 47 regional sparkling or fortified principles', () async {
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
    expect(remaining, hasLength(47));
    expect(remaining.any((row) => _ids.contains(row.id)), isFalse);
  });

  test('regional, producer and process questions present and grade', () async {
    for (final id in [
      'ki_reg_ah_tokaj_cellar',
      'ki_reg_na_oregon_series_controls',
      'ki_wset_nw_ontario_icewine_selection',
      'ki_wset_nwa_limari_chardonnay',
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
  });
}
