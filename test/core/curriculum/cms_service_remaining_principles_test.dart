import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _templateId = 'qt_cms_service_remaining_principles_33';
const _distillationId = 'ki_cms_example_distillation';
const _choiceIds = {
  'ki_cms_beer_mash',
  'ki_cms_beer_wort',
  'ki_cms_beer_hops',
  'ki_cms_beer_hop_types',
  'ki_cms_beer_yeast',
  'ki_cms_beer_ale_lager',
  'ki_cms_beer_porter_stout',
  'ki_cms_beer_wheat_fruit',
  'ki_cms_beer_cask_live',
  'ki_cms_beer_cask_terms',
  'ki_cms_beer_package',
  'ki_cms_cider_apples',
  'ki_cms_cider_press',
  'ki_cms_cider_practice',
  'ki_cms_cider_style',
  'ki_cms_belgian_wit',
  'ki_cms_belgian_dubbel_tripel',
  'ki_cms_belgian_saison',
  'ki_cms_beer_food_intensity',
  'ki_cms_beer_food_link',
  'ki_cms_beer_food_trial',
  'ki_cms_irish_origin',
  'ki_cms_irish_pot_malt',
  'ki_cms_irish_blend',
  'ki_cms_liqueur_orange',
  'ki_cms_liqueur_herbal',
  'ki_cms_liqueur_compare',
  'ki_cms_pairing_browning',
  'ki_cms_pairing_preparation',
  'ki_cms_pairing_sauce',
  'ki_cms_pairing_vinegar',
  'ki_cms_pairing_chocolate',
  'ki_cms_pairing_caramel',
};

void main() {
  final dataset = bundledDataset();
  final targetIds = {..._choiceIds, _distillationId};
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == _templateId,
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(template);

  test('the remaining service choices retain fact and source scope', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(choices.keys.toSet(), _choiceIds);
    final items = {
      for (final item in dataset.knowledgeItems)
        if (targetIds.contains(item.id)) item.id: item,
    };
    expect(items, hasLength(34));
    final sources = {
      for (final source in dataset.sourceCitations) source.id: source,
    };
    for (final entry in choices.entries) {
      final item = items[entry.key]!;
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: entry.key);
      expect(item.domainId, 'service', reason: entry.key);
      expect(item.mcqDisabled, isTrue, reason: entry.key);
      expect(item.verificationStatus, 'unverified', reason: entry.key);
      expect(entry.value.options, hasLength(4), reason: entry.key);
      expect(entry.value.options.toSet(), hasLength(4), reason: entry.key);
      expect(
        dataset.knowledgeItemCitations.any(
          (row) =>
              row.knowledgeItemId == entry.key &&
              row.sourceCitationId == entry.value.sourceCitationId &&
              row.locator?.isNotEmpty == true,
        ),
        isTrue,
        reason: entry.key,
      );
      expect(
        sources[entry.value.sourceCitationId],
        isNotNull,
        reason: entry.key,
      );
    }
    // These prompts apply bounded references, not laws or tested menu guarantees.
    expect(choices['ki_cms_cider_practice']!.explanation, contains('UK'));
    expect(
      choices['ki_cms_cider_style']!.explanation,
      contains('not universal legal'),
    );
    expect(
      choices['ki_cms_pairing_preparation']!
          .options[choices['ki_cms_pairing_preparation']!.correctIndex],
      contains('not a controlled comparison'),
    );
    expect(
      choices['ki_cms_pairing_caramel']!.explanation,
      contains('does not test or guarantee'),
    );
    expect(
      choices['ki_cms_liqueur_herbal']!.explanation,
      contains('rather than a universal'),
    );
  });

  test('answer positions and length ranks do not supply a dominant clue', () {
    final positions = List<int>.filled(4, 0);
    final lengthRanks = List<int>.filled(4, 0);
    for (final cue in choices.values) {
      positions[cue.correctIndex]++;
      final correctLength = cue.options[cue.correctIndex].length;
      final rank = cue.options
          .where((text) => text.length < correctLength)
          .length;
      lengthRanks[rank]++;
    }
    expect(positions, [9, 8, 8, 8]);
    expect(lengthRanks, [9, 8, 8, 8]);
  });

  test(
    'Certified overrides distillation depth while Introductory stays intact',
    () {
      final mappings = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == _distillationId)
          .toList();
      expect(mappings, hasLength(2));
      final byTrack = {for (final row in mappings) row.certificationId: row};
      expect(byTrack['CMS_INTRODUCTORY']!.importance, 'core');
      expect(byTrack['CMS_INTRODUCTORY']!.minimumDepth, 1);
      expect(byTrack['CMS_CERTIFIED']!.importance, 'core');
      expect(byTrack['CMS_CERTIFIED']!.minimumDepth, 2);
      // A track-specific override must not lower the formats' general depth rules.
      for (final mode in ['flashcard', 'typed', 'short_answer']) {
        expect(appFormats[mode]!.requiredDepth('forward'), 2, reason: mode);
      }
      expect(
        dataset.knowledgeItems.where(
          (row) => row.subjectId == 'n_cms_example_distillation',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'all 34 gaps receive useful practice at the publication instant',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: clock,
      ).ingest(dataset);
      final planner = StudyPlanner(db, clock: clock);
      final cards = {
        for (final card in await planner.cards('CMS_CERTIFIED'))
          card.itemId: card,
      };
      expect(cards.keys, containsAll(targetIds));
      final distillation = cards[_distillationId]!;
      expect(distillation.mapping.minimumDepth, 2);
      expect(
        distillation.formats.map((format) => format.mode).toSet(),
        containsAll({'authored_choice', 'flashcard', 'typed'}),
      );
      final introductory = (await planner.cards('CMS_INTRODUCTORY'))
          .singleWhere((card) => card.itemId == _distillationId);
      expect(introductory.mapping.minimumDepth, 1);
      expect(introductory.formats.map((format) => format.mode).toSet(), {
        'authored_choice',
      });
      for (final track in ['WSET_L1', 'WSET_L2', 'WSET_L3', 'WSET_L4']) {
        final lowerIds = (await planner.cards(track))
            .map((card) => card.itemId)
            .toSet();
        expect(lowerIds.intersection(targetIds), isEmpty, reason: track);
      }

      final presenter = ExercisePresenter(db, clock: clock);
      for (final id in _choiceIds) {
        expect(
          cards[id]!.formats.any(
            (format) => format.questionTemplateId == _templateId,
          ),
          isTrue,
          reason: id,
        );
        final exercise = await presenter.present(
          id,
          _templateId,
          seed: 31,
        ) as AuthoredChoiceQuestion;
        expect(exercise.options, hasLength(4), reason: id);
        expect(
          exercise.answer.name,
          choices[id]!.options[choices[id]!.correctIndex],
          reason: id,
        );
        expect(
          exercise.sourceCitationId,
          choices[id]!.sourceCitationId,
          reason: id,
        );
        final good = const AuthoredChoiceFormat().grade(
          exercise,
          exercise.answer,
        );
        expect(good.single.itemId, id);
        expect(good.single.rating, fsrs.Rating.good);
        final wrong = exercise.options.firstWhere(
          (option) => option != exercise.answer,
        );
        expect(
          const AuthoredChoiceFormat().grade(exercise, wrong).single.rating,
          fsrs.Rating.again,
          reason: id,
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
      final measured = report.items.where((row) => targetIds.contains(row.id));
      expect(measured, hasLength(34));
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(
          row.servedFormats,
          containsAll({'authored_choice', 'flashcard', 'typed'}),
          reason: row.id,
        );
      }
    },
  );
}
