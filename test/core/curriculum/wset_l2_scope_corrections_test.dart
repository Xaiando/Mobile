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
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  const choiceId = 'qt_wset_l2_scope_corrections_choice_3';
  const typedId = 'qt_wset_l2_scope_corrections_typed_3';
  const newIds = {
    'ki_wset_l2_kabinett_must_weight',
    'ki_wset_l2_closure_failure_sensory',
    'ki_wset_l2_heat_damage_sensory',
  };
  const ruleIds = {
    'ki_kabinett_rule',
    'ki_spaetlese_rule',
    'ki_auslese_rule',
    'ki_beerenauslese_rule',
    'ki_trockenbeerenauslese_rule',
    'ki_eiswein_rule',
  };
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final choice = dataset.questionTemplates.singleWhere(
    (row) => row.id == choiceId,
  );
  final typed = dataset.questionTemplates.singleWhere(
    (row) => row.id == typedId,
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(choice);
  final recall = TypedFormat.itemCuesOf(typed)!;

  test('six named Prädikate gain L2 recall without lowering higher tracks', () {
    expect(validateDataset(dataset).errors, isEmpty);
    for (final id in ruleIds) {
      final mappings = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == id)
          .toList();
      expect(mappings, hasLength(3), reason: id);
      final byTrack = {for (final row in mappings) row.certificationId: row};
      expect(byTrack.keys.toSet(), {'WSET_L2', 'WSET_L3', 'CMS_CERTIFIED'});
      for (final row in mappings) {
        expect(row.importance, 'core', reason: id);
        expect(
          row.minimumDepth,
          row.certificationId == 'WSET_L2' ? 2 : 3,
          reason: '$id on ${row.certificationId}',
        );
      }
      expect(items[id]!.relationType, 'LEGAL_DEFINITION', reason: id);
      expect(items[id]!.domainId, 'viticulture', reason: id);
      expect(
        dataset.knowledgeItemCitations.any(
          (row) =>
              row.knowledgeItemId == id &&
              row.sourceCitationId == 'src_de_weing',
        ),
        isTrue,
        reason: id,
      );
    }
    // Preserve the shared unenrichment principle and the statutory TBA exception.
    expect(
      items['ki_kabinett_rule']!.assertionText,
      contains('every higher Prädikat must also be unenriched'),
    );
    expect(
      items['ki_trockenbeerenauslese_rule']!.assertionText,
      contains('where noble rot exceptionally fails'),
    );
    expect(
      items['ki_eiswein_rule']!.assertionText,
      contains('frozen when they are harvested and pressed'),
    );

    final l2Ids = dataset.certificationKnowledgeMappings
        .where((row) => row.certificationId == 'WSET_L2')
        .map((row) => row.knowledgeItemId)
        .toSet();
    final prerequisiteIds = dataset.knowledgeItemPrerequisites
        .where((row) => {...ruleIds, ...newIds}.contains(row.knowledgeItemId))
        .map((row) => row.prerequisiteItemId)
        .toSet();
    expect(prerequisiteIds, contains('ki_praedikatswein_protection'));
    expect(
      prerequisiteIds.difference(l2Ids),
      isEmpty,
      reason: 'newly mapped rules retain reachable Level 2 prerequisites',
    );
  });

  test(
    'three original points have scoped, cited and balanced alternatives',
    () {
      expect(choices.keys.toSet(), newIds);
      expect(recall.keys.toSet(), newIds);
      final answerPositions = <int, int>{};
      final answerLengths = <int, int>{};
      final sources = {
        for (final source in dataset.sourceCitations) source.id: source,
      };
      for (final id in newIds) {
        final item = items[id]!;
        expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
        expect(item.verificationStatus, 'unverified', reason: id);
        expect(item.mcqDisabled, isTrue, reason: id);
        expect(
          item.domainId,
          id == 'ki_wset_l2_kabinett_must_weight' ? 'viticulture' : 'service',
        );
        final mappings = dataset.certificationKnowledgeMappings
            .where((row) => row.knowledgeItemId == id)
            .toList();
        expect(mappings, hasLength(1), reason: id);
        expect(mappings.single.certificationId, 'WSET_L2', reason: id);
        expect(mappings.single.importance, 'core', reason: id);
        expect(mappings.single.minimumDepth, 2, reason: id);
        final cue = choices[id]!;
        expect(cue.options, hasLength(4), reason: id);
        expect(cue.options.toSet(), hasLength(4), reason: id);
        expect(
          dataset.knowledgeItemCitations.any(
            (row) =>
                row.knowledgeItemId == id &&
                row.sourceCitationId == cue.sourceCitationId &&
                row.locator?.isNotEmpty == true,
          ),
          isTrue,
          reason: id,
        );
        final source = sources[cue.sourceCitationId]!;
        expect(source.kind, 'reference_work');
        expect(Uri.parse(source.url!).host, 'www.wsetglobal.com');
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
      expect(answerPositions, {0: 1, 1: 1, 2: 1});
      expect(answerLengths, {0: 1, 1: 1, 2: 1});
      expect(
        items['ki_wset_l2_kabinett_must_weight']!.assertionText,
        contains('alone does not establish'),
      );
      expect(
        items['ki_wset_l2_closure_failure_sensory']!.assertionText,
        contains('observations alone do not prove'),
      );
      expect(
        items['ki_wset_l2_heat_damage_sensory']!.assertionText,
        contains('possible heat-damage effect'),
      );
    },
  );

  test('all nine corrections are useful L2 study; choices and recall grade evidence', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final clock = Clock.fixed(dataset.publishedAt);
    final generation = await CurriculumIngester(
      db,
      clock: clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(dataset);
    final cards = {
      for (final card in await StudyPlanner(db, clock: clock).cards('WSET_L2'))
        card.itemId: card,
    };
    const allIds = {...ruleIds, ...newIds};
    for (final id in allIds) {
      expect(cards[id], isNotNull, reason: id);
    }
    for (final id in newIds) {
      expect(
        cards[id]!.formats.map((row) => row.questionTemplateId),
        containsAll([choiceId, typedId]),
        reason: id,
      );
    }
    final presenter = ExercisePresenter(db, clock: clock);
    const choiceFormat = AuthoredChoiceFormat();
    const recallFormat = TypedFormat();
    const wrongRecall = {
      'ki_wset_l2_kabinett_must_weight': [
        'highest',
        'always sweet',
        'Kabinett',
      ],
      'ki_wset_l2_closure_failure_sensory': [
        'nitrogen',
        'tartrate',
        'a cork piece',
      ],
      'ki_wset_l2_heat_damage_sensory': [
        'more acidity',
        'new oak',
        'guaranteed improvement',
      ],
    };
    for (final id in newIds) {
      final question = await presenter.present(
        id,
        choiceId,
        seed: 23,
        certificationId: 'WSET_L2',
      ) as AuthoredChoiceQuestion;
      expect(question.sourceCitationId, choices[id]!.sourceCitationId);
      expect(
        question.answer.name,
        choices[id]!.options[choices[id]!.correctIndex],
      );
      expect(
        choiceFormat.grade(question, question.answer).single.rating,
        fsrs.Rating.good,
        reason: id,
      );
      for (final wrong in question.options.where(
        (option) => option != question.answer,
      )) {
        expect(
          choiceFormat.grade(question, wrong).single.rating,
          fsrs.Rating.again,
          reason: id,
        );
      }
      final typedQuestion = await presenter.present(
        id,
        typedId,
        seed: 23,
        certificationId: 'WSET_L2',
      ) as TypedQuestion;
      expect(typedQuestion.prompt, recall[id]!.prompt);
      for (final answer in recall[id]!.acceptedAnswers) {
        expect(
          recallFormat.grade(typedQuestion, answer).single.rating,
          fsrs.Rating.good,
          reason: '$id accepts $answer',
        );
      }
      for (final answer in wrongRecall[id]!) {
        expect(
          recallFormat.grade(typedQuestion, answer).single.rating,
          fsrs.Rating.again,
          reason: '$id rejects $answer',
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
          'WSET_L2',
          on: dataset.publishedAt.toIso8601String().substring(0, 10),
          skipped: generation.skipped,
        );
    final measured = report.items
        .where((row) => allIds.contains(row.id))
        .toList();
    expect(measured, hasLength(9));
    for (final row in measured) {
      expect(row.isCore, isTrue, reason: row.id);
      expect(row.hasUsefulPractice, isTrue, reason: row.id);
      expect(row.servedFormats, contains('flashcard'), reason: row.id);
      if (newIds.contains(row.id)) {
        expect(
          row.servedFormats,
          containsAll(['authored_choice', 'typed']),
          reason: row.id,
        );
      }
    }
    final lowerIds = (await StudyPlanner(db, clock: clock).cards('WSET_L1'))
        .map((card) => card.itemId)
        .toSet();
    expect(
      lowerIds.intersection(allIds),
      isEmpty,
      reason: 'Level 2 corrections do not enter Level 1',
    );
  });
}
