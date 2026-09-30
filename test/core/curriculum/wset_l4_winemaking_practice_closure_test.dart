import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _globalId = 'qt_wset_l4_winemaking_principles_global_22';
const _regionalId = 'qt_wset_l4_winemaking_principles_regional_27';
const _causalId = 'qt_wset_l4_winemaking_causal_closure_2';
const _caseId = 'qt_wset_l4_winemaking_case_criteria_23';

const _globalIds = <String>{
  'ki_d1target_nolo_balance',
  'ki_d1target_pack_freight',
  'ki_d1target_qc_iso_trace',
  'ki_d4nw_argentina_market',
  'ki_d4nw_argentina_terms',
  'ki_d4nw_au_sea_label',
  'ki_d4nw_au_south_australia',
  'ki_d4nw_au_tasmania',
  'ki_d4nw_au_victoria',
  'ki_d4nw_chile_coast_method',
  'ki_d4nw_nz_method',
  'ki_d4nw_nz_regions',
  'ki_d4nw_us_california',
  'ki_d4nw_us_oregon',
  'ki_d4nw_us_washington',
  'ki_d4nw_za_association',
  'ki_d4nw_za_variation',
  'ki_spark_alcohol_tartrate',
  'ki_spark_bidule',
  'ki_spark_lees_decline',
  'ki_spark_liner',
  'ki_spark_low_liner',
};

const _regionalIds = <String>{
  'ki_reg_ah_vienna_joint',
  'ki_reg_cn_ningxia_deficit_chemistry',
  'ki_reg_cn_shandong_blend',
  'ki_reg_cn_shandong_marselan_extraction',
  'ki_reg_cn_shandong_separate_ferments',
  'ki_reg_cn_xinjiang_shade_style',
  'ki_reg_cn_yunnan_2017_blend',
  'ki_reg_fe_jura_jaune_time',
  'ki_reg_fe_jura_non_topped',
  'ki_reg_fe_jura_paille_drying',
  'ki_reg_fe_jura_topped',
  'ki_reg_gr_kotsifali_softness',
  'ki_reg_gr_liatiko_dry_expression',
  'ki_reg_gr_mandilaria_structure',
  'ki_reg_gr_moschofilero_white',
  'ki_reg_gr_robola_handling',
  'ki_reg_gr_samos_dry_muscat',
  'ki_reg_gr_vidiano_palate',
  'ki_reg_gr_vilana_palate',
  'ki_reg_inc_ripasso_pomace',
  'ki_reg_inc_ripasso_structure',
  'ki_reg_na_long_island_cab_franc_style',
  'ki_reg_oa_mclaren_gentle_cap',
  'ki_reg_oa_mclaren_whole_berries',
  'ki_reg_oa_pinotage_oak_comparison',
  'ki_reg_sa_itata_skin_time',
  'ki_reg_sa_itata_wholeberries',
};

const _causalIds = <String>{
  'ki_reason_mlf_conversion',
  'ki_reason_so2_molecular',
};

const _caseSubjects = <String>{
  'n_d1target_case_nolo',
  'n_d1target_case_pack',
  'n_d1target_case_qc',
  'n_d3rt_case_margaret_blend',
  'n_d4depth_case_british_frost',
  'n_d4depth_case_cava_upgrade',
  'n_d4depth_case_champagne_house',
  'n_d4depth_case_rive_offer',
  'n_d4nw_case_australian_offer',
  'n_d5f_case_fortified_list',
  'n_d5f_case_port_offer',
  'n_d5f_case_sherry_vos_stock',
  'n_fault_case_brett_rising',
  'n_fault_case_sporadic_sweet_spoilage',
  'n_fault_case_sulfur_before_bottling',
  'n_fort_case_madeira_slow',
  'n_fort_case_vdn_fresh',
  'n_reg_fe_case_jura_white_comparison',
  'n_reg_oa_case_hunter_toast',
  'n_reg_oa_case_mclaren_cap_trial',
  'n_reg_sa_case_itata_skin_trial',
  'n_spark_case_gushing_batch',
  'n_spark_case_long_closure',
};

// These whole-case pools are owned by the parallel Diploma business batch.
const _reservedBusinessSubjects = <String>{
  'n_reg_ah_case_vienna_harvest',
  'n_reg_am_case_mendoza_claim',
  'n_reg_cn_case_xinjiang_shade_style',
  'n_reg_cn_case_yunnan_blend_evidence',
  'n_reg_fe_case_jura_maturation_cash',
  'n_reg_gr_case_aromatic_whites',
  'n_reg_na_case_oregon_stem_trial',
  'n_reg_oa_case_canterbury_riesling_offer',
  'n_reg_sa_case_mendoza_yeast_trial',
};

