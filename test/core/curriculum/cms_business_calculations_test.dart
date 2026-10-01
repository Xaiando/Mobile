import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/numeric/numeric_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _answers = {
  'ki_cms_calc_full_pours': (7.0, 'pours'),
  'ki_cms_calc_event_bottles': (14.0, 'bottles'),
  'ki_cms_calc_gross_profit': (18.0, 'EUR'),
  'ki_cms_calc_gross_margin': (60.0, '%'),
  'ki_cms_calc_markup': (150.0, '%'),
  'ki_cms_calc_target_price': (30.0, 'EUR'),
};
const _diplomaIds = {
  'ki_d2_calc_unit_contribution',
  'ki_d2_calc_breakeven_bottles',
  'ki_d2_calc_fx_receipt',
  'ki_d2_calc_fx_receipt_reduction',
  'ki_d2_calc_landed_cost_per_bottle',
  'ki_d2_calc_cash_gap_days',
};
const _template = 'qt_cms_calculated_value_fwd_numeric';

void main() {
  final dataset = bundledDataset();
  final items = {for (final row in dataset.knowledgeItems) row.id: row};

  test(
    'hypothetical calculations have exact units and only Certified mappings',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      final relation = dataset.relationTypes.singleWhere(
        (row) => row.id == 'CALCULATED_VALUE',
      );
      expect(relation.cardinality, 'one');
      expect(relation.defaultDomainId, 'business');
      final calculationItems = dataset.knowledgeItems.where(
        (row) => row.relationType == 'CALCULATED_VALUE',
      );
      expect(calculationItems.map((row) => row.id).toSet(), {
        ..._answers.keys,
        ..._diplomaIds,
      });
      expect(
        calculationItems
            .where((row) => row.id.startsWith('ki_cms_calc_'))
            .map((row) => row.id)
            .toSet(),
        _answers.keys.toSet(),
      );
      for (final id in _diplomaIds) {
        final mappings = dataset.certificationKnowledgeMappings.where(
          (row) => row.knowledgeItemId == id,
        );
        expect(mappings, hasLength(1));
        expect(
          (
            mappings.single.certificationId,
            mappings.single.importance,
            mappings.single.minimumDepth,
          ),
          ('WSET_L4', 'core', 2),
        );
      }
      final quantityById = {
        for (final row in dataset.quantityValues) row.knowledgeNodeId: row,
      };
      for (final entry in _answers.entries) {
        final item = items[entry.key]!;
        expect(item.domainId, 'business');
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue);
        final quantity = quantityById[item.objectId]!;
        expect(quantity.minimum, entry.value.$1, reason: entry.key);
        expect(quantity.maximum, entry.value.$1, reason: entry.key);
        expect(quantity.unit, entry.value.$2, reason: entry.key);
        final mappings = dataset.certificationKnowledgeMappings.where(
          (row) => row.knowledgeItemId == item.id,
        );
        expect(mappings, hasLength(1));
        expect(mappings.single.certificationId, 'CMS_CERTIFIED');
        expect(mappings.single.minimumDepth, 2);
        expect(mappings.single.importance, 'core');
        final citations = dataset.knowledgeItemCitations.where(
          (row) => row.knowledgeItemId == item.id,
        );
        expect(citations, hasLength(1));
        expect(citations.single.locator, contains('original'));
        expect(
          citations.single.sourceCitationId,
          entry.key == 'ki_cms_calc_full_pours' ||
                  entry.key == 'ki_cms_calc_event_bottles'
              ? 'src_cms_calc_proportions'
              : 'src_biz_victoria_pricing',
        );
      }
      final cmsIds = dataset.certificationKnowledgeMappings
          .where((row) => row.certificationId == 'CMS_CERTIFIED')
          .map((row) => row.knowledgeItemId)
          .toSet();
      final prerequisites = dataset.knowledgeItemPrerequisites.where(
        (row) => _answers.containsKey(row.knowledgeItemId),
      );
      expect(prerequisites, hasLength(4));
      expect(
        prerequisites
            .map((row) => row.prerequisiteItemId)
            .toSet()
            .difference(cmsIds),
        isEmpty,
      );
      expect(
        items['ki_cms_calc_full_pours']!.assertionText,
        contains('not a standard or legal measure'),
      );
      expect(
        items['ki_cms_calc_event_bottles']!.assertionText,
        contains('not a consumption recommendation'),
      );
      expect(
        items['ki_cms_calc_gross_profit']!.assertionText,
        contains('not net profit'),
      );
      expect(
        items['ki_cms_calc_target_price']!.assertionText,
        contains('19.20'),
      );
    },
  );

  test(
    'worked results use unit arithmetic and distinct pricing denominators',
    () {
      expect(
        (750 / 100).floor().toDouble(),
        _answers['ki_cms_calc_full_pours']!.$1,
      );
      expect(
        (40 * 2 * 125 / 750).ceil().toDouble(),
        _answers['ki_cms_calc_event_bottles']!.$1,
      );
      const cost = 12.0;
      const price = 30.0;
      expect(price - cost, _answers['ki_cms_calc_gross_profit']!.$1);
      expect(
        (price - cost) / price * 100,
        _answers['ki_cms_calc_gross_margin']!.$1,
      );
      expect((price - cost) / cost * 100, _answers['ki_cms_calc_markup']!.$1);
      expect(cost / (1 - 0.60), _answers['ki_cms_calc_target_price']!.$1);
    },
  );

  test(
    'ingested quantity examples serve and grade without guessed conversion',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final cards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('CMS_CERTIFIED'))
          card.itemId: card,
      };
      final presenter = ExercisePresenter(db, clock: clock);
      const format = NumericFormat();
      for (final entry in _answers.entries) {
        expect(cards[entry.key], isNotNull, reason: entry.key);
        expect(
          cards[entry.key]!.formats.map((row) => row.questionTemplateId),
          unorderedEquals([_template, 'qt_cms_calculated_value_fwd_flashcard']),
        );
        final question = await presenter.present(
          entry.key,
          _template,
          seed: 23,
          certificationId: 'CMS_CERTIFIED',
        ) as NumericQuestion;
        expect(question.canonicalMinimum, entry.value.$1);
        expect(question.canonicalMaximum, entry.value.$1);
        expect(question.canonicalUnit, entry.value.$2);
        expect(question.exactTolerance, 0);
        expect(question.tolerance, 0);
        final subject = dataset.knowledgeNodes.singleWhere(
          (row) => row.id == items[entry.key]!.subjectId,
        );
        expect(question.prompt, subject.name);
        for (final answer in [
          '${entry.value.$1}',
          '${entry.value.$1} ${entry.value.$2}',
        ]) {
          expect(
            format.grade(question, answer).single.rating,
            fsrs.Rating.good,
            reason: '${entry.key}: $answer',
          );
        }
        for (final answer in [
          '${entry.value.$1 - 1}',
          '${entry.value.$1 + 1}',
          '${entry.value.$1} kg',
        ]) {
          expect(
            format.grade(question, answer).single.rating,
            fsrs.Rating.again,
            reason: '${entry.key}: $answer',
          );
        }
      }
      for (final (id, wrong) in [
        ('ki_cms_calc_full_pours', '7.5'),
        ('ki_cms_calc_event_bottles', '13'),
        ('ki_cms_calc_gross_margin', '150%'),
        ('ki_cms_calc_gross_margin', r'60$'),
        ('ki_cms_calc_gross_profit', '19 EUR'),
        ('ki_cms_calc_markup', '60%'),
        ('ki_cms_calc_target_price', '19.20 EUR'),
      ]) {
        final question = await presenter.present(
          id,
          _template,
          seed: 23,
          certificationId: 'CMS_CERTIFIED',
        ) as NumericQuestion;
        expect(
          format.grade(question, wrong).single.rating,
          fsrs.Rating.again,
          reason: '$id rejects $wrong',
        );
      }
      const policyPath = 'assets/curriculum/coverage_policy.yaml';
      final report =
          await CoverageChecker(
            db,
            CoveragePolicy.parse(
              File(policyPath).readAsStringSync(),
              path: policyPath,
            ),
          ).check(
            'CMS_CERTIFIED',
            on: dataset.publishedAt.toIso8601String().substring(0, 10),
            skipped: generation.skipped,
          );
      final covered = report.items.where(
        (row) => _answers.containsKey(row.item.id),
      );
      expect(covered, hasLength(6));
      expect(covered.where((row) => !row.hasUsefulPractice), isEmpty);
      for (final track in ['WSET_L1', 'WSET_L2', 'WSET_L3', 'WSET_L4']) {
        final lowerCards = await StudyPlanner(db, clock: clock).cards(track);
        expect(
          lowerCards.where((row) => _answers.containsKey(row.itemId)),
          isEmpty,
          reason: 'CMS calculations do not change $track',
        );
      }
    },
  );
}
