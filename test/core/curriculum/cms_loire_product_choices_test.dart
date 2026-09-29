import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  const templateId = 'qt_cms_loire_product_choices_6';
  const itemIds = {
    'ki_cms_loire_cheverny_red_rose',
    'ki_cms_loire_cheverny_white',
    'ki_cms_loire_orleans_red_rose',
    'ki_cms_loire_orleans_white',
    'ki_cms_loire_saint_pourcain_red_rose',
    'ki_cms_loire_saint_pourcain_white',
  };
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == templateId,
  );
  final cues = AuthoredChoiceFormat.itemChoicesOf(template);

  test('six existing CMS Loire facts have one cited product choice each', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(cues.keys.toSet(), itemIds);
    final owners = <String, List<String>>{};
    for (final authored in dataset.questionTemplates.where(
      (row) => row.mode == AuthoredChoiceFormat.formatId,
    )) {
      for (final id in AuthoredChoiceFormat.itemChoicesOf(authored).keys) {
        if (itemIds.contains(id)) {
          (owners[id] ??= <String>[]).add(authored.id);
        }
      }
    }
    final answerPositions = <int, int>{};
    final answerLengths = <int, int>{};
    for (final entry in cues.entries) {
      final id = entry.key;
      final cue = entry.value;
      expect(owners[id], [templateId], reason: id);
      expect(items[id]!.domainId, 'geography', reason: id);
      expect(items[id]!.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(items[id]!.verificationStatus, 'unverified', reason: id);
      expect(items[id]!.mcqDisabled, isTrue, reason: id);
      final mappings = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == id)
          .toList();
      expect(mappings, hasLength(1), reason: id);
      expect(mappings.single.certificationId, 'CMS_CERTIFIED', reason: id);
      expect(mappings.single.importance, 'core', reason: id);
      expect(mappings.single.minimumDepth, 2, reason: id);
      expect(cue.options, hasLength(4), reason: id);
      expect(cue.options.toSet(), hasLength(4), reason: id);
      expect(
        dataset.knowledgeItemCitations.any(
          (row) =>
              row.knowledgeItemId == id &&
              row.sourceCitationId == cue.sourceCitationId &&
              (row.locator?.isNotEmpty == true),
        ),
        isTrue,
        reason: id,
      );
      final source = sources[cue.sourceCitationId]!;
      expect(source.kind, anyOf('legislation', 'regulator_register'));
      expect(source.url, startsWith('https://'));
      expect(
        Uri.parse(source.url!).host,
        anyOf('info.agriculture.gouv.fr', 'inao.gouv.fr', 'www.inao.gouv.fr'),
      );
      answerPositions.update(
        cue.correctIndex,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final rank = cue.options
          .where(
            (option) => option.length < cue.options[cue.correctIndex].length,
          )
          .length;
      answerLengths.update(rank, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(answerPositions, {0: 2, 1: 2, 2: 1, 3: 1});
    expect(answerLengths, {0: 2, 1: 2, 2: 1, 3: 1});
  });

  test('Cheverny partner correction uses the approved 2025 specification', () {
    final source = sources['src_cms_loire_cheverny_cdc_2025']!;
    expect(source.kind, 'legislation');
    expect(source.documentIdentifier, contains('5 décembre 2025'));
    expect(source.url, contains('document_administratif-5a98c628-'));
    expect(source.url, isNot(contains('PNO')));
    final white = items['ki_cms_loire_cheverny_white']!.assertionText;
    for (final grape in [
      'Sauvignon Blanc',
      'Sauvignon Gris',
      'Chardonnay',
      'Chenin',
      'Orbois',
    ]) {
      expect(white, contains(grape), reason: grape);
    }
    expect(white, contains('at least one complementary grape'));
    expect(white, contains('not a compulsory component'));
    final cue = cues['ki_cms_loire_cheverny_white']!;
    expect(cue.sourceCitationId, source.id);
    final answer = cue.options[cue.correctIndex];
    expect(answer, contains('permitted partner'));
    expect(answer, contains('Chenin and Orbois'));
    for (final id in itemIds.where((id) => id.endsWith('_red_rose'))) {
      expect(cues[id]!.prompt, contains('red'), reason: id);
      expect(cues[id]!.explanation, contains('rosé'), reason: id);
    }
  });

  test(
    'all six choices are served, cited and useful in Certified Study',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final questions = (await db.select(db.questions).get())
          .where((row) => row.questionTemplateId == templateId)
          .toList();
      expect(questions, hasLength(6));
      expect(questions.map((row) => row.knowledgeItemId).toSet(), itemIds);
      final cards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('CMS_CERTIFIED'))
          card.itemId: card,
      };
      final presenter = ExercisePresenter(db, clock: clock);
      const format = AuthoredChoiceFormat();
      for (final id in itemIds) {
        expect(cards[id], isNotNull, reason: id);
        expect(
          cards[id]!.formats.map((row) => row.questionTemplateId),
          contains(templateId),
          reason: id,
        );
        final question = await presenter.present(
          id,
          templateId,
          seed: 19,
          certificationId: 'CMS_CERTIFIED',
        ) as AuthoredChoiceQuestion;
        final cue = cues[id]!;
        expect(question.knowledgeItemId, id);
        expect(question.sourceCitationId, cue.sourceCitationId);
        expect(
          question.options.map((option) => option.name),
          unorderedEquals(cue.options),
        );
        expect(question.answer.name, cue.options[cue.correctIndex]);
        expect(
          format.grade(question, question.answer).single.rating,
          fsrs.Rating.good,
        );
        for (final wrong in question.options.where(
          (option) => option != question.answer,
        )) {
          expect(
            format.grade(question, wrong).single.rating,
            fsrs.Rating.again,
          );
        }
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
      final measured = report.items.where((row) => itemIds.contains(row.id));
      expect(measured, hasLength(6));
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(row.servedFormats, contains('authored_choice'), reason: row.id);
        expect(row.servedFormats, contains('flashcard'), reason: row.id);
      }
    },
  );
}
