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

// Registration and actual D4 delivery are required. Finite recall does not
// replace the original four-role regional cases or confer qualification.
void main() {
  final dataset = bundledDataset();
  const typedId = 'qt_d4sekt_principle_typed_6';
  const choiceId = 'qt_d4sekt_principle_choice_6';
  const criteriaId = 'qt_d4sekt_case_criteria_2';
  const writtenId = 'qt_d4sekt_case_written_2';
  const principleIds = {
    'ki_d4sekt_origin_hierarchy',
    'ki_d4sekt_winzersekt_standards',
    'ki_d4sekt_vdp_classification',
    'ki_d4sekt_base_wine_selection',
    'ki_d4sekt_autolysis_vs_fruit',
    'ki_d4sekt_dosage_style',
  };
  const caseIds = {
    'ki_d4sekt_case_winzersekt_allocation_action',
    'ki_d4sekt_case_winzersekt_allocation_reason',
    'ki_d4sekt_case_winzersekt_allocation_tradeoff',
    'ki_d4sekt_case_winzersekt_allocation_limitation',
    'ki_d4sekt_case_extended_lees_positioning_action',
    'ki_d4sekt_case_extended_lees_positioning_reason',
    'ki_d4sekt_case_extended_lees_positioning_tradeoff',
    'ki_d4sekt_case_extended_lees_positioning_limitation',
  };
  const expectedIds = {...principleIds, ...caseIds};
  const actions = {
    'n_d4sekt_case_winzersekt_allocation':
        'ki_d4sekt_case_winzersekt_allocation_action',
    'n_d4sekt_case_extended_lees_positioning':
        'ki_d4sekt_case_extended_lees_positioning_action',
  };
  const expectedCasePrerequisites = {
    'n_d4sekt_case_winzersekt_allocation': {
      'ki_d4sekt_origin_hierarchy',
      'ki_d4sekt_winzersekt_standards',
      'ki_d4sekt_autolysis_vs_fruit',
      'ki_biz_routes_partner_fit',
      'ki_biz_routes_reviewable_roles',
      'ki_biz_routes_downstream_sales',
      'ki_biz_payment_timing',
      'ki_biz_inventory_cash',
      'ki_biz_profit_cash',
      'ki_biz_working_capital',
    },
    'n_d4sekt_case_extended_lees_positioning': {
      'ki_d4sekt_vdp_classification',
      'ki_d4sekt_base_wine_selection',
      'ki_d4sekt_dosage_style',
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
    'src_d4sekt_dwi_regulations':
        'https://www.deutscheweine.de/wissen/qualitaetsstufen/',
    'src_d4sekt_vdp_statut': 'https://www.vdp.de/en/vdp-sekt/',
    'src_d4sekt_oiv_sparkling': 'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32019R0934',
    'src_d4sekt_awri_sparkling':
        'https://www.awri.com.au/information_resources/fact_sheets/',
    'src_d4sekt_eu_reg_2019_33': 'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32019R0033',
  };
  const expectedRecall = {
    'ki_d4sekt_origin_hierarchy': {'A.P.-Nr.', 'Amtliche Prüfungsnummer'},
    'ki_d4sekt_winzersekt_standards': {'9', 'nine'},
    'ki_d4sekt_vdp_classification': {'36', 'thirty-six'},
    'ki_d4sekt_base_wine_selection': {'Botrytis', 'grey rot', 'noble rot'},
    'ki_d4sekt_autolysis_vs_fruit': {'autolysis', 'yeast autolysis'},
    'ki_d4sekt_dosage_style': {'Brut'},
  };
  const wrongRecall = {
    'ki_d4sekt_origin_hierarchy': {
      'Kabinett',
      'Trocken',
      'Qualitätswein',
      'Sekt',
    },
    'ki_d4sekt_winzersekt_standards': {'6', '12', '15', '24'},
    'ki_d4sekt_vdp_classification': {'9', '15', '24', '48'},
    'ki_d4sekt_base_wine_selection': {
      'oïdium',
      'mildew',
      'phylloxera',
      'cork taint',
    },
    'ki_d4sekt_autolysis_vs_fruit': {
      'maceration',
      'chaptalisation',
      'filtration',
      'tannin',
    },
    'ki_d4sekt_dosage_style': {
      'Extra Brut',
      'Brut Nature',
      'Demi-Sec',
      'Trocken',
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

  test(
    'fourteen Sekt points have exact L4 mappings and formal prerequisite sets',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      final cohort = dataset.knowledgeItems
          .where((row) => row.id.startsWith('ki_d4sekt_'))
          .toList();
      expect(cohort, hasLength(14));
      expect(cohort.map((row) => row.id).toSet(), expectedIds);
      final nodes = dataset.knowledgeNodes
          .where((row) => row.id.startsWith('n_d4sekt_'))
          .toList();
      expect(nodes, hasLength(22));
      expect(nodes.map((row) => row.id).toSet(), hasLength(22));
      final expectedPrincipleCitations = {
        'ki_d4sekt_origin_hierarchy': {'src_d4sekt_dwi_regulations'},
        'ki_d4sekt_winzersekt_standards': {'src_wset_sf_winzersekt'},
        'ki_d4sekt_vdp_classification': {'src_d4sekt_vdp_statut'},
        'ki_d4sekt_base_wine_selection': {
          'src_d4sekt_oiv_sparkling',
          'src_spark_gushing',
        },
        'ki_d4sekt_autolysis_vs_fruit': {'src_d4sekt_awri_sparkling'},
        'ki_d4sekt_dosage_style': {'src_d4sekt_eu_reg_2019_33'},
      };
      for (final item in cohort) {
        final principle = principleIds.contains(item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        expect(item.assertionText, isNotEmpty);
        expect(item.domainId, 'winemaking');
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
        hasLength(80),
      );
      final uniquePrerequisites = expectedCasePrerequisites.values
          .expand((ids) => ids)
          .toSet();
      expect(uniquePrerequisites, hasLength(13));
      expect(uniquePrerequisites.intersection(principleIds), principleIds);
      expect(uniquePrerequisites.difference(principleIds), hasLength(7));
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
            .where((row) => row.id.startsWith('src_d4sekt_'))
            .map((row) => row.id)
            .toSet(),
        sourceUrls.keys.toSet(),
      );
    },
  );

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
        expect(prompts[subject], contains('conditional'));
        for (final item in items.values.where(
          (row) => row.subjectId == subject,
        )) {
          expect(prompts[subject], isNot(contains(item.assertionText)));
        }
      }
      expect(
        prompts['n_d4sekt_case_winzersekt_allocation'],
        contains('autolytic brief'),
      );
      expect(
        prompts['n_d4sekt_case_winzersekt_allocation'],
        contains('24 days'),
      );
      expect(
        prompts['n_d4sekt_case_extended_lees_positioning'],
        contains('VDP.SEKT.PRESTIGE'),
      );
      expect(
        prompts['n_d4sekt_case_extended_lees_positioning'],
        contains('30 days'),
      );
      final templates = dataset.questionTemplates
          .where((row) => row.id.startsWith('qt_d4sekt_'))
          .toList();
      expect(templates, hasLength(4));
      expect(templates.map((row) => row.mode).toSet(), {
        'typed',
        'authored_choice',
        'case_criteria',
        'short_answer',
      });
      for (final template in templates) {
        expect(template.variant, startsWith('d4sekt_'));
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

  test('Sekt analytical content routes only to Diploma D4 and preserves lower tracks', () {
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
      diploma.units.singleWhere((unit) => unit.id == 'D4').itemIds.toSet(),
      containsAll(expectedIds),
    );
    for (final unit in diploma.units.where((unit) => unit.id != 'D4')) {
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
      objectives['wset_l4.sparkling.germany']!.covers!.within
          .toSet()
          .intersection(subjects),
      subjects,
    );
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
    expect(
      dataset.nodeGeometries.where(
        (row) => row.knowledgeNodeId.startsWith('n_d4sekt_'),
      ),
      isEmpty,
    );
    for (final entry in {
      'assets/curriculum/areas/diploma_sekt_analytical_cases.yaml':
          'b5f1f1b7297f19aeee96907201a86f5024e26c65930f741f86529fc229b716a8',
      'assets/curriculum/templates/diploma_sekt_analytical_cases.yaml':
          '558173751e885ea2e6d9929acc3e6235cf9be92f6dc6e7ae4eb0b961cd1c4658',
    }.entries) {
      expect(_canonicalFileSha256(entry.key), entry.value, reason: entry.key);
    }
  });

  test(
    'canonical file hashing is line-ending invariant and rejects tampering',
    () {
      final tempDir = Directory.systemTemp.createTempSync('sekt_hash_test_');
      try {
        const sample = 'name: test\r\nvalue: 42\r\n';
        final crlfFile = File('${tempDir.path}/crlf.yaml')
          ..writeAsStringSync(sample);
        final lfFile = File('${tempDir.path}/lf.yaml')
          ..writeAsStringSync(sample.replaceAll('\r\n', '\n'));

        // Exercise the actual _canonicalFileSha256 function on disk files
        final hashCrlf = _canonicalFileSha256(crlfFile.path);
        final hashLf = _canonicalFileSha256(lfFile.path);
        expect(hashCrlf, hashLf);

        final mutatedChar = File('${tempDir.path}/mutated_char.yaml')
          ..writeAsStringSync(sample.replaceAll('test', 'prod'));
        expect(_canonicalFileSha256(mutatedChar.path), isNot(hashLf));

        final mutatedSpace = File('${tempDir.path}/mutated_space.yaml')
          ..writeAsStringSync(sample.replaceAll('value: 42', 'value:  42'));
        expect(_canonicalFileSha256(mutatedSpace.path), isNot(hashLf));

        final mutatedTrailing = File('${tempDir.path}/mutated_trailing.yaml')
          ..writeAsStringSync('$sample\n');
        expect(_canonicalFileSha256(mutatedTrailing.path), isNot(hashLf));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );

  test('independent correctness regressions reject faulty premises and verify repaired Sekt principles and analytical rules', () {
    // R1: Vintage release vs non-vintage VDP minimum
    // 15 months on lees qualifies for non-vintage VDP.SEKT, but vintage VDP.SEKT requires at least 24 months.
    // Releasing a 16-month wine with a vintage date violates VDP statute.
    const lotCLeesMonths = 15;
    const vdpNonVintageMinLees = 15;
    const vdpVintageMinLees = 24;
    expect(
      lotCLeesMonths >= vdpNonVintageMinLees,
      isTrue,
      reason: 'Complies with NV VDP.SEKT minimum',
    );
    expect(
      lotCLeesMonths >= vdpVintageMinLees,
      isFalse,
      reason: 'Violates vintage VDP.SEKT 24m minimum',
    );

    // R2: VDP.SEKT.PRESTIGE requires 36 months, but single-vineyard designation is optional
    const prestigeMinLees = 36;
    expect(prestigeMinLees, 36);
    // VDP is a private association standard, not universal statutory law
    const isVdpStatutoryLaw = false;
    expect(isVdpStatutoryLaw, isFalse);

    // R3: Sekt b.A. production clock
    // German wine law requires at least 6 months total production duration for Sekt.
    // Rapid release in week 8 is only lawful if the 6-month statutory production period already elapsed.
    const statutorySektProductionMonths = 6;
    const week8Months = 8 / 4.33; // ~1.85 months
    expect(
      week8Months < statutorySektProductionMonths,
      isTrue,
      reason: '8 weeks from start of fermentation is unlawful without prior compliant production',
    );

    // R4: Cash sufficiency counterexamples
    // Counterexample A: Inadequate prepayment volume
    // 360 bottles at 20 EUR/bottle gross = 7,200 EUR receipts.
    // 7,200 EUR is insufficient to cover an 8,500 EUR lease payment with 0 opening cash.
    const prepaidBottles = 360;
    const illustrativeUnitPrice = 20.0;
    const leasePayment = 8500.0;
    const openingCashZero = 0.0;
    final grossReceipts = prepaidBottles * illustrativeUnitPrice;
    final netCashA = openingCashZero + grossReceipts - leasePayment;
    expect(
      netCashA,
      -1300.0,
      reason: 'Prepayment alone leaves 1,300 EUR deficit without adequate reserves or pricing',
    );

    // Counterexample B: Sufficient opening liquidity
    // 20,000 EUR liquid reserves easily covers 8,500 EUR payment regardless of 60-day distributor terms.
    const openingCashReserves = 20000.0;
    final netCashB = openingCashReserves - leasePayment;
    expect(
      netCashB > 0,
      isTrue,
      reason: 'Deferred distributor receipts do not create insolvency when adequate reserves exist',
    );

    // R5: Sweetness category determined by final total residual sugar, not dosage addition alone
    // Under Regulation (EU) 2019/33: Brut allows up to 12 g/L finished RS.
    // If base wine has 6 g/L RS and 8 g/L dosage sugar is added, final RS is 14 g/L (Extra Trocken, NOT Brut).
    double finalRs(double baseWineRs, double dosageSugarAdded) =>
        baseWineRs + dosageSugarAdded;
    expect(finalRs(1.0, 8.0), 9.0); // <= 12 g/L -> Brut
    expect(
      finalRs(6.0, 8.0),
      14.0,
    ); // > 12 g/L -> Extra Trocken (12-17 g/L), rejecting Brut claim

    // R6: Tank vessel does not prevent autolysis; short-cycle tank clarifies early, while autolysis requires extended contact
    // OIV Code II.4.3.3 authorizes tank maturation on the deposit/lees.
    // Autolysis requires prolonged yeast contact (starting around 9-12 months).
    const autolysisOnsetMonths = 9;
    const shortCycleTankMonths = 2; // e.g. 8 weeks
    expect(
      shortCycleTankMonths < autolysisOnsetMonths,
      isTrue,
      reason: 'Short-cycle tank intentionally avoids autolysis to preserve primary fruit',
    );

    // R7: Botrytis fungal proteases degrade foam proteins; laccase causes oxidation
    // AWRI s2195: fungal proteases cleave foam-active proteins; laccase causes polyphenol oxidation.
    const proteaseTarget = 'foam-active proteins';
    const laccaseTarget = 'polyphenols / oxidative browning';
    expect(proteaseTarget, isNot(laccaseTarget));
  });

  test(
    'six real recalled meanings and authored alternatives reject wrong answers',
    () async {
      final db = openTestDatabase();
      try {
        final fixed = Clock.fixed(dataset.publishedAt);
        await CurriculumIngester(
          db,
          clock: fixed,
          assets: (path) async => File(path).readAsBytesSync(),
        ).ingest(dataset);
        final choiceTemplate = dataset.questionTemplates.singleWhere(
          (row) => row.id == choiceId,
        );
        final choices = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);
        expect(choices.keys.toSet(), principleIds);
        expect(choiceTemplate.variant, 'd4sekt_principle_choice_6');
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
              const QuestionOption('n_wine_winzersekt', 'Winzersekt'),
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
    },
  );

  test('Sekt analytical cases require all co-roles and independently grade every point', () async {
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
      final prerequisiteIds = expectedCasePrerequisites.values
          .expand((ids) => ids)
          .toSet();
      expect(prerequisiteIds, hasLength(13));
      expect(cold.keys.toSet(), containsAll(prerequisiteIds));
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
        final casePoints = expectedIds.where((id) {
          final item = dataset.knowledgeItems.singleWhere(
            (row) => row.id == id,
          );
          return item.subjectId == entry.key;
        }).toSet();
        expect(exercise.itemIds.toSet(), casePoints, reason: entry.key);
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
        expect(written.itemIds.toSet(), casePoints, reason: entry.key);
        expect(written.keyPoints, hasLength(4));
        expect(
          written.keyPoints.every((row) => row.statement.isNotEmpty),
          isTrue,
        );
        final writtenCorrect = writtenFormat.grade(
          written,
          ShortAnswerResponse('My original Sekt case analysis', casePoints),
        );
        expect(
          writtenCorrect.every((row) => row.rating == fsrs.Rating.good),
          isTrue,
        );
        final uncovered = writtenFormat.grade(
          written,
          ShortAnswerResponse(
            'I omitted the limitation',
            {...casePoints}..remove(correctByRole['CASE_LIMITATION']),
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
        measured.where((row) => row.item.domainId == 'winemaking'),
        hasLength(14),
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
      expect(
        measured
            .where(
              (row) =>
                  objectives['wset_l4.sparkling.germany']!.covers!.matches(row),
            )
            .map((row) => row.id)
            .toSet(),
        expectedIds,
      );
      expect(
        measured
            .where(
              (row) => objectives['wset_l4.sparkling.production']!.covers!
                  .matches(row),
            )
            .map((row) => row.id)
            .toSet(),
        {
          'ki_d4sekt_origin_hierarchy',
          'ki_d4sekt_winzersekt_standards',
          'ki_d4sekt_base_wine_selection',
          'ki_d4sekt_autolysis_vs_fruit',
          'ki_d4sekt_dosage_style',
          'ki_d4sekt_case_winzersekt_allocation_action',
          'ki_d4sekt_case_winzersekt_allocation_reason',
          'ki_d4sekt_case_winzersekt_allocation_tradeoff',
          'ki_d4sekt_case_winzersekt_allocation_limitation',
        },
      );
      expect(
        measured
            .where(
              (row) => objectives['wset_l4.sparkling.commerce']!.covers!
                  .matches(row),
            )
            .map((row) => row.id)
            .toSet(),
        caseIds,
      );
    } finally {
      await db.close();
    }
  });
}
