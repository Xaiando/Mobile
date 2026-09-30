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
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _principleTemplateId = 'qt_d3_geography_principle_closure_24';
const _geographyCaseTemplateId = 'qt_d3_geography_case_criteria_8';
const _serviceCaseTemplateId = 'qt_d3_service_fault_case_criteria_2';

const _principleIds = <String>{
  'ki_reg_ah_styria_context',
  'ki_reg_ah_styria_microclimates',
  'ki_reg_de_saale_unstrut_sheltered_slopes',
  'ki_reg_de_sachsen_day_night',
  'ki_reg_fe_jura_chardonnay',
  'ki_reg_fe_jura_exposure',
  'ki_reg_fe_jura_savagnin',
  'ki_reg_fe_jura_season',
  'ki_reg_gr_amyndeon_lakes',
  'ki_reg_gr_crete_northern_influence',
  'ki_reg_gr_north_soil_textures',
  'ki_reg_gr_robola_slope_context',
  'ki_reg_inc_alto_adige_air',
  'ki_reg_inc_bolgheri_breeze',
  'ki_reg_inc_bolgheri_soils',
  'ki_reg_inc_dolcetto_dry',
  'ki_reg_inc_friuli_ponca',
  'ki_reg_inc_friuli_position',
  'ki_reg_inc_matelica_inland',
  'ki_reg_inc_orvieto_grapes',
  'ki_reg_inc_orvieto_sweetness',
  'ki_reg_inc_rosso_youth',
  'ki_reg_oa_adelaide_m3_sources',
  'ki_reg_sa_itata_grapes',
};

const _geographyCases = <String>{
  'n_reg_am_case_california_sites',
  'n_reg_am_case_chile_white',
  'n_reg_am_case_pacific_northwest',
  'n_reg_gr_case_north_comparison',
  'n_reg_sh_case_au_cabernet_price',
  'n_reg_sh_case_au_shiraz_selection',
  'n_reg_sh_case_nz_white_comparison',
  'n_reg_sh_case_za_chenin_purchasing',
};

const _serviceCases = <String>{
  'n_fault_case_hot_delivery',
  'n_fault_case_lit_display',
};

