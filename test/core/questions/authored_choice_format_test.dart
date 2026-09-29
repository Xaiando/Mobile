import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/features/practice/format_views.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

const _itemId = 'ki_test_sugar_to_alcohol';
const _templateId = 'qt_test_authored_choice';

Map<String, dynamic> _fixture() {
  final data = copyOf(minimalDataset());
  rowsOf(data, 'node_types').addAll([
    {'id': 'production_principle', 'label': 'production principle'},
    {'id': 'learning_point', 'label': 'learning point'},
  ]);
  rowsOf(data, 'relation_types').add({
    'id': 'PRINCIPLE_EXPLANATION',
    'label': 'explains',
    'reverse_label': 'is explained by',
    'cardinality': 'many',
    'default_domain_id': 'viticulture',
  });
  rowsOf(data, 'relation_type_signatures').add({
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'subject_node_type': 'production_principle',
    'object_node_type': 'learning_point',
  });
  rowsOf(data, 'knowledge_nodes').addAll([
    {
      'id': 'n_test_fermentation_question',
      'node_type': 'production_principle',
      'name': 'What does yeast produce?',
    },
    {
      'id': 'n_test_fermentation_point',
      'node_type': 'learning_point',
      'name': 'Alcoholic fermentation',
    },
  ]);
  rowsOf(data, 'knowledge_relations').add({
    'subject_id': 'n_test_fermentation_question',
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'object_id': 'n_test_fermentation_point',
    'valid_from': '1900-01-01',
  });
  rowsOf(data, 'knowledge_items').add({
    'id': _itemId,
    'subject_id': 'n_test_fermentation_question',
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'object_id': 'n_test_fermentation_point',
    'domain_id': 'viticulture',
    'assertion_text': 'Yeast converts grape sugars into alcohol and CO2.',
    'mcq_disabled': true,
    'last_verified_at': '2026-01-01T00:00:00.000Z',
  });
  rowsOf(
    data,
    'knowledge_item_citations',
  ).add({'knowledge_item_id': _itemId, 'source_citation_id': 'src_test_law'});
  rowsOf(data, 'certification_knowledge_mappings').add({
    'certification_id': 'WSET_L1',
    'knowledge_item_id': _itemId,
    'importance': 'core',
    'minimum_depth': 2,
  });
  rowsOf(data, 'question_templates').addAll([
    {
      'id': 'qt_test_principle_flashcard',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'flashcard',
      'prompt_template': '{subject.name}',
    },
    {
      'id': 'qt_test_principle_mcq',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'mcq',
      'prompt_template': '{subject.name}',
    },
    {
      'id': _templateId,
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'authored_choice',
      'prompt_template': '{subject.name}',
      'parameters': {
        'item_choices': {
          _itemId: {
            'prompt': 'What two products does yeast make from grape sugar?',
            'options': [
              'Malic and lactic acids',
              'Alcohol and carbon dioxide',
              'Tannins and pigments',
              'Water and oxygen',
            ],
            'correctIndex': 1,
            'explanation': 'Yeast makes ethanol and carbon dioxide.',
            'sourceCitationId': 'src_test_law',
          },
        },
      },
    },
  ]);
  return data;
}

List<String> _parameterErrors(Map<String, dynamic> data) => [
  for (final issue in validateDataset(datasetOf(data)).errors)
    if (issue.rule == 'template-parameters') issue.message,
];

Map<String, dynamic> _cue(Map<String, dynamic> data) =>
    ((rowOf(data, 'question_templates', 'id', _templateId)['parameters']
                as Map<String, dynamic>)['item_choices']
            as Map<String, dynamic>)[_itemId]
        as Map<String, dynamic>;

