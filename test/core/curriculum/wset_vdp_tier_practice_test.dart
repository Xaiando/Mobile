import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _templateId = 'qt_wset_l3_geography_vdp_private';
const _meanings = <String, String>{
  'ki_vdp_gutswein_private':
      'Estate-wine tier within the private VDP classification',
  'ki_vdp_ortswein_private':
      'Village-wine tier in the private VDP classification',
  'ki_vdp_erste_lage_private': 'Classified vineyard tier below VDP.GROSSE LAGE',
  'ki_vdp_grosse_lage_private':
      'Highest classified vineyard tier in the private VDP hierarchy',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == _templateId,
  );
  final cues = AuthoredChoiceFormat.itemChoicesOf(template);

  test(
    'four secondary VDP meanings extend only the existing private template',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(template.relationType, 'PRIVATE_CLASSIFICATION_OF');
      expect(template.direction, 'forward');
      expect(template.mode, 'authored_choice');
      expect(template.variant, 'l3_geography_origin_classification');
      expect(cues.keys.toSet(), {
        ..._meanings.keys,
        'ki_vdp_grosses_gewaechs_private',
      });
      final items = {for (final row in dataset.knowledgeItems) row.id: row};
      final citations = {
        for (final row in dataset.knowledgeItemCitations)
          (row.knowledgeItemId, row.sourceCitationId),
      };
      final positions = <int, int>{};
      final lengths = <int, int>{};
      for (final entry in _meanings.entries) {
        final id = entry.key;
        final cue = cues[id]!;
        expect(cue.options[cue.correctIndex], entry.value, reason: id);
        expect(cue.options.toSet(), _meanings.values.toSet(), reason: id);
        expect(cue.prompt, isNot(contains(entry.value)), reason: id);
        expect(cue.explanation, contains('private'), reason: id);
        expect(cue.sourceCitationId, 'src_de_vdp_classification', reason: id);
        expect(citations, contains((id, cue.sourceCitationId)), reason: id);
        expect(items[id]!.verificationStatus, 'unverified', reason: id);
        expect(items[id]!.mcqDisabled, isTrue, reason: id);
        for (final track in {'WSET_L3', 'CMS_CERTIFIED'}) {
          final mapping = dataset.certificationKnowledgeMappings.singleWhere(
            (row) => row.certificationId == track && row.knowledgeItemId == id,
          );
          expect(mapping.importance, 'secondary', reason: '$track $id');
          expect(mapping.minimumDepth, 2, reason: '$track $id');
        }
        positions.update(cue.correctIndex, (n) => n + 1, ifAbsent: () => 1);
        final rank = cue.options
            .where((text) => text.length < entry.value.length)
            .length;
        lengths.update(rank, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(positions, {0: 1, 1: 1, 2: 1, 3: 1});
      expect(lengths, {0: 1, 1: 1, 2: 1, 3: 1});
      final gg = cues['ki_vdp_grosses_gewaechs_private']!;
      expect(gg.correctIndex, 1);
      expect(
        gg.options[gg.correctIndex],
        'Dry wine from a VDP classified site under the private VDP rules',
      );
      expect(gg.sourceCitationId, 'src_de_vdp_classification');
      expect(gg.explanation, contains('§30'));
    },
  );

  group('genuine bundled ingestion and tier grading', () {
    late AppDatabase db;
    late StudyPlanner planner;
    late ExercisePresenter presenter;
    setUpAll(() async {
      db = openTestDatabase();
      final clock = Clock.fixed(dataset.publishedAt.toUtc());
      await CurriculumIngester(
        db,
        clock: clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      planner = StudyPlanner(db, clock: clock);
      presenter = ExercisePresenter(db, clock: clock);
    });
    tearDownAll(() => db.close());

    for (final entry in _meanings.entries) {
      test(
        'the exact meaning of ${entry.key} grades and sibling tiers fail',
        () async {
          final cards = {
            for (final card in await planner.cards('WSET_L3'))
              card.itemId: card,
          };
          final card = cards[entry.key];
          expect(card, isNotNull);
          expect(card!.isNew, isTrue);
          expect(card.mapping.importance, 'secondary');
          expect(card.mapping.minimumDepth, 2);
          expect(
            card.formats.map((row) => row.questionTemplateId),
            containsAll({
              _templateId,
              'qt_private_classification_fwd_flashcard',
              'qt_private_classification_fwd_typed',
            }),
          );
          final generated = await db.select(db.questions).get();
          expect(
            generated.where(
              (row) =>
                  row.knowledgeItemId == entry.key &&
                  row.questionTemplateId == _templateId,
            ),
            hasLength(1),
          );
          for (final seed in [5, 23]) {
            final question = await presenter.present(
              entry.key,
              _templateId,
              seed: seed,
              certificationId: 'WSET_L3',
            ) as AuthoredChoiceQuestion;
            expect(question.answer.name, entry.value);
            expect(question.sourceCitationId, 'src_de_vdp_classification');
            expect(
              question.options.map((option) => option.name).toSet(),
              _meanings.values.toSet(),
            );
            const format = AuthoredChoiceFormat();
            expect(() => format.grade(question, 'VDP'), throwsArgumentError);
            // Association ownership is not a responsive answer to a tier question.
            final good = format.grade(question, question.answer).single;
            expect(good.itemId, entry.key);
            expect(good.rating, fsrs.Rating.good);
            expect(
              (good.payload! as Map<String, dynamic>)['sourceCitationId'],
              'src_de_vdp_classification',
            );
            final wrong = question.options.where(
              (option) => option != question.answer,
            );
            expect(wrong, hasLength(3));
            expect(
              wrong.map((option) => option.name).toSet(),
              _meanings.values
                  .where((meaning) => meaning != entry.value)
                  .toSet(),
            );
            for (final sibling in wrong) {
              final grade = format.grade(question, sibling).single;
              expect(grade.itemId, entry.key);
              expect(grade.rating, fsrs.Rating.again, reason: sibling.name);
            }
          }
          expect(await db.select(db.reviewStates).get(), isEmpty);
          expect(await db.select(db.reviewEvents).get(), isEmpty);
        },
      );
    }

    test(
      'useful secondary practice keeps lower fact counts and core denominators',
      () async {
        for (final baseline in const {
          'WSET_L1': 132,
          'WSET_L2': 844,
          'WSET_L3': 3444,
        }.entries) {
          final cards = await planner.cards(baseline.key);
          expect(cards, hasLength(baseline.value), reason: baseline.key);
          if (baseline.key != 'WSET_L3') {
            expect(
              cards
                  .map((card) => card.itemId)
                  .toSet()
                  .intersection(_meanings.keys.toSet()),
              isEmpty,
              reason: baseline.key,
            );
          }
        }
        final audit =
            await CoverageChecker(
              db,
              CoveragePolicy.parse(
                File('assets/curriculum/coverage_policy.yaml')
                    .readAsStringSync(),
              ),
            ).check(
              'WSET_L3',
              on: dataset.publishedAt.toUtc().toIso8601String().substring(
                0,
                10,
              ),
            );
        expect(audit.counts[CoverageMetric.core], 2246);
        expect(audit.counts[CoverageMetric.coreUsefulPractice], 2246);
        for (final id in _meanings.keys) {
          final item = audit.items.singleWhere((row) => row.id == id);
          expect(item.isCore, isFalse, reason: id);
          expect(item.hasUsefulPractice, isTrue, reason: id);
        }
        final gg = await presenter.present(
          'ki_vdp_grosses_gewaechs_private',
          _templateId,
          seed: 23,
          certificationId: 'WSET_L3',
        ) as AuthoredChoiceQuestion;
        expect(
          gg.answer.name,
          'Dry wine from a VDP classified site under the private VDP rules',
        );
        const format = AuthoredChoiceFormat();
        expect(format.grade(gg, gg.answer).single.rating, fsrs.Rating.good);
        for (final alternative in gg.options.where((row) => row != gg.answer)) {
          expect(
            format.grade(gg, alternative).single.rating,
            fsrs.Rating.again,
          );
        }
      },
    );
  });
}