void main() {
  final dataset = bundledDataset();
  final templates = {for (final row in dataset.questionTemplates) row.id: row};
  final principleTemplate = templates[_principleTemplateId]!;
  final geographyTemplate = templates[_geographyCaseTemplateId]!;
  final serviceTemplate = templates[_serviceCaseTemplateId]!;
  final choices =
      (jsonDecode(principleTemplate.parameters!)
              as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;
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

  test('24 Level 4 regional comparisons use the facts own source links', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(principleTemplate.mode, 'authored_choice');
    expect(principleTemplate.relationType, 'PRINCIPLE_EXPLANATION');
    expect(choices.keys.toSet(), _principleIds);
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citations = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    final sourceUrls = {
      for (final citation in dataset.sourceCitations) citation.id: citation.url,
    };
    final answers = <int, int>{};
    final lengthRanks = <int, int>{};
    for (final entry in choices.entries) {
      final id = entry.key;
      final choice = entry.value as Map<String, dynamic>;
      final options = (choice['options'] as List<dynamic>).cast<String>();
      final answer = choice['correctIndex'] as int;
      final citationId = choice['sourceCitationId'] as String;
      expect(items[id]!.domainId, 'geography', reason: id);
      expect(items[id]!.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(items[id]!.verificationStatus, 'unverified', reason: id);
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
      expect(citations, contains((id, citationId)), reason: id);
      expect(Uri.parse(sourceUrls[citationId]!).scheme, 'https', reason: id);
      answers[answer] = (answers[answer] ?? 0) + 1;
    }
    expect(answers, {0: 6, 1: 6, 2: 6, 3: 6});
    for (final rank in [0, 1, 2, 3]) {
      expect(lengthRanks[rank], inInclusiveRange(4, 8));
    }
  });

  test('10 full case pools retain four cited decision roles', () {
    final subjects = {
      geographyTemplate.id: _geographyCases,
      serviceTemplate.id: _serviceCases,
    };
    final citedIds = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId,
    };
    for (final template in [geographyTemplate, serviceTemplate]) {
      final scope = CaseCriteriaFormat.scopeNodeIdsOf(template);
      final distractors = CaseCriteriaFormat.distractorsOf(template);
      expect(scope, subjects[template.id], reason: template.id);
      expect(distractors.keys.toSet(), scope);
      expect(CaseCriteriaFormat.datasetProblems(template, dataset), isEmpty);
      for (final subject in scope) {
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
          expect(citedIds, contains(role.id), reason: role.id);
          expect(role.verificationStatus, 'unverified', reason: role.id);
        }
      }
    }
    final servicePrompts = CaseCriteriaFormat.scenarioPromptsOf(
      serviceTemplate,
    );
    expect(servicePrompts.keys.toSet(), _serviceCases);
    expect(
      servicePrompts['n_fault_case_hot_delivery'],
      contains('holdback samples'),
    );
    expect(
      servicePrompts['n_fault_case_lit_display'],
      contains('protected stock'),
    );
  });

  test(
    'Diploma geography and service cases serve without losing maps',
    () async {
      final generated = (await db.select(db.questions).get())
          .where(
            (question) => question.questionTemplateId == _principleTemplateId,
          )
          .toList();
      expect(generated, hasLength(24));
      expect(
        generated.map((question) => question.knowledgeItemId).toSet(),
        _principleIds,
      );
      final pools = (await db.select(db.exercisePools).get()).where(
        (pool) =>
            pool.questionTemplateId == _geographyCaseTemplateId ||
            pool.questionTemplateId == _serviceCaseTemplateId,
      );
      expect(pools, hasLength(10));
      expect(pools.map((pool) => pool.scopeNodeId).toSet(), {
        ..._geographyCases,
        ..._serviceCases,
      });
      final members = await db.select(db.exercisePoolItems).get();
      for (final pool in pools) {
        expect(
          members.where((member) => member.exercisePoolId == pool.id),
          hasLength(4),
          reason: pool.scopeNodeId,
        );
      }
      final geography = audit.domains.singleWhere(
        (domain) => domain.id == 'geography',
      );
      final service = audit.domains.singleWhere(
        (domain) => domain.id == 'service',
      );
      expect(geography.counts[CoverageMetric.core], 1121);
      expect(geography.counts[CoverageMetric.coreUsefulPractice], 1121);
      expect(geography.counts[CoverageMetric.spatial], 1673);
      final coreLocations = audit.items.where(
        (row) =>
            row.isCore &&
            row.item.domainId == 'geography' &&
            row.item.relationType == 'LOCATED_IN',
      );
      expect(coreLocations, isNotEmpty);
      expect(
        coreLocations.where(
          (row) => !row.families.contains(FormatFamily.spatial),
        ),
        isEmpty,
        reason: 'every core place-location fact must retain map-click practice',
      );
      expect(service.counts[CoverageMetric.core], 112);
      expect(service.counts[CoverageMetric.coreUsefulPractice], 112);
      expect(
        audit.items.where(
          (row) =>
              row.isCore &&
              (row.item.domainId == 'geography' ||
                  row.item.domainId == 'service') &&
              !row.hasUsefulPractice,
        ),
        isEmpty,
      );
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L4'))
          card.itemId: card,
      };
      for (final id in _principleIds) {
        expect(
          cards[id]!.formats.map((format) => format.mode).toSet(),
          containsAll({'authored_choice', 'typed', 'flashcard'}),
          reason: id,
        );
      }
      for (final id in [
        'ki_reg_am_case_california_sites_reason',
        'ki_fault_case_hot_delivery_action',
      ]) {
        expect(
          cards[id]!.formats.map((format) => format.mode).toSet(),
          containsAll({'short_answer', 'typed'}),
          reason: id,
        );
        expect(
          audit.items.singleWhere((row) => row.id == id).servedFormats,
          contains('case_criteria'),
          reason: id,
        );
      }
    },
  );

  test(
    'regional and service cases grade role matching and reject traps',
    () async {
      for (final (id, templateId) in [
        ('ki_reg_am_case_california_sites_action', _geographyCaseTemplateId),
        ('ki_fault_case_hot_delivery_action', _serviceCaseTemplateId),
      ]) {
        final exercise = await ExercisePresenter(
          db,
        ).present(id, templateId, seed: 13) as CaseCriteriaExercise;
        expect(exercise.itemIds, hasLength(4));
        expect(exercise.options, hasLength(6));
        expect(exercise.prompt.length, greaterThan(80));
        for (final criterion in exercise.criteria) {
          expect(criterion.sources, isNotEmpty);
          expect(criterion.sources.first.url, startsWith('https://'));
        }
        final byRole = {
          for (final criterion in exercise.criteria)
            criterion.role: criterion.itemId,
        };
        const format = CaseCriteriaFormat();
        expect(
          format
              .grade(exercise, CaseCriteriaResponse(byRole))
              .every((grade) => grade.rating == fsrs.Rating.good),
          isTrue,
        );
        final falseOption = exercise.options.firstWhere(
          (option) => option.explanation != null,
        );
        final withFalse = {...byRole, 'CASE_REASON': falseOption.id};
        expect(
          format
              .grade(exercise, CaseCriteriaResponse(withFalse))
              .singleWhere((grade) => grade.itemId == byRole['CASE_REASON'])
              .rating,
          fsrs.Rating.again,
        );
      }
    },
  );
}