void main() {
  test('daily practice has a view for authored choices', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(formatViewsProvider)['authored_choice'], isNotNull);
  });

  test('Level 3 viticulture principle choices avoid length clues and keep item citations', () {
    final data = flattenDataset('assets/curriculum/curriculum.yaml');
    final linkedCitations = <String, Set<String>>{};
    for (final row in rowsOf(data, 'knowledge_item_citations')) {
      final citation = row as Map<String, dynamic>;
      linkedCitations
          .putIfAbsent(citation['knowledge_item_id'] as String, () => {})
          .add(citation['source_citation_id'] as String);
    }
    final sources = {
      for (final row in rowsOf(data, 'source_citations'))
        (row as Map<String, dynamic>)['id'] as String: row,
    };
    const finalPrincipleIds = {
      'ki_wset_nw_canterbury_style_range',
      'ki_wset_nw_dry_creek_zinfandel',
      'ki_wset_nw_finger_lakes_riesling',
      'ki_wset_nw_gisborne_wine_styles',
      'ki_wset_nw_great_southern_styles',
      'ki_wset_nw_hawkes_syrah_pinot_gris',
      'ki_wset_nw_marlborough_aromatics',
      'ki_wset_nw_nelson_wine_styles',
      'ki_wset_nw_ontario_icewine_style',
      'ki_wset_nw_otago_aromatics',
      'ki_wset_nw_riverina_dry_styles',
      'ki_wset_nw_riverland_styles',
      'ki_wset_nw_saint_helena_setting',
      'ki_wset_nw_san_luis_grapes',
      'ki_wset_nw_stags_leap_setting',
      'ki_wset_nw_swartland_grapes',
    };
    final allIds = <String>{};
    const principleTemplateCounts = {
      'qt_wset_l3_viticulture_principle_closure_40': 40,
      'qt_wset_l3_viticulture_principle_closure_next_40': 40,
      'qt_wset_l3_viticulture_principle_final_16': 16,
    };
    for (final entry in principleTemplateCounts.entries) {
      final template = rowOf(data, 'question_templates', 'id', entry.key);
      final choices =
          (template['parameters'] as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      expect(choices, hasLength(entry.value), reason: entry.key);
      if (entry.value == 16) {
        expect(choices.keys.toSet(), finalPrincipleIds);
      }
      expect(allIds.intersection(choices.keys.toSet()), isEmpty);
      allIds.addAll(choices.keys);
      final answerPositions = [0, 0, 0, 0];
      for (final entry in choices.entries) {
        final choice = entry.value as Map<String, dynamic>;
        final options = (choice['options'] as List).cast<String>();
        final answerIndex = choice['correctIndex'] as int;
        expect(options, hasLength(4), reason: entry.key);
        expect(options.toSet(), hasLength(4), reason: entry.key);
        expect(answerIndex, inInclusiveRange(0, 3), reason: entry.key);
        expect(
          linkedCitations[entry.key],
          contains(choice['sourceCitationId']),
          reason: entry.key,
        );
        if (finalPrincipleIds.contains(entry.key)) {
          final source = sources[choice['sourceCitationId']];
          expect(source?['url'], startsWith('https://'), reason: entry.key);
        }
        final lengths = options.map((option) => option.length).toList();
        expect(
          lengths[answerIndex] == lengths.reduce(max) &&
              lengths
                      .where((length) => length == lengths[answerIndex])
                      .length ==
                  1,
          isFalse,
          reason: '${entry.key} should not reveal its key by unique length',
        );
        answerPositions[answerIndex]++;
      }
      expect(
        answerPositions,
        everyElement(entry.value ~/ 4),
        reason: entry.key,
      );
    }
    expect(allIds, hasLength(96));
  });

  test(
    'authored choice rejects malformed or uncited item-specific options',
    () {
      final duplicate = _fixture();
      (_cue(duplicate)['options'] as List)[2] = 'alcohol AND carbon dioxide';
      expect(
        _parameterErrors(duplicate).join('\n'),
        contains('Duplicate authored options'),
      );

      final wrongIndex = _fixture();
      _cue(wrongIndex)['correctIndex'] = 4;
      expect(
        _parameterErrors(wrongIndex).join('\n'),
        contains('Invalid authored choice'),
      );

      final uncited = _fixture();
      _cue(uncited)['sourceCitationId'] = 'src_missing';
      expect(
        _parameterErrors(uncited).join('\n'),
        contains('not cited by this item'),
      );

      final unknown = _fixture();
      final entries =
          (rowOf(unknown, 'question_templates', 'id', _templateId)['parameters']
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      entries['ki_missing'] = entries.remove(_itemId);
      expect(
        _parameterErrors(unknown).join('\n'),
        contains('no knowledge item'),
      );
    },
  );

  test(
    'literal choice reviews remain durable without node foreign keys',
    () async {
      final db = openTestDatabase();
      final time = TestClock(DateTime.utc(2026, 10, 1, 9));
      try {
        final report = await CurriculumIngester(
          db,
          clock: time.clock,
        ).ingest(datasetOf(_fixture()));
        expect(report.byFormat['authored_choice'], 1);
        final questions = await QuestionPresenter(db).questionsFor(_itemId);
        expect(
          questions.map((question) => question.questionTemplateId),
          contains(_templateId),
        );
        expect(
          questions.map((question) => question.questionTemplateId),
          isNot(contains('qt_test_principle_mcq')),
          reason: 'mcq_disabled still blocks inferred graph distractors',
        );
        final card = (await StudyPlanner(db, clock: time.clock).cards(
          'WSET_L1',
        )).singleWhere((candidate) => candidate.itemId == _itemId);
        expect(card.formats.map((format) => format.mode).toSet(), {
          'flashcard',
          'authored_choice',
        });

        final presenter = ExercisePresenter(db, clock: time.clock);
        final question = await presenter.present(
          _itemId,
          _templateId,
          seed: 19,
        ) as AuthoredChoiceQuestion;
        final sameSeed = await presenter.present(
          _itemId,
          _templateId,
          seed: 19,
        ) as AuthoredChoiceQuestion;
        expect(
          question.options.map((option) => option.name).toList(),
          sameSeed.options.map((option) => option.name).toList(),
        );
        expect(question.options, hasLength(4));
        expect(question.answer.name, 'Alcohol and carbon dioxide');
        expect(question.explanation, contains('ethanol'));
        expect(question.sourceCitationId, 'src_test_law');

        final wrong = question.options.firstWhere(
          (option) => option != question.answer,
        );
        final grades = presenter.grade(question, wrong);
        expect(grades.single.rating, fsrs.Rating.again);
        expect(
          presenter.grade(question, question.answer).single.rating,
          fsrs.Rating.good,
        );
        expect(
          () => presenter.grade(
            question,
            QuestionOption(wrong.nodeId, 'forged literal'),
          ),
          throwsArgumentError,
        );
        expect(grades.single.optionNodeIds, isEmpty);
        expect(grades.single.selectedNodeId, isNull);
        final reviews = ReviewService(
          db,
          clock: time.clock,
          random: Random(17),
        );
        await expectLater(
          reviews.answerMultipleChoice(question, question.answer),
          throwsArgumentError,
        );
        final result = (await reviews.recordExercise(question, grades)).single;
        expect(result.event.selectedNodeId, isNull);
        expect(await db.select(db.reviewEventOptions).get(), isEmpty);
        final payload =
            jsonDecode(result.event.answerPayload!) as Map<String, dynamic>;
        expect(
          payload['options'],
          question.options.map((option) => option.name).toList(),
        );
        expect(payload['selectedIndex'], question.options.indexOf(wrong));
        expect(payload['correctIndex'], question.correctIndex);
        expect(payload['sourceCitationId'], 'src_test_law');
        expect(payload['prompt'], question.prompt);
        expect(payload['explanation'], question.explanation);
        expect(
          (await db.select(db.reviewStates).get()).single.knowledgeItemId,
          _itemId,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    '1532 cited choices are generated and served across WSET and CMS tracks',
    () async {
      final db = openTestDatabase();
      try {
        await CurriculumIngester(db).ingest(bundledDataset());
        const foundationExamples = {
          'ki_wset_found_flower_to_fruit': 'viticulture',
          'ki_wset_found_fermentation': 'winemaking',
          'ki_wset_found_acidity': 'tasting',
          'ki_wset_found_familiar_chablis': 'geography',
          'ki_wset_srv_storage_cool': 'service',
        };
        final allTemplates = await (db.select(
          db.questionTemplates,
        )..where((row) => row.mode.equals('authored_choice'))).get();
        final templates = allTemplates
            .where(
              (template) =>
                  template.id.startsWith('qt_wset_') ||
                  template.id.startsWith('qt_cms_example_') ||
                  template.id == 'qt_d3rt_regional_choice' ||
                  template.id == 'qt_d4depth_regional_choices' ||
                  template.id == 'qt_d5f_authored_choice',
            )
            .toList();
        expect(templates, hasLength(73));
        final expectedIds = {
          for (final template in templates)
            ...((jsonDecode(template.parameters!)
                        as Map<String, dynamic>)['item_choices']
                    as Map<String, dynamic>)
                .keys,
        };
        final levelOneIds = {
          for (final template in templates)
            if (template.id.startsWith('qt_wset_l1_'))
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        final levelTwoIds = {
          for (final template in templates)
            if (template.id.startsWith('qt_wset_l2_'))
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        final sharedGrapeIds = {
          for (final template in templates)
            if (template.id.startsWith('qt_wset_shared_grape_'))
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        Set<String> idsForTemplate(String templateId) => {
          for (final template in templates)
            if (template.id == templateId)
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        final remainingGrapeIds = {
          ...idsForTemplate('qt_wset_shared_grape_profiles_remaining_3'),
          ...idsForTemplate('qt_wset_shared_grape_berry_colour_remaining_9'),
          ...idsForTemplate('qt_wset_shared_grape_structure_remaining_8'),
        };
        expect(remainingGrapeIds, hasLength(20));
        expect(sharedGrapeIds, containsAll(remainingGrapeIds));
        final remainingTemplates = templates.where(
          (template) =>
              template.id.contains('_remaining_') &&
              template.id.startsWith('qt_wset_shared_grape_'),
        );
        final newChoiceBlocks = remainingTemplates.expand((template) {
          final parameters =
              jsonDecode(template.parameters!) as Map<String, dynamic>;
          return (parameters['item_choices'] as Map<String, dynamic>).values;
        }).cast<Map<String, dynamic>>();
        final answerPositions = [0, 1, 2, 3]
            .map(
              (index) => newChoiceBlocks
                  .where((choice) => choice['correctIndex'] == index)
                  .length,
            )
            .toList();
        expect(answerPositions, everyElement(5));
        final remainingWinemakingIds = {
          ...idsForTemplate('qt_wset_l2_winemaking_method_remaining_1'),
          ...idsForTemplate('qt_wset_l2_winemaking_principles_remaining_39'),
        };
        expect(remainingWinemakingIds, hasLength(40));
        final winemakingChoiceBlocks = templates
            .where(
              (template) =>
                  template.id.startsWith('qt_wset_l2_winemaking_') &&
                  template.id.contains('_remaining_'),
            )
            .expand((template) {
              final parameters =
                  jsonDecode(template.parameters!) as Map<String, dynamic>;
              return (parameters['item_choices'] as Map<String, dynamic>)
                  .values;
            })
            .cast<Map<String, dynamic>>();
        expect(
          [0, 1, 2, 3].map(
            (index) => winemakingChoiceBlocks
                .where((choice) => choice['correctIndex'] == index)
                .length,
          ),
          everyElement(10),
        );
        final europeIds = idsForTemplate('qt_wset_europe_application_67');
        final newWorldIds = idsForTemplate('qt_wset_new_world_application_16');
        final businessIds = idsForTemplate('qt_wset_business_application_26');
        final l3BusinessGapIds = idsForTemplate('qt_wset_l3_business_gap_30');
        final cmsExampleIds = {
          for (final template in templates)
            if (template.id.startsWith('qt_cms_example_'))
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        final winemakingSharedIds = idsForTemplate(
          'qt_wset_winemaking_shared_application_9',
        );
        final winemakingL3Ids = idsForTemplate(
          'qt_wset_winemaking_l3_application_12',
        );
        final winemakingDepthIds = idsForTemplate(
          'qt_wset_winemaking_l3_depth_37',
        );
        final winemakingGapIds = idsForTemplate('qt_wset_l3_winemaking_gap_40');
        final l3WinemakingRegionalIds = idsForTemplate(
          'qt_wset_l3_winemaking_regional_principles_54',
        );
        final l3WinemakingSpecialIds = idsForTemplate(
          'qt_wset_l3_winemaking_special_principles_47',
        );
        final l3WinemakingFirstClosureIds = idsForTemplate(
          'qt_wset_l3_winemaking_principle_closure_40',
        );
        final l3ApplicationIds = idsForTemplate('qt_wset_l3_application_40');
        final l3ViticultureIds = idsForTemplate(
          'qt_wset_l3_viticulture_application_40',
        );
        final l3ViticulturePrincipleIds = idsForTemplate(
          'qt_wset_l3_viticulture_principle_closure_40',
        );
        final l3ViticulturePrincipleNextIds = idsForTemplate(
          'qt_wset_l3_viticulture_principle_closure_next_40',
        );
        final l3ViticulturePrincipleFinalIds = idsForTemplate(
          'qt_wset_l3_viticulture_principle_final_16',
        );
        final l3ViticultureCaseIds = {
          ...idsForTemplate('qt_wset_l3_viticulture_case_action_choice'),
          ...idsForTemplate('qt_wset_l3_viticulture_case_limitation_choice'),
          ...idsForTemplate('qt_wset_l3_viticulture_case_reason_choice'),
          ...idsForTemplate('qt_wset_l3_viticulture_case_tradeoff_choice'),
        };
        final l3ViticultureGeneralIds = idsForTemplate(
          'qt_wset_l3_viticulture_general_22',
        );
        final l3TastingIds = idsForTemplate(
          'qt_wset_l3_tasting_application_23',
        );
        final l3ServiceIds = idsForTemplate(
          'qt_wset_l3_service_application_17',
        );
        final l3TastingClosureIds = idsForTemplate(
          'qt_wset_l3_tasting_fault_closure_12',
        );
        final l3ServicePrincipleClosureIds = idsForTemplate(
          'qt_wset_l3_service_principle_closure_8',
        );
        final l3ServiceCaseClosureIds = {
          ...idsForTemplate('qt_wset_l3_service_case_action_closure_4'),
          ...idsForTemplate('qt_wset_l3_service_case_reason_closure_4'),
          ...idsForTemplate('qt_wset_l3_service_case_tradeoff_closure_4'),
          ...idsForTemplate('qt_wset_l3_service_case_limitation_closure_4'),
        };
        final l3GeographyIds = idsForTemplate(
          'qt_wset_l3_geography_gap_scenarios',
        );
        final l3GeographyIds2 = idsForTemplate(
          'qt_wset_l3_geography_gap_scenarios_2',
        );
        final l3RemainingPrincipleIds = idsForTemplate(
          'qt_wset_l3_geography_remaining_principles_40',
        );
        final l3FinalGeographyIds = {
          ...idsForTemplate('qt_wset_l3_geography_remaining_8_principles'),
          ...idsForTemplate('qt_wset_l3_geography_gg_awarder'),
          ...idsForTemplate('qt_wset_l3_geography_vdp_private'),
          ...idsForTemplate('qt_wset_l3_geography_ripasso_origin'),
        };
        final l3LocationClueIds = idsForTemplate(
          'qt_wset_l3_geography_location_clues_35',
        );
        final l3WinemakingPrincipleIds = idsForTemplate(
          'qt_wset_l3_winemaking_principle_closure_40',
        );
        final diplomaBusinessIds = idsForTemplate(
          'qt_wset_d2_business_application_29',
        );
        final d3RegionalIds = idsForTemplate('qt_d3rt_regional_choice');
        final d4RegionalIds = idsForTemplate('qt_d4depth_regional_choices');
        final d5FortifiedIds = idsForTemplate('qt_d5f_authored_choice');
        final earlierLevelThreeIds = expectedIds.difference({
          ...levelOneIds,
          ...levelTwoIds,
          ...sharedGrapeIds,
          ...europeIds,
          ...newWorldIds,
          ...businessIds,
          ...l3BusinessGapIds,
          ...cmsExampleIds,
          ...winemakingSharedIds,
          ...winemakingL3Ids,
          ...winemakingDepthIds,
          ...winemakingGapIds,
          ...l3WinemakingRegionalIds,
          ...l3WinemakingSpecialIds,
          ...l3ApplicationIds,
          ...l3ViticultureIds,
          ...l3ViticulturePrincipleIds,
          ...l3ViticulturePrincipleNextIds,
          ...l3ViticulturePrincipleFinalIds,
          ...l3ViticultureCaseIds,
          ...l3ViticultureGeneralIds,
          ...l3TastingIds,
          ...l3ServiceIds,
          ...l3TastingClosureIds,
          ...l3ServicePrincipleClosureIds,
          ...l3ServiceCaseClosureIds,
          ...l3GeographyIds,
          ...l3GeographyIds2,
          ...l3RemainingPrincipleIds,
          ...l3FinalGeographyIds,
          ...l3LocationClueIds,
          ...l3WinemakingPrincipleIds,
          ...diplomaBusinessIds,
          ...d3RegionalIds,
          ...d4RegionalIds,
          ...d5FortifiedIds,
        });
        expect(
          d3RegionalIds.intersection(remainingWinemakingIds),
          isEmpty,
          reason: 'Diploma regional choices use distinct cited items',
        );
        expect(
          d3RegionalIds.intersection(
            idsForTemplate('qt_wset_l2_viticulture_gap_choices'),
          ),
          isEmpty,
          reason: 'Diploma and Level 2 viticulture choices remain distinct',
        );
        expect(
          d3RegionalIds.intersection(l3GeographyIds),
          isEmpty,
          reason: 'Diploma and Level 3 geography choices remain distinct',
        );
        expect(
          d3RegionalIds.intersection(l3GeographyIds2),
          isEmpty,
          reason: 'Diploma and Level 3 geography choices remain distinct',
        );
        expect(expectedIds, hasLength(1532));
        expect(levelOneIds, hasLength(132));
        expect(levelTwoIds, hasLength(309));
        expect(sharedGrapeIds, hasLength(52));
        expect(europeIds, hasLength(67));
        expect(newWorldIds, hasLength(16));
        expect(businessIds, hasLength(26));
        expect(l3BusinessGapIds, hasLength(30));
        expect(cmsExampleIds, hasLength(12));
        expect(winemakingSharedIds, hasLength(9));
        expect(winemakingL3Ids, hasLength(12));
        expect(winemakingDepthIds, hasLength(37));
        expect(winemakingGapIds, hasLength(40));
        expect(l3WinemakingRegionalIds, hasLength(54));
        expect(l3WinemakingSpecialIds, hasLength(47));
        expect(
          l3WinemakingSpecialIds.intersection(l3WinemakingRegionalIds),
          isEmpty,
        );
        expect(
          l3WinemakingSpecialIds.intersection(l3WinemakingFirstClosureIds),
          isEmpty,
        );
        expect(l3WinemakingSpecialIds.intersection(winemakingGapIds), isEmpty);
        expect(
          l3WinemakingRegionalIds.intersection(l3WinemakingFirstClosureIds),
          isEmpty,
        );
        expect(l3WinemakingRegionalIds.intersection(winemakingGapIds), isEmpty);
        expect(l3ApplicationIds, hasLength(40));
        expect(l3ViticultureIds, hasLength(40));
        expect(l3ViticulturePrincipleIds, hasLength(40));
        expect(l3ViticulturePrincipleNextIds, hasLength(40));
        expect(l3ViticulturePrincipleFinalIds, hasLength(16));
        expect(l3ViticultureCaseIds, hasLength(40));
        expect(
          l3ViticulturePrincipleIds.intersection(l3ViticultureIds),
          isEmpty,
        );
        expect(
          l3ViticulturePrincipleNextIds.intersection(l3ViticulturePrincipleIds),
          isEmpty,
        );
        expect(l3ViticultureGeneralIds, hasLength(22));
        expect(l3TastingIds, hasLength(23));
        expect(l3ServiceIds, hasLength(17));
        expect(l3TastingClosureIds, hasLength(12));
        expect(l3ServicePrincipleClosureIds, hasLength(8));
        expect(l3ServiceCaseClosureIds, hasLength(16));
        expect(l3GeographyIds, hasLength(36));
        expect(l3GeographyIds2, hasLength(40));
        expect(l3RemainingPrincipleIds, hasLength(40));
        expect(l3FinalGeographyIds, hasLength(11));
        expect(l3LocationClueIds, hasLength(35));
        expect(l3WinemakingPrincipleIds, hasLength(40));
        expect(diplomaBusinessIds, hasLength(29));
        expect(d3RegionalIds, hasLength(19));
        expect(d4RegionalIds, hasLength(24));
        expect(d5FortifiedIds, hasLength(16));
        expect(earlierLevelThreeIds, hasLength(85));
        final rows = await db.customSelect('''
        SELECT q.knowledge_item_id, i.domain_id FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        JOIN knowledge_items i ON i.id = q.knowledge_item_id
        WHERE t.mode = 'authored_choice'
          AND (t.id GLOB 'qt_wset_*' OR t.id GLOB 'qt_cms_example_*'
               OR t.id = 'qt_d3rt_regional_choice'
               OR t.id = 'qt_d4depth_regional_choices'
               OR t.id = 'qt_d5f_authored_choice')
        ORDER BY q.knowledge_item_id
      ''').get();
        expect(rows, hasLength(1532));
        final actual = {
          for (final row in rows)
            row.read<String>('knowledge_item_id'): row.read<String>(
              'domain_id',
            ),
        };
        expect(actual.keys.toSet(), expectedIds);
        for (final entry in foundationExamples.entries) {
          expect(actual[entry.key], entry.value, reason: entry.key);
        }
        final levelOneCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L1'))
            card.itemId: card,
        };
        final levelTwoCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L2'))
            card.itemId: card,
        };
        final levelThreeCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L3'))
            card.itemId: card,
        };
        final levelFourCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L4'))
            card.itemId: card,
        };
        final cmsCards = {
          for (final card in await StudyPlanner(db).cards('CMS_CERTIFIED'))
            card.itemId: card,
        };
        expect(
          europeIds.where(levelTwoCards.containsKey),
          hasLength(26),
          reason: 'Only the Level 2-scope European applications are shared',
        );
        final sharedL3ApplicationIds = l3ApplicationIds
            .where(levelTwoCards.containsKey)
            .toSet();
        expect(
          sharedL3ApplicationIds,
          hasLength(15),
          reason: 'Only existing Level 2 core facts inherit this batch',
        );
        for (final id in sharedL3ApplicationIds) {
          expect(
            levelTwoCards[id]?.formats.map((format) => format.mode),
            contains('authored_choice'),
            reason: 'Level 2: $id',
          );
        }
        for (final id in remainingWinemakingIds) {
          expect(
            levelTwoCards[id]?.formats.map((format) => format.mode),
            contains('authored_choice'),
            reason: 'Level 2 winemaking: $id',
          );
          expect(
            levelThreeCards[id]?.formats.map((format) => format.mode),
            contains('authored_choice'),
            reason: 'Level 3 winemaking inheritance: $id',
          );
        }
        expect(
          levelTwoCards['ki_champagne_method']?.formats.map(
            (format) => format.mode,
          ),
          containsAll({'authored_choice', 'flashcard', 'typed'}),
          reason: 'Champagne method needs an independent recall family at L2',
        );
        expect(
          businessIds.where(levelTwoCards.containsKey),
          hasLength(15),
          reason:
              'The 15 Level 2 business applications are shared with Level 3',
        );
        for (final id in businessIds) {
          expect(
            levelThreeCards[id]?.formats.map((format) => format.mode),
            contains('authored_choice'),
            reason: 'Level 3 business: $id',
          );
          if (levelTwoCards.containsKey(id)) {
            expect(
              levelTwoCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Level 2 business: $id',
            );
          }
        }
        for (final id in expectedIds) {
          if (d5FortifiedIds.contains(id)) {
            expect(
              levelFourCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Diploma D5: $id',
            );
          }
          if (d4RegionalIds.contains(id)) {
            expect(
              levelFourCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Diploma D4: $id',
            );
          }
          if (d3RegionalIds.contains(id)) {
            expect(
              levelFourCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Diploma D3: $id',
            );
          }
          if (diplomaBusinessIds.contains(id)) {
            expect(
              levelFourCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Diploma D2: $id',
            );
            if (id.startsWith('ki_d2_')) {
              expect(levelOneCards.containsKey(id), isFalse, reason: id);
              expect(levelTwoCards.containsKey(id), isFalse, reason: id);
              expect(levelThreeCards.containsKey(id), isFalse, reason: id);
              expect(cmsCards.containsKey(id), isFalse, reason: id);
            }
          }
          if (sharedGrapeIds.contains(id) ||
              newWorldIds.contains(id) ||
              winemakingSharedIds.contains(id) ||
              (europeIds.contains(id) && levelTwoCards.containsKey(id))) {
            expect(
              levelTwoCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Level 2: $id',
            );
            expect(
              levelThreeCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Level 3: $id',
            );
          }
          if (europeIds.contains(id) ||
              winemakingL3Ids.contains(id) ||
              winemakingDepthIds.contains(id) ||
              l3BusinessGapIds.contains(id) ||
              winemakingGapIds.contains(id) ||
              l3ApplicationIds.contains(id) ||
              l3ViticultureIds.contains(id) ||
              l3ViticulturePrincipleIds.contains(id) ||
              l3ViticulturePrincipleNextIds.contains(id) ||
              l3ViticulturePrincipleFinalIds.contains(id) ||
              l3ViticultureCaseIds.contains(id) ||
              l3ViticultureGeneralIds.contains(id) ||
              l3GeographyIds.contains(id) ||
              l3GeographyIds2.contains(id) ||
              l3RemainingPrincipleIds.contains(id) ||
              l3FinalGeographyIds.contains(id)) {
            expect(
              levelThreeCards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: 'Level 3: $id',
            );
          }
          expect(
            (levelOneIds.contains(id)
                    ? levelOneCards[id]
                    : levelTwoIds.contains(id)
                    ? levelTwoCards[id]
                    : sharedGrapeIds.contains(id)
                    ? levelTwoCards[id]
                    : cmsExampleIds.contains(id)
                    ? cmsCards[id]
                    : diplomaBusinessIds.contains(id)
                    ? levelFourCards[id]
                    : d3RegionalIds.contains(id)
                    ? levelFourCards[id]
                    : d4RegionalIds.contains(id)
                    ? levelFourCards[id]
                    : d5FortifiedIds.contains(id)
                    ? levelFourCards[id]
                    : levelThreeCards[id])
                ?.formats
                .map((format) => format.mode),
            contains('authored_choice'),
            reason: id,
          );
          final item = await (db.select(
            db.knowledgeItems,
          )..where((row) => row.id.equals(id))).getSingle();
          expect(item.mcqDisabled, isTrue, reason: id);
        }
        final genericDisabled = await db.customSelect('''
        SELECT q.knowledge_item_id FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        JOIN knowledge_items i ON i.id = q.knowledge_item_id
        WHERE t.mode = 'mcq' AND i.mcq_disabled = 1
      ''').get();
        expect(genericDisabled, isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'Diploma D2 cases use distinct choices and linked primary citations',
    () {
      final dataset = bundledDataset();
      final template = dataset.questionTemplates.singleWhere(
        (row) => row.id == 'qt_wset_d2_business_application_29',
      );
      final choices =
          (jsonDecode(template.parameters!)
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      final linkedSources = <String, Set<String>>{};
      for (final citation in dataset.knowledgeItemCitations) {
        linkedSources
            .putIfAbsent(citation.knowledgeItemId, () => <String>{})
            .add(citation.sourceCitationId);
      }
      expect(choices, hasLength(29));
      expect(choices.keys.where((id) => id.startsWith('ki_d2_')), hasLength(3));
      final answerCounts = List<int>.filled(4, 0);
      for (final entry in choices.entries) {
        final caseData = entry.value as Map<String, dynamic>;
        final options = (caseData['options'] as List<dynamic>).cast<String>();
        final correctIndex = caseData['correctIndex'] as int;
        expect(options, hasLength(4), reason: entry.key);
        expect(
          options.map((option) => option.trim().toLowerCase()).toSet(),
          hasLength(4),
          reason: entry.key,
        );
        expect(correctIndex, inInclusiveRange(0, 3), reason: entry.key);
        expect(caseData['prompt'], isNotEmpty, reason: entry.key);
        expect(caseData['explanation'], isNotEmpty, reason: entry.key);
        expect(
          linkedSources[entry.key],
          contains(caseData['sourceCitationId']),
          reason: entry.key,
        );
        answerCounts[correctIndex]++;
      }
      expect(answerCounts, [8, 7, 7, 7]);
    },
  );
}