Map<String, dynamic> _choices(String parameters) =>
    (jsonDecode(parameters) as Map<String, dynamic>)['item_choices']
        as Map<String, dynamic>;

void main() {
  final dataset = bundledDataset();
  final templates = {
    for (final template in dataset.questionTemplates) template.id: template,
  };
  final cases = templates[_caseId]!;
  final choiceGroups = {
    _globalId: _globalIds,
    _regionalId: _regionalIds,
    _causalId: _causalIds,
  };
  late AppDatabase db;
  late TrackCoverage audit;

  setUpAll(() async {
    db = openTestDatabase();
    final generation = await CurriculumIngester(
      db,
      clock: Clock.fixed(dataset.publishedAt.toUtc()),
    ).ingest(dataset);
    const policyPath = 'assets/curriculum/coverage_policy.yaml';
    audit =
        await CoverageChecker(
          db,
          CoveragePolicy.parse(
            File(policyPath).readAsStringSync(),
            path: policyPath,
          ),
        ).check(
          'WSET_L4',
          on: dataset.publishedAt.toIso8601String().substring(0, 10),
          skipped: generation.skipped,
        );
  });

  tearDownAll(() async => db.close());

  test('51 item-specific choices remain cited and Diploma-mapped', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    final sourceUrls = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    final mappings = {
      for (final mapping in dataset.certificationKnowledgeMappings)
        if (mapping.certificationId == 'WSET_L4')
          mapping.knowledgeItemId: mapping,
    };
    final allIds = <String>{};
    final positions = <int, int>{};
    final lengthRanks = <int, int>{};
    for (final entry in choiceGroups.entries) {
      final template = templates[entry.key]!;
      final choices = _choices(template.parameters!);
      expect(template.mode, 'authored_choice');
      expect(choices.keys.toSet(), entry.value);
      for (final row in choices.entries) {
        final id = row.key;
        expect(allIds.add(id), isTrue, reason: id);
        final choice = row.value as Map<String, dynamic>;
        final options = (choice['options'] as List<dynamic>).cast<String>();
        final answer = choice['correctIndex'] as int;
        final citationId = choice['sourceCitationId'] as String;
        expect(items[id]!.domainId, 'winemaking', reason: id);
        expect(items[id]!.relationType, template.relationType, reason: id);
        expect(items[id]!.verificationStatus, 'unverified', reason: id);
        expect(mappings[id]!.importance, 'core', reason: id);
        expect(options, hasLength(4), reason: id);
        expect(
          options.map((option) => option.toLowerCase()).toSet(),
          hasLength(4),
          reason: id,
        );
        expect(answer, inInclusiveRange(0, 3), reason: id);
        expect(choice['prompt'], isNotEmpty, reason: id);
        expect(choice['explanation'], isNotEmpty, reason: id);
        final keyedLength = options[answer].length;
        final distractors = [
          for (var index = 0; index < options.length; index++)
            if (index != answer) options[index],
        ];
        final lengthRank = distractors
            .where((option) => option.length < keyedLength)
            .length;
        lengthRanks[lengthRank] = (lengthRanks[lengthRank] ?? 0) + 1;
        final absoluteCue = RegExp(
          r'\b(?:all|always|every|must|never|guarantees?|necessarily|automatically|only)\b',
          caseSensitive: false,
        );
        expect(
          distractors.where(absoluteCue.hasMatch).length,
          lessThanOrEqualTo(1),
          reason: '$id needs plausible distractors beyond absolute wording',
        );
        expect(citationPairs, contains((id, citationId)), reason: id);
        expect(Uri.parse(sourceUrls[citationId]!).scheme, 'https', reason: id);
        positions[answer] = (positions[answer] ?? 0) + 1;
      }
    }
    expect(allIds, hasLength(51));
    for (final position in [0, 1, 2, 3]) {
      expect(positions[position], inInclusiveRange(10, 15));
      expect(lengthRanks[position], inInclusiveRange(9, 16));
    }
  });

  test(
    '23 case subjects retain full premises and four source-linked roles',
    () {
      final scope = CaseCriteriaFormat.scopeNodeIdsOf(cases);
      final distractors = CaseCriteriaFormat.distractorsOf(cases);
      final overrides = CaseCriteriaFormat.scenarioPromptsOf(cases);
      final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
      final cited = {
        for (final citation in dataset.knowledgeItemCitations)
          citation.knowledgeItemId,
      };
      expect(scope, _caseSubjects);
      expect(scope.intersection(_reservedBusinessSubjects), isEmpty);
      expect(distractors.keys.toSet(), scope);
      expect(overrides, hasLength(13));
      expect(CaseCriteriaFormat.datasetProblems(cases, dataset), isEmpty);
      for (final subject in scope) {
        expect(
          (overrides[subject] ?? nodes[subject]!.name).length,
          greaterThan(80),
          reason: subject,
        );
        expect(distractors[subject], hasLength(2), reason: subject);
        final roles = dataset.knowledgeItems
            .where(
              (item) =>
                  item.subjectId == subject &&
                  caseCriterionRoles.contains(item.relationType),
            )
            .toList();
        expect(roles, hasLength(4), reason: subject);
        expect(
          roles.map((item) => item.relationType).toSet(),
          caseCriterionRoles.toSet(),
          reason: subject,
        );
        for (final role in roles) {
          expect(role.domainId, 'winemaking', reason: role.id);
          expect(role.verificationStatus, 'unverified', reason: role.id);
          expect(cited, contains(role.id), reason: role.id);
        }
      }
    },
  );

  test(
    'authored questions and case pools serve without losing study modes',
    () async {
      final generated = (await db.select(db.questions).get()).where(
        (question) => choiceGroups.containsKey(question.questionTemplateId),
      );
      expect(generated, hasLength(51));
      expect(generated.map((question) => question.knowledgeItemId).toSet(), {
        ..._globalIds,
        ..._regionalIds,
        ..._causalIds,
      });
      final pools = (await db.select(db.exercisePools).get())
          .where((pool) => pool.questionTemplateId == _caseId)
          .toList();
      expect(pools, hasLength(23));
      expect(pools.map((pool) => pool.scopeNodeId).toSet(), _caseSubjects);
      final members = await db.select(db.exercisePoolItems).get();
      for (final pool in pools) {
        expect(
          members.where((member) => member.exercisePoolId == pool.id),
          hasLength(4),
          reason: pool.scopeNodeId,
        );
      }
      final winemaking = audit.domains.singleWhere(
        (domain) => domain.id == 'winemaking',
      );
      expect(winemaking.counts[CoverageMetric.core], 726);
      expect(winemaking.counts[CoverageMetric.coreUsefulPractice], 726);
      final remaining = audit.items.where(
        (row) =>
            row.item.domainId == 'winemaking' &&
            row.isCore &&
            !row.hasUsefulPractice,
      );
      expect(remaining, isEmpty);
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L4'))
          card.itemId: card,
      };
      for (final id in {..._globalIds, ..._regionalIds, ..._causalIds}) {
        expect(
          cards[id]!.formats.map((format) => format.mode).toSet(),
          containsAll({'authored_choice', 'typed', 'flashcard'}),
          reason: id,
        );
      }
      for (final id in [
        'ki_d1target_case_nolo_action',
        'ki_d5f_case_sherry_vos_stock_reason',
        'ki_spark_case_long_closure_limitation',
      ]) {
        final row = audit.items.singleWhere((item) => item.id == id);
        expect(row.servedFormats, contains('case_criteria'), reason: id);
        expect(row.servedFormats, contains('short_answer'), reason: id);
        expect(row.servedFormats, contains('typed'), reason: id);
      }
    },
  );

  test(
    'case matching grades all four roles and rejects false answers',
    () async {
      for (final id in [
        'ki_d1target_case_nolo_action',
        'ki_d5f_case_sherry_vos_stock_action',
        'ki_reg_oa_case_mclaren_cap_trial_action',
      ]) {
        final exercise = await ExercisePresenter(
          db,
        ).present(id, _caseId, seed: 19) as CaseCriteriaExercise;
        expect(exercise.prompt.length, greaterThan(80));
        expect(exercise.itemIds, hasLength(4));
        expect(exercise.options, hasLength(6));
        for (final criterion in exercise.criteria) {
          expect(criterion.sources, isNotEmpty);
          expect(criterion.sources.first.url, startsWith('https://'));
        }
        final correct = {
          for (final criterion in exercise.criteria)
            criterion.role: criterion.itemId,
        };
        const format = CaseCriteriaFormat();
        expect(
          format
              .grade(exercise, CaseCriteriaResponse(correct))
              .every((grade) => grade.rating == fsrs.Rating.good),
          isTrue,
        );
        final falseOption = exercise.options.firstWhere(
          (option) => option.explanation != null,
        );
        final withFalse = {...correct, 'CASE_REASON': falseOption.id};
        expect(
          format
              .grade(exercise, CaseCriteriaResponse(withFalse))
              .singleWhere((grade) => grade.itemId == correct['CASE_REASON'])
              .rating,
          fsrs.Rating.again,
        );
      }
    },
  );
}
