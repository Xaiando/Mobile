import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

String _canonicalFileSha256(String path) {
  final text = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  return sha256.convert(utf8.encode(text)).toString();
}

// Original French cases registered in the isolated 0.24.65 candidate.
// These tests intentionally require both asset registration and explicit D3 scope.
void main() {
  final dataset = bundledDataset();
  const criteriaId = 'qt_d3fr2_case_criteria_2';
  const writtenId = 'qt_d3fr2_case_written_2';
  const actions = {
    'n_d3fr2_case_bordeaux_route': 'ki_d3fr2_case_bordeaux_route_action',
    'n_d3fr2_case_rhone_white': 'ki_d3fr2_case_rhone_white_action',
  };
  const expectedIds = {
    'ki_d3fr2_case_bordeaux_route_action',
    'ki_d3fr2_case_bordeaux_route_reason',
    'ki_d3fr2_case_bordeaux_route_tradeoff',
    'ki_d3fr2_case_bordeaux_route_limitation',
    'ki_d3fr2_case_rhone_white_action',
    'ki_d3fr2_case_rhone_white_reason',
    'ki_d3fr2_case_rhone_white_tradeoff',
    'ki_d3fr2_case_rhone_white_limitation',
  };
  const expectedPrerequisites = {
    'ki_d3fr2_case_bordeaux_route_action': {
      'ki_biz_routes_partner_fit',
      'ki_biz_routes_reviewable_roles',
      'ki_biz_payment_timing',
    },
    'ki_d3fr2_case_bordeaux_route_reason': {
      'ki_wset_eu_bordeaux_classifications_scope',
      'ki_wset_eu_bordeaux_classification_quality',
      'ki_biz_routes_downstream_sales',
      'ki_biz_profit_cash',
    },
    'ki_d3fr2_case_bordeaux_route_tradeoff': {
      'ki_biz_inventory_cash',
      'ki_biz_payment_timing',
      'ki_biz_profit_cash',
    },
    'ki_d3fr2_case_bordeaux_route_limitation': {
      'ki_wset_eu_bordeaux_classifications_scope',
      'ki_biz_working_capital',
      'ki_biz_routes_reviewable_roles',
    },
    'ki_d3fr2_case_rhone_white_action': {
      'ki_reg_fs_marsanne_palate',
      'ki_reg_fs_roussanne_sensitivity',
      'ki_win_mlf_stability',
    },
    'ki_d3fr2_case_rhone_white_reason': {
      'ki_reg_fs_marsanne_palate',
      'ki_reg_fs_roussanne_sensitivity',
      'ki_win_mlf_conversion',
      'ki_win_oak_flavours',
      'ki_win_lees_release',
    },
    'ki_d3fr2_case_rhone_white_tradeoff': {
      'ki_biz_inventory_cash',
      'ki_biz_payment_timing',
      'ki_biz_value_pricing',
    },
    'ki_d3fr2_case_rhone_white_limitation': {
      'ki_win_oak_variables',
      'ki_win_mlf_monitor',
      'ki_reg_fs_roussanne_sensitivity',
    },
  };
  const expectedCitations = {
    'ki_d3fr2_case_bordeaux_route_action': {
      'src_biz_routes_wine_australia_partner',
      'src_biz_routes_wine_australia_terms',
      'src_biz_au_cashflow',
    },
    'ki_d3fr2_case_bordeaux_route_reason': {
      'src_wset_eu_bdx_classification',
      'src_biz_routes_wine_australia_partner',
      'src_biz_sec_statements',
    },
    'ki_d3fr2_case_bordeaux_route_tradeoff': {
      'src_biz_routes_wine_australia_partner',
      'src_biz_au_cashflow',
      'src_biz_sec_statements',
    },
    'ki_d3fr2_case_bordeaux_route_limitation': {
      'src_wset_eu_bdx_classification',
      'src_biz_routes_wine_australia_partner',
      'src_biz_au_cashflow',
    },
    'ki_d3fr2_case_rhone_white_action': {
      'src_d4nw_awri_sensory',
      'src_win_mlf',
      'src_win_lees',
    },
    'ki_d3fr2_case_rhone_white_reason': {
      'src_reg_fs_marsanne',
      'src_reg_fs_roussanne',
      'src_win_mlf_style',
      'src_win_oak',
      'src_win_lees',
    },
    'ki_d3fr2_case_rhone_white_tradeoff': {
      'src_biz_au_cashflow',
      'src_biz_au_pricing',
    },
    'ki_d3fr2_case_rhone_white_limitation': {
      'src_d4nw_awri_sensory',
      'src_win_mlf',
      'src_win_oak',
      'src_biz_au_pricing',
    },
  };
  const preservedHashes = {
    'assets/curriculum/areas/regional_france_comparisons.yaml':
        '59677c19d6dc4bf70f228feabff6a7b5c63b2266e0443b8d7df9a681a2fb5fac',
    'assets/curriculum/areas/regional_france_rivers_southwest_comparisons.yaml':
        '2066becfc88e74982d3b007dc3dcc6b5c03cfa9ce90cc7265881a150d2e73556',
    'assets/curriculum/templates/regional_france_cases.yaml':
        '4adc5ccca94bef0cae9dc29726991535168aa59c1e6c079e37283d0c4d6fef08',
    'assets/curriculum/templates/regional_france_rivers_southwest_cases.yaml':
        'a3a5a07ece747e2178c921d2c55a995e7ddf86cd9edad4e6cb25bc5a89e67a62',
    'assets/curriculum/templates/wset_l3_business_case_criteria.yaml':
        '82922ddc1629b4127b580c7227916c843a8364248c5701a8db3e73518eb4de4f',
    'assets/study/diploma_written_practice.json':
        '25bf2cac634ca23c42d6015aa84b60e35ba97bc063f836a84c9a23e68360fbb0',
  };
  final criteriaTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == criteriaId,
  );
  final writtenTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == writtenId,
  );
  final prompts = CaseCriteriaFormat.scenarioPromptsOf(criteriaTemplate);
  final scope = actions.keys.toSet();

  test('Bordeaux cash and Rhône white packets have exact sourced roles and prerequisites', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), scope);
    expect(ShortAnswerFormat.scopeNodeIdsOf(writtenTemplate), scope);
    expect(prompts.keys.toSet(), scope);
    final distractors = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
    expect(distractors.keys.toSet(), scope);
    final items = dataset.knowledgeItems
        .where((row) => row.id.startsWith('ki_d3fr2_case_'))
        .toList();
    expect(items.map((row) => row.id).toSet(), expectedIds);
    final sourceUrls = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    for (final subject in scope) {
      final node = dataset.knowledgeNodes.singleWhere(
        (row) => row.id == subject,
      );
      expect(node.nodeType, 'production_case');
      expect(node.name, prompts[subject]);
      expect(node.name, startsWith('Fictional'));
      final points = items.where((row) => row.subjectId == subject).toList();
      expect(points, hasLength(4), reason: subject);
      expect(
        points.map((row) => row.relationType).toSet(),
        caseCriterionRoles.toSet(),
      );
      expect(distractors[subject], hasLength(2), reason: subject);
      expect(
        distractors[subject]!.map((row) => row.summary).toSet(),
        hasLength(2),
      );
      expect(
        distractors[subject]!.every(
          (row) => row.explanation?.isNotEmpty ?? false,
        ),
        isTrue,
      );
      for (final item in points) {
        final productionRole =
            subject == 'n_d3fr2_case_rhone_white' &&
            {'CASE_ACTION', 'CASE_REASON'}.contains(item.relationType);
        expect(item.domainId, productionRole ? 'winemaking' : 'business');
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        final mappings = dataset.certificationKnowledgeMappings
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(mappings, hasLength(1), reason: item.id);
        expect(mappings.single.certificationId, 'WSET_L4');
        expect(mappings.single.importance, 'core');
        expect(mappings.single.minimumDepth, 3);
        final linked = dataset.knowledgeItemCitations
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(
          linked.map((row) => row.sourceCitationId).toSet(),
          expectedCitations[item.id],
        );
        for (final citation in linked) {
          expect(sourceUrls[citation.sourceCitationId], startsWith('https://'));
          expect(citation.locator, isNotEmpty);
        }
        final prerequisites = dataset.knowledgeItemPrerequisites
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(
          prerequisites.map((row) => row.prerequisiteItemId).toSet(),
          expectedPrerequisites[item.id],
        );
      }
    }
    expect(
      prompts['n_d3fr2_case_bordeaux_route'],
      contains('payment 60 days after shipment'),
    );
    expect(
      prompts['n_d3fr2_case_bordeaux_route'],
      contains('supplier bill due in 20 days'),
    );
    expect(
      prompts['n_d3fr2_case_bordeaux_route'],
      contains('without naming the system'),
    );
    expect(
      prompts['n_d3fr2_case_bordeaux_route'],
      contains('not standard Bordeaux trade practices or payment law'),
    );
    expect(
      prompts['n_d3fr2_case_rhone_white'],
      contains('Several cellar variables differ'),
    );
    expect(
      prompts['n_d3fr2_case_rhone_white'],
      contains('not legal minima, regional price data or guarantees'),
    );
    final whiteTradeoff = items
        .singleWhere((row) => row.id == 'ki_d3fr2_case_rhone_white_tradeoff')
        .assertionText;
    expect(whiteTradeoff, contains('B would miss the eight-week launch'));
    expect(whiteTradeoff, contains('complete costs'));
    final cashReason = items
        .singleWhere((row) => row.id == 'ki_d3fr2_case_bordeaux_route_reason')
        .assertionText;
    expect(
      cashReason,
      contains('would not itself fund the bill due in 20 days'),
    );
    expect(
      dataset.knowledgeItemPrerequisites.where(
        (row) => expectedIds.contains(row.knowledgeItemId),
      ),
      hasLength(27),
    );
    // Unique identity includes the variant and locale; do not add a duplicate
    // unscoped CASE_ACTION template like the rejected earlier numeric design.
    for (final template in [criteriaTemplate, writtenTemplate]) {
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
      expect(template.variant, startsWith('d3fr2_case_'));
      expect(template.locale, 'en');
    }
  });

  test(
    'regional cases route explicitly to D3 without widening other tracks',
    () {
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
      final d3 = diploma.units.singleWhere((unit) => unit.id == 'D3');
      expect(d3.itemIds.toSet(), containsAll(expectedIds));
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
      expect(
        objectives['wset_l4.world.bordeaux']!.covers!.within,
        contains('n_d3fr2_case_bordeaux_route'),
      );
      expect(
        objectives['wset_l4.world.rhone']!.covers!.within,
        contains('n_d3fr2_case_rhone_white'),
      );
      expect(
        objectives['wset_l4.world.comparison']!.covers!.within,
        containsAll(scope),
      );
      expect(
        objectives['wset_l4.world.comparison']!.covers!.relationTypes,
        containsAll(caseCriterionRoles),
      );
    },
  );

  test(
    'existing French packets and the Diploma written bank stay unchanged',
    () {
      for (final entry in preservedHashes.entries) {
        expect(
          _canonicalFileSha256(entry.key),
          entry.value,
          reason:
              'This batch must not rewrite the existing input: ${entry.key}',
        );
      }
      for (final prefix in [
        'ki_reg_fr_case_bordeaux_blend_',
        'ki_reg_fr_case_rhone_cost_',
        'ki_reg_fs_case_rhone_harvest_water_',
        'ki_reg_fr_case_chardonnay_buy_',
        'ki_reg_fr_case_loire_list_',
        'ki_reg_fs_case_loire_muscadet_inventory_',
      ]) {
        expect(
          dataset.knowledgeItems.where((row) => row.id.startsWith(prefix)),
          hasLength(4),
        );
      }
    },
  );

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

  test('cold and studied French cases preserve isolation and independently grade eight criteria', () async {
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
      final prerequisiteIds = expectedPrerequisites.values
          .expand((ids) => ids)
          .toSet();
      expect(prerequisiteIds, hasLength(18));
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
      expect(servedIds, expectedIds);

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
      expect(measured, hasLength(8));
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(row.servedFormats, contains('case_criteria'), reason: row.id);
        expect(row.servedFormats, contains('short_answer'), reason: row.id);
      }
    } finally {
      await db.close();
    }
  });
}
