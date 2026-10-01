import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

String _canonicalFileSha256(String path) {
  final text = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  return sha256.convert(utf8.encode(text)).toString();
}

// Registration and actual D3 delivery are required. Finite recall does not
// replace the original four-role regional cases or confer qualification.
void main() {
  final dataset = bundledDataset();
  const typedId = 'qt_d3pt_principle_typed_6';
  const criteriaId = 'qt_d3pt_case_criteria_2';
  const writtenId = 'qt_d3pt_case_written_2';
  const principleIds = {
    'ki_d3pt_tejo_site_context',
    'ki_d3pt_tejo_white_blend',
    'ki_d3pt_tejo_label_scope',
    'ki_d3pt_setubal_site_context',
    'ki_d3pt_setubal_castelao_red',
    'ki_d3pt_setubal_product_boundary',
  };
  const caseIds = {
    'ki_d3pt_case_tejo_white_action',
    'ki_d3pt_case_tejo_white_reason',
    'ki_d3pt_case_tejo_white_tradeoff',
    'ki_d3pt_case_tejo_white_limitation',
    'ki_d3pt_case_setubal_still_red_action',
    'ki_d3pt_case_setubal_still_red_reason',
    'ki_d3pt_case_setubal_still_red_tradeoff',
    'ki_d3pt_case_setubal_still_red_limitation',
  };
  const expectedIds = {...principleIds, ...caseIds};
  const actions = {
    'n_d3pt_case_tejo_white': 'ki_d3pt_case_tejo_white_action',
    'n_d3pt_case_setubal_still_red': 'ki_d3pt_case_setubal_still_red_action',
  };
  const expectedCasePrerequisites = {
    'n_d3pt_case_tejo_white': {
      'ki_d3pt_tejo_site_context',
      'ki_d3pt_tejo_white_blend',
      'ki_d3pt_tejo_label_scope',
      'ki_biz_payment_timing',
      'ki_biz_routes_dtc_resources',
      'ki_biz_routes_partner_fit',
      'ki_biz_routes_reviewable_roles',
      'ki_biz_routes_downstream_sales',
      'ki_biz_profit_cash',
    },
    'n_d3pt_case_setubal_still_red': {
      'ki_d3pt_setubal_site_context',
      'ki_d3pt_setubal_castelao_red',
      'ki_d3pt_setubal_product_boundary',
      'ki_biz_routes_partner_fit',
      'ki_biz_routes_reviewable_roles',
      'ki_biz_routes_downstream_sales',
      'ki_biz_payment_timing',
      'ki_biz_inventory_cash',
      'ki_biz_profit_cash',
      'ki_biz_working_capital',
    },
  };
  const sourceUrls = {
    'src_d3pt_cvrtejo_terroir': 'https://www.cvrtejo.pt/terroir',
    'src_d3pt_cvrtejo_castas': 'https://www.cvrtejo.pt/castas',
    'src_d3pt_ivv_ig_tejo_2026':
        'https://www.ivv.gov.pt/wp-content/uploads/2026/02/IG_Tejo.pdf',
    'src_d3pt_ivv_do_tejo':
        'https://www.ivv.gov.pt/wp-content/uploads/2026/02/DO_Do-Tejo.pdf',
    'src_d3pt_ivv_setubal_profile': 'https://www.ivv.gov.pt/regioes-vitivinicolas/mapa-das-regioes/peninsula-de-setubal/',
    'src_d3pt_ivv_ig_setubal': 'https://www.ivv.gov.pt/wp-content/uploads/2026/02/IG_Peninsula-de-Setubal.pdf',
  };
  const expectedRecall = {
    'ki_d3pt_tejo_site_context': {'Serras'},
    'ki_d3pt_tejo_white_blend': {'Arinto'},
    'ki_d3pt_tejo_label_scope': {
      'IGP',
      'protected geographical indication',
      'indicação geográfica protegida',
    },
    'ki_d3pt_setubal_site_context': {'Arrábida', 'Serra da Arrábida'},
    'ki_d3pt_setubal_castelao_red': {'Castelão'},
    'ki_d3pt_setubal_product_boundary': {
      'licoroso',
      'vinho licoroso',
      'liqueur wine',
      'fortified wine',
    },
  };
  const wrongRecall = {
    'ki_d3pt_tejo_site_context': {'Campo', 'Bairro', 'Charneca', 'Tejo'},
    'ki_d3pt_tejo_white_blend': {'Fernão Pires', 'Castelão', 'Tejo'},
    'ki_d3pt_tejo_label_scope': {'DOP', 'PDO', 'Tejo'},
    'ki_d3pt_setubal_site_context': {'Sado', 'Tejo', 'Setúbal'},
    'ki_d3pt_setubal_castelao_red': {'Arinto', 'Moscatel', 'Setúbal'},
    'ki_d3pt_setubal_product_boundary': {
      'dry still red',
      'table wine',
      'Setúbal',
    },
  };
  final typedTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == typedId,
  );
  final criteriaTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == criteriaId,
  );
  final writtenTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == writtenId,
  );
  final cues = TypedFormat.itemCuesOf(typedTemplate)!;
  final prompts = CaseCriteriaFormat.scenarioPromptsOf(criteriaTemplate);
  final scope = actions.keys.toSet();
  final items = {
    for (final row in dataset.knowledgeItems)
      if (expectedIds.contains(row.id)) row.id: row,
  };
  final subjects = items.values.map((row) => row.subjectId).toSet();

  test('fourteen sourced points have exact L4 mappings and formal prerequisite sets', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final cohort = dataset.knowledgeItems
        .where((row) => row.id.startsWith('ki_d3pt_'))
        .toList();
    expect(cohort, hasLength(14));
    expect(cohort.map((row) => row.id).toSet(), expectedIds);
    final nodes = dataset.knowledgeNodes
        .where((row) => row.id.startsWith('n_d3pt_'))
        .toList();
    expect(nodes, hasLength(22));
    expect(nodes.map((row) => row.id).toSet(), hasLength(22));
    final expectedPrincipleCitations = {
      'ki_d3pt_tejo_site_context': {
        'src_d3pt_cvrtejo_terroir',
        'src_d3pt_ivv_ig_tejo_2026',
      },
      'ki_d3pt_tejo_white_blend': {
        'src_d3pt_cvrtejo_castas',
        'src_d3pt_ivv_do_tejo',
        'src_d4nw_awri_sensory',
      },
      'ki_d3pt_tejo_label_scope': {
        'src_d3pt_ivv_ig_tejo_2026',
        'src_d3pt_ivv_do_tejo',
      },
      'ki_d3pt_setubal_site_context': {
        'src_d3pt_ivv_setubal_profile',
        'src_d3pt_ivv_ig_setubal',
      },
      'ki_d3pt_setubal_castelao_red': {
        'src_d3pt_ivv_setubal_profile',
        'src_d3pt_ivv_ig_setubal',
      },
      'ki_d3pt_setubal_product_boundary': {
        'src_d3pt_ivv_setubal_profile',
        'src_d3pt_ivv_ig_setubal',
      },
    };
    for (final item in cohort) {
      final principle = principleIds.contains(item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(item.assertionText, isNotEmpty);
      expect(
        item.domainId,
        principle
            ? 'geography'
            : item.subjectId == 'n_d3pt_case_tejo_white'
            ? 'winemaking'
            : 'business',
      );
      expect(
        nodes.singleWhere((row) => row.id == item.subjectId).nodeType,
        principle ? 'production_principle' : 'production_case',
      );
      expect(
        nodes.singleWhere((row) => row.id == item.objectId).nodeType,
        'learning_point',
      );
      final relation = dataset.knowledgeRelations.singleWhere(
        (row) =>
            row.subjectId == item.subjectId &&
            row.relationType == item.relationType &&
            row.objectId == item.objectId,
      );
      expect(relation.validFrom, '2026-10-01');
      expect(relation.validUntil, isNull);
      final mappings = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1));
      expect(mappings.single.certificationId, 'WSET_L4');
      expect(mappings.single.importance, 'core');
      expect(mappings.single.minimumDepth, 3);
      final citations = dataset.knowledgeItemCitations
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      final citedIds = citations.map((row) => row.sourceCitationId).toSet();
      expect(
        citations.length,
        citedIds.length,
        reason: 'No duplicate citation for one fact',
      );
      expect(citations, isNotEmpty);
      if (principle) {
        expect(citedIds, expectedPrincipleCitations[item.id]);
      } else if ({
        'CASE_TRADEOFF',
        'CASE_LIMITATION',
      }.contains(item.relationType)) {
        expect(citedIds, contains('src_biz_au_cashflow'));
        expect(citedIds, contains('src_biz_routes_wine_australia_partner'));
      } else {
        expect(citedIds, contains('src_d4nw_awri_sensory'));
      }
      for (final citation in citations) {
        expect(citation.locator, isNotEmpty);
        final source = dataset.sourceCitations.singleWhere(
          (row) => row.id == citation.sourceCitationId,
        );
        expect(source.url, startsWith('https://'));
        expect(source.url, isNot(contains('wset_l4wines_specification')));
      }
      final prerequisites = dataset.knowledgeItemPrerequisites
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      final required = principle
          ? <String>{}
          : expectedCasePrerequisites[item.subjectId]!;
      expect(
        prerequisites.map((row) => row.prerequisiteItemId).toSet(),
        required,
        reason: item.id,
      );
      expect(prerequisites, hasLength(required.length));
      for (final id in required) {
        expect(
          dataset.knowledgeItems.where((row) => row.id == id),
          hasLength(1),
          reason: id,
        );
      }
    }
    expect(
      dataset.knowledgeItemPrerequisites.where(
        (row) => expectedIds.contains(row.knowledgeItemId),
      ),
      hasLength(76),
    );
    final uniquePrerequisites = expectedCasePrerequisites.values
        .expand((ids) => ids)
        .toSet();
    expect(uniquePrerequisites, hasLength(14));
    expect(uniquePrerequisites.intersection(principleIds), principleIds);
    expect(uniquePrerequisites.difference(principleIds), hasLength(8));
    for (final entry in sourceUrls.entries) {
      expect(
        dataset.sourceCitations.singleWhere((row) => row.id == entry.key).url,
        entry.value,
      );
      expect(
        dataset.sourceCitations.where((row) => row.url == entry.value),
        hasLength(1),
      );
    }
    expect(
      dataset.sourceCitations
          .where((row) => row.id.startsWith('src_d3pt_'))
          .map((row) => row.id)
          .toSet(),
      sourceUrls.keys.toSet(),
    );
  });

  test(
    'bounded recall and four-role prompts have distinct template identities',
    () {
      expect(cues.keys.toSet(), principleIds);
      for (final entry in expectedRecall.entries) {
        expect(cues[entry.key]!.acceptedAnswers.toSet(), entry.value);
        expect(cues[entry.key]!.prompt, isNotEmpty);
        expect(cues[entry.key]!.prompt, isNot(items[entry.key]!.assertionText));
        final normalized = normalizeName(cues[entry.key]!.prompt);
        for (final answer in entry.value) {
          expect(
            normalized,
            isNot(contains(normalizeName(answer))),
            reason: entry.key,
          );
        }
      }
      expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), scope);
      expect(ShortAnswerFormat.scopeNodeIdsOf(writtenTemplate), scope);
      expect(prompts.keys.toSet(), scope);
      expect(
        ShortAnswerFormat.keyPointsOf(writtenTemplate)!.keys.toSet(),
        caseCriterionRoles.toSet(),
      );
      final wrongOptions = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
      expect(wrongOptions.keys.toSet(), scope);
      for (final subject in scope) {
        expect(wrongOptions[subject], hasLength(2));
        expect(
          wrongOptions[subject]!.map((row) => row.id).toSet(),
          hasLength(2),
        );
        for (final option in wrongOptions[subject]!) {
          expect(option.summary, isNotEmpty);
          expect(option.explanation?.isNotEmpty ?? false, isTrue);
        }
        expect(prompts[subject], contains('fictional'));
        expect(prompts[subject], contains('conditional action'));
        for (final item in items.values.where(
          (row) => row.subjectId == subject,
        )) {
          expect(prompts[subject], isNot(contains(item.assertionText)));
        }
      }
      expect(
        prompts['n_d3pt_case_tejo_white'],
        contains('not effects assigned to one variable'),
      );
      expect(prompts['n_d3pt_case_tejo_white'], contains('week ten for B'));
      expect(
        prompts['n_d3pt_case_setubal_still_red'],
        contains('not a controlled single-variable'),
      );
      expect(
        prompts['n_d3pt_case_setubal_still_red'],
        contains('no actual Palmela composition'),
      );
      final templates = dataset.questionTemplates
          .where((row) => row.id.startsWith('qt_d3pt_'))
          .toList();
      expect(templates, hasLength(4));
      expect(templates.map((row) => row.mode).toSet(), {
        'typed',
        'authored_choice',
        'case_criteria',
        'short_answer',
      });
      for (final template in templates) {
        expect(template.variant, startsWith('d3pt_'));
        expect(template.locale, 'en');
        final identical = dataset.questionTemplates.where(
          (row) =>
              row.relationType == template.relationType &&
              row.direction == template.direction &&
              row.mode == template.mode &&
              row.variant == template.variant &&
              row.locale == template.locale,
        );
        expect(identical, hasLength(1));
        expect(identical.single.id, template.id);
      }
    },
  );

  test('regional content routes only to Diploma D3 and preserves existing maps and saved banks', () {
    final progress = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = progress.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    expect(diploma.units.map((unit) => unit.id).toSet(), {
      'D1',
      'D2',
      'D3',
      'D4',
      'D5',
      'D6',
    });
    expect(
      diploma.units.singleWhere((unit) => unit.id == 'D3').itemIds.toSet(),
      containsAll(expectedIds),
    );
    for (final unit in diploma.units.where((unit) => unit.id != 'D3')) {
      expect(
        unit.itemIds.toSet().intersection(expectedIds),
        isEmpty,
        reason: unit.id,
      );
    }
    for (final level in progress.levels.where(
      (level) => level.certificationId != 'WSET_L4',
    )) {
      expect(
        level.requiredItemIds.intersection(expectedIds),
        isEmpty,
        reason: level.certificationId,
      );
    }
    expect(diploma.curriculumComplete, isFalse);
    final manifest = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final row in manifest.tracks['WSET_L4']!.objectives) row.id: row,
    };
    for (final id in ['wset_l4.world.portugal', 'wset_l4.world.comparison']) {
      expect(
        objectives[id]!.covers!.within.toSet().intersection(subjects),
        subjects,
        reason: id,
      );
      // Preserve each existing selector: Portugal is unrestricted;
      // comparison explicitly selects principles and all four case roles.
      expect(
        objectives[id]!.covers!.relationTypes,
        id == 'wset_l4.world.portugal'
            ? const <String>{}
            : {'PRINCIPLE_EXPLANATION', ...caseCriterionRoles},
        reason: id,
      );
    }
    for (final track in manifest.tracks.entries.where(
      (row) => row.key != 'WSET_L4',
    )) {
      for (final objective in track.value.objectives) {
        expect(
          objective.covers?.within.toSet().intersection(subjects) ?? <String>{},
          isEmpty,
          reason: objective.id,
        );
      }
    }
    for (final entry in {
      'ki_atlas_tejo_location': 'n_geo_tejo',
      'ki_atlas_setubal_location': 'n_geo_setubal',
    }.entries) {
      final item = dataset.knowledgeItems.singleWhere(
        (row) => row.id == entry.key,
      );
      expect(item.subjectId, entry.value);
      expect(item.relationType, 'LOCATED_IN');
      expect(item.objectId, 'n_geo_portugal');
      expect(item.domainId, 'geography');
      for (final track in ['WSET_L3', 'CMS_CERTIFIED']) {
        final mapping = dataset.certificationKnowledgeMappings.singleWhere(
          (row) =>
              row.knowledgeItemId == entry.key && row.certificationId == track,
        );
        expect(mapping.importance, 'core');
        expect(mapping.minimumDepth, 2);
      }
    }
    expect(
      dataset.nodeGeometries.where(
        (row) => row.knowledgeNodeId.startsWith('n_d3pt_'),
      ),
      isEmpty,
    );
    for (final entry in {
      'assets/study/diploma_written_practice.json':
          '25bf2cac634ca23c42d6015aa84b60e35ba97bc063f836a84c9a23e68360fbb0',
      'assets/study/diploma_tasting_flights.json':
          '799cda7635d4a7acc0397af9d590fca9214496d0f835ce30743a4bf1ee6caf31',
    }.entries) {
      expect(_canonicalFileSha256(entry.key), entry.value, reason: entry.key);
    }
  });

  test(
    'canonical file hashing is line-ending invariant and rejects tampering',
    () {
      const sample = 'name: test\r\nvalue: 42\r\n';
      final lf = sample.replaceAll('\r\n', '\n');
      final crlf = sample;
      final hashLf = sha256.convert(utf8.encode(lf)).toString();
      final hashCrlf = sha256
          .convert(utf8.encode(crlf.replaceAll('\r\n', '\n')))
          .toString();
      expect(hashCrlf, hashLf);

      // Character mutation alters hash
      final mutatedChar = lf.replaceAll('test', 'prod');
      expect(
        sha256.convert(utf8.encode(mutatedChar)).toString(),
        isNot(hashLf),
      );

      // Whitespace alteration alters hash
      final mutatedSpace = lf.replaceAll('value: 42', 'value:  42');
      expect(
        sha256.convert(utf8.encode(mutatedSpace)).toString(),
        isNot(hashLf),
      );

      // Trailing additions alter hash
      final mutatedTrailing = '$lf\n';
      expect(
        sha256.convert(utf8.encode(mutatedTrailing)).toString(),
        isNot(hashLf),
      );
    },
  );

  test('six real recalled meanings and authored alternatives reject wrong answers without leaking feedback', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(dataset.publishedAt);
      await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      const choiceId = 'qt_d3pt_principle_choice_6';
      final choiceTemplate = dataset.questionTemplates.singleWhere(
        (row) => row.id == choiceId,
      );
      final choices = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);
      expect(choices.keys.toSet(), principleIds);
      expect(choiceTemplate.variant, 'd3pt_principle_choice_6');
      final planner = StudyPlanner(db, clock: fixed);
      final cards = {
        for (final card in await planner.cards('WSET_L4')) card.itemId: card,
      };
      final presenter = ExercisePresenter(db, clock: fixed);
      final reviews = ReviewService(db, clock: fixed);
      final settingsBefore = {
        for (final row in await db.select(db.userSettings).get())
          row.name: row.value,
      };
      final generated = (await db.select(db.questions).get())
          .where(
            (row) =>
                row.questionTemplateId == typedId ||
                row.questionTemplateId == choiceId,
          )
          .toList();
      expect(generated, hasLength(12));
      for (final id in principleIds) {
        expect(
          generated
              .where((row) => row.knowledgeItemId == id)
              .map((row) => row.questionTemplateId)
              .toSet(),
          {typedId, choiceId},
        );
        expect(
          cards[id]!.formats.map((row) => row.questionTemplateId),
          containsAll({typedId, choiceId}),
        );
        final typed = await presenter.present(
          id,
          typedId,
          certificationId: 'WSET_L4',
          seed: 37,
        ) as TypedQuestion;
        expect(typed.prompt, cues[id]!.prompt);
        expect(typed.options, isEmpty);
        expect(typed.explanation, contains(items[id]!.assertionText));
        expect(typed.prompt, isNot(contains(typed.explanation)));
        for (final answer in expectedRecall[id]!) {
          expect(
            const TypedFormat().grade(typed, answer).single.rating,
            fsrs.Rating.good,
            reason: '$id: $answer',
          );
        }
        for (final wrong in wrongRecall[id]!) {
          expect(
            const TypedFormat().grade(typed, wrong).single.rating,
            fsrs.Rating.again,
            reason: '$id: $wrong',
          );
        }
        final cue = choices[id]!;
        expect(cue.options.map(normalizeName).toSet(), hasLength(4));
        expect(
          dataset.knowledgeItemCitations
              .where((row) => row.knowledgeItemId == id)
              .map((row) => row.sourceCitationId),
          contains(cue.sourceCitationId),
        );
        final choice = await presenter.present(
          id,
          choiceId,
          certificationId: 'WSET_L4',
          seed: 37,
        ) as AuthoredChoiceQuestion;
        expect(choice.prompt, cue.prompt);
        expect(
          choice.options.map((row) => row.name).toSet(),
          cue.options.toSet(),
        );
        expect(choice.answer.name, cue.options[cue.correctIndex]);
        expect(choice.explanation, cue.explanation);
        expect(choice.sourceCitationId, cue.sourceCitationId);
        expect(choice.prompt, isNot(contains(choice.answer.name)));
        expect(choice.prompt, isNot(contains(choice.explanation)));
        for (final option in choice.options) {
          final grade = const AuthoredChoiceFormat()
              .grade(choice, option)
              .single;
          expect(grade.itemId, id);
          expect(
            grade.rating,
            option == choice.answer ? fsrs.Rating.good : fsrs.Rating.again,
          );
        }
        expect(
          () => const AuthoredChoiceFormat().grade(
            choice,
            const QuestionOption('n_geo_tejo', 'Tejo'),
          ),
          throwsArgumentError,
        );
        await reviews.recordExercise(
          choice,
          const AuthoredChoiceFormat().grade(choice, choice.answer),
        );
      }
      final events = await db.select(db.reviewEvents).get();
      expect(events, hasLength(6));
      expect(events.map((row) => row.knowledgeItemId).toSet(), principleIds);
      expect(
        events.every(
          (row) =>
              row.questionTemplateId == choiceId &&
              row.rating == fsrs.Rating.good.value,
        ),
        isTrue,
      );
      expect(
        (await db.select(db.reviewStates).get())
            .map((row) => row.knowledgeItemId)
            .toSet(),
        principleIds,
      );
      expect({
        for (final row in await db.select(db.userSettings).get())
          row.name: row.value,
      }, settingsBefore);
    } finally {
      await db.close();
    }
  });
  test('real regional cases require all co-roles and independently grade every point', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final pools = (await db.select(db.exercisePools).get())
          .where((row) => row.questionTemplateId == criteriaId)
          .toList();
      expect(pools, hasLength(2));
      expect(pools.map((row) => row.scopeNodeId).toSet(), scope);
      final poolItems = await db.select(db.exercisePoolItems).get();
      for (final pool in pools) {
        expect(
          poolItems.where((row) => row.exercisePoolId == pool.id),
          hasLength(4),
          reason: pool.scopeNodeId,
        );
      }

      final writtenPools = (await db.select(db.exercisePools).get())
          .where((row) => row.questionTemplateId == writtenId)
          .toList();
      expect(writtenPools, hasLength(2));
      expect(writtenPools.map((row) => row.scopeNodeId).toSet(), scope);
      for (final pool in writtenPools) {
        final actual = poolItems
            .where((row) => row.exercisePoolId == pool.id)
            .map((row) => row.knowledgeItemId)
            .toSet();
        expect(
          actual,
          items.values
              .where((row) => row.subjectId == pool.scopeNodeId)
              .map((row) => row.id)
              .toSet(),
        );
      }
      final initialSettings = {
        for (final row in await db.select(db.userSettings).get())
          row.name: row.value,
      };
      final planner = StudyPlanner(db, clock: fixed);
      for (final track in [
        'WSET_L1',
        'WSET_L2',
        'WSET_L3',
        'CMS_INTRODUCTORY',
        'CMS_CERTIFIED',
      ]) {
        expect(
          (await planner.cards(track))
              .map((row) => row.itemId)
              .toSet()
              .intersection(expectedIds),
          isEmpty,
          reason: track,
        );
      }
      final cold = {
        for (final card in await planner.cards('WSET_L4')) card.itemId: card,
      };
      expect(cold.keys.toSet(), containsAll(expectedIds));
      // A shared prerequisite is one study card even when multiple case roles need it.
      final prerequisiteIds = expectedCasePrerequisites.values
          .expand((ids) => ids)
          .toSet();
      expect(prerequisiteIds, hasLength(14));
      expect(
        cold.keys.toSet(),
        containsAll(prerequisiteIds),
        reason:
            'Every distinct prerequisite must remain available through the real L4 inheritance chain; '
            'missing: ${prerequisiteIds.difference(cold.keys.toSet())}',
      );
      for (final id in actions.values) {
        expect(
          cold[id]!.formats.map((row) => row.mode),
          isNot(contains(CaseCriteriaFormat.formatId)),
          reason: id,
        );
      }

      final coldPresenter = ExercisePresenter(db, clock: fixed);
      for (final entry in actions.entries) {
        await expectLater(
          coldPresenter.present(
            entry.value,
            criteriaId,
            certificationId: 'WSET_L4',
            seed: 11,
          ),
          throwsArgumentError,
        );
        final introduction = await coldPresenter.present(
          entry.value,
          writtenId,
          certificationId: 'WSET_L4',
          seed: 11,
        ) as ShortAnswerExercise;
        expect(introduction.itemIds, hasLength(2));
        expect(introduction.itemIds, contains(entry.value));
        expect(
          introduction.itemIds.toSet().difference(
            items.values
                .where((row) => row.subjectId == entry.key)
                .map((row) => row.id)
                .toSet(),
          ),
          isEmpty,
        );
        for (final track in [
          'WSET_L1',
          'WSET_L2',
          'WSET_L3',
          'CMS_INTRODUCTORY',
          'CMS_CERTIFIED',
        ]) {
          for (final templateId in [criteriaId, writtenId]) {
            await expectLater(
              coldPresenter.present(
                entry.value,
                templateId,
                certificationId: track,
                seed: 11,
              ),
              throwsArgumentError,
              reason: track,
            );
          }
        }
      }

      const flashcards = {
        'CASE_ACTION': 'qt_case_action_flashcard',
        'CASE_REASON': 'qt_case_reason_flashcard',
        'CASE_TRADEOFF': 'qt_case_tradeoff_flashcard',
        'CASE_LIMITATION': 'qt_case_limitation_flashcard',
      };
      final flashcardPresenter = QuestionPresenter(db);
      final reviews = ReviewService(db, clock: fixed);
      // Two studied co-roles are insufficient: the third missing point keeps
      // the objective four-role exercise locked while written recall remains.
      for (final entry in actions.entries) {
        final coRoles = dataset.knowledgeItems.where(
          (row) =>
              row.subjectId == entry.key &&
              {'CASE_REASON', 'CASE_TRADEOFF'}.contains(row.relationType),
        );
        for (final item in coRoles) {
          final question = await flashcardPresenter.present(
            item.id,
            flashcards[item.relationType]!,
            seed: 11,
          );
          await reviews.gradeFlashcard(question, fsrs.Rating.good);
        }
        final partial = {
          for (final card in await planner.cards('WSET_L4')) card.itemId: card,
        };
        expect(
          partial[entry.value]!.formats.map((row) => row.mode),
          isNot(contains(CaseCriteriaFormat.formatId)),
        );
        final limitation = dataset.knowledgeItems.singleWhere(
          (row) =>
              row.subjectId == entry.key &&
              row.relationType == 'CASE_LIMITATION',
        );
        final question = await flashcardPresenter.present(
          limitation.id,
          flashcards[limitation.relationType]!,
          seed: 11,
        );
        await reviews.gradeFlashcard(question, fsrs.Rating.good);
      }
      final studied = {
        for (final card in await planner.cards('WSET_L4')) card.itemId: card,
      };
      for (final id in actions.values) {
        expect(
          studied[id]!.formats.map((row) => row.mode),
          contains(CaseCriteriaFormat.formatId),
          reason: id,
        );
      }

      final presenter = ExercisePresenter(db, clock: fixed);
      const criteriaFormat = CaseCriteriaFormat();
      const writtenFormat = ShortAnswerFormat();
      final servedIds = <String>{};
      for (final entry in actions.entries) {
        final exercise = await presenter.present(
          entry.value,
          criteriaId,
          certificationId: 'WSET_L4',
          seed: 11,
        ) as CaseCriteriaExercise;
        expect(exercise.prompt, prompts[entry.key]);
        final caseIds = expectedIds.where((id) {
          final item = dataset.knowledgeItems.singleWhere(
            (row) => row.id == id,
          );
          return item.subjectId == entry.key;
        }).toSet();
        expect(exercise.itemIds.toSet(), caseIds, reason: entry.key);
        expect(exercise.options, hasLength(6), reason: entry.key);
        expect(
          exercise.options.map((row) => row.summary).toSet(),
          hasLength(6),
          reason: entry.key,
        );
        expect(
          exercise.criteria.every(
            (row) =>
                row.assertion.isNotEmpty &&
                row.sources.isNotEmpty &&
                row.sources.every(
                  (source) => source.url?.startsWith('https://') == true,
                ),
          ),
          isTrue,
          reason: entry.key,
        );
        servedIds.addAll(exercise.itemIds);
        final correctByRole = {
          for (final criterion in exercise.criteria)
            criterion.role: criterion.itemId,
        };
        final correct = criteriaFormat.grade(
          exercise,
          CaseCriteriaResponse(correctByRole),
        );
        expect(correct, hasLength(4));
        expect(correct.every((row) => row.rating == fsrs.Rating.good), isTrue);
        await reviews.recordExercise(exercise, correct);
        final otherCaseAction = actions.values.singleWhere(
          (id) => id != entry.value,
        );
        expect(
          () => criteriaFormat.grade(
            exercise,
            CaseCriteriaResponse({
              ...correctByRole,
              'CASE_ACTION': otherCaseAction,
            }),
          ),
          throwsArgumentError,
        );
        final falseOptions = exercise.options
            .where((row) => row.explanation != null)
            .toList();
        expect(falseOptions, hasLength(2));
        for (final falseOption in falseOptions) {
          for (final role in caseCriterionRoles) {
            final grades = criteriaFormat.grade(
              exercise,
              CaseCriteriaResponse({...correctByRole, role: falseOption.id}),
            );
            final ratings = {
              for (final grade in grades) grade.itemId: grade.rating,
            };
            expect(
              ratings[correctByRole[role]],
              fsrs.Rating.again,
              reason: entry.key,
            );
            for (final other in caseCriterionRoles.where(
              (row) => row != role,
            )) {
              expect(
                ratings[correctByRole[other]],
                fsrs.Rating.good,
                reason: entry.key,
              );
            }
          }
        }
        // A supported case point assigned to the wrong role also fails that role.
        final mixed = criteriaFormat.grade(
          exercise,
          CaseCriteriaResponse({
            ...correctByRole,
            'CASE_ACTION': correctByRole['CASE_REASON']!,
            'CASE_REASON': correctByRole['CASE_ACTION']!,
          }),
        );
        expect(
          mixed.singleWhere((row) => row.itemId == entry.value).rating,
          fsrs.Rating.again,
        );
        expect(
          mixed
              .singleWhere((row) => row.itemId == correctByRole['CASE_REASON'])
              .rating,
          fsrs.Rating.again,
        );
        for (final role in ['CASE_TRADEOFF', 'CASE_LIMITATION']) {
          expect(
            mixed
                .singleWhere((row) => row.itemId == correctByRole[role])
                .rating,
            fsrs.Rating.good,
          );
        }

        final written = await presenter.present(
          entry.value,
          writtenId,
          certificationId: 'WSET_L4',
          seed: 11,
        ) as ShortAnswerExercise;
        expect(written.prompt, prompts[entry.key]);
        expect(written.itemIds.toSet(), caseIds, reason: entry.key);
        expect(written.keyPoints, hasLength(4));
        expect(
          written.keyPoints.every((row) => row.statement.isNotEmpty),
          isTrue,
        );
        final writtenCorrect = writtenFormat.grade(
          written,
          ShortAnswerResponse('My original case analysis', caseIds),
        );
        expect(
          writtenCorrect.every((row) => row.rating == fsrs.Rating.good),
          isTrue,
        );
        final uncovered = writtenFormat.grade(
          written,
          ShortAnswerResponse(
            'I omitted the limitation',
            {...caseIds}..remove(correctByRole['CASE_LIMITATION']),
          ),
        );
        expect(
          uncovered
              .singleWhere(
                (row) => row.itemId == correctByRole['CASE_LIMITATION'],
              )
              .rating,
          fsrs.Rating.again,
        );
      }
      expect(servedIds, caseIds);

      final criteriaEvents = (await db.select(db.reviewEvents).get())
          .where((row) => row.questionTemplateId == criteriaId)
          .toList();
      expect(criteriaEvents, hasLength(8));
      expect(criteriaEvents.map((row) => row.knowledgeItemId).toSet(), caseIds);
      expect(
        criteriaEvents.every(
          (row) =>
              row.rating == fsrs.Rating.good.value && row.exerciseId != null,
        ),
        isTrue,
      );
      expect(criteriaEvents.map((row) => row.exerciseId).toSet(), hasLength(2));
      expect(
        (await db.select(db.reviewStates).get())
            .map((row) => row.knowledgeItemId)
            .toSet(),
        caseIds,
      );
      expect({
        for (final row in await db.select(db.userSettings).get())
          row.name: row.value,
      }, initialSettings);

      const policyPath = 'assets/curriculum/coverage_policy.yaml';
      final report =
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
      final measured = report.items
          .where((row) => expectedIds.contains(row.id))
          .toList();
      expect(measured, hasLength(14));
      expect(
        measured.where((row) => row.item.domainId == 'geography'),
        hasLength(6),
      );
      expect(
        measured.where((row) => row.item.domainId == 'winemaking'),
        hasLength(4),
      );
      expect(
        measured.where((row) => row.item.domainId == 'business'),
        hasLength(4),
      );
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        if (principleIds.contains(row.id)) {
          expect(
            row.servedFormats,
            contains('authored_choice'),
            reason: row.id,
          );
          expect(row.servedFormats, contains('typed'), reason: row.id);
        } else {
          expect(row.servedFormats, contains('case_criteria'), reason: row.id);
          expect(row.servedFormats, contains('short_answer'), reason: row.id);
        }
      }
      final manifest = TrackScopeManifest.parse(
        File('assets/curriculum/track_scope.yaml').readAsStringSync(),
      );
      final objectives = {
        for (final row in manifest.tracks['WSET_L4']!.objectives) row.id: row,
      };
      for (final id in ['wset_l4.world.portugal', 'wset_l4.world.comparison']) {
        expect(
          measured
              .where((row) => objectives[id]!.covers!.matches(row))
              .map((row) => row.id)
              .toSet(),
          expectedIds,
          reason: id,
        );
      }
    } finally {
      await db.close();
    }
  });
}
