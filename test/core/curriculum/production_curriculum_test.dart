import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late CurriculumDataset dataset;
  final time = TestClock(DateTime.utc(2026, 10, 1, 9));
  const relations = {
    'PRINCIPLE_EXPLANATION',
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  bool originalItem(String id) =>
      const ['ki_vit_', 'ki_win_', 'ki_biz_', 'ki_srv_'].any(id.startsWith) &&
      !id.startsWith('ki_biz_models_') &&
      !id.startsWith('ki_biz_routes_');
  bool originalCase(String id) =>
      const ['qt_vit_', 'qt_win_', 'qt_biz_', 'qt_srv_'].any(id.startsWith) &&
      !id.startsWith('qt_biz_models_') &&
      !id.startsWith('qt_biz_routes_');
  bool productOrFaultItem(String id) =>
      const ['ki_spark_', 'ki_fort_', 'ki_fault_'].any(id.startsWith);
  bool regionalItem(String id) => const [
    'ki_reg_fr_',
    'ki_reg_am_',
    'ki_reg_sh_',
    'ki_reg_inc_',
    'ki_reg_isi_',
    'ki_reg_ib_',
    'ki_reg_fe_',
    'ki_reg_fm_',
    'ki_reg_fs_',
    'ki_reg_de_',
    'ki_reg_ah_',
    'ki_reg_gr_',
    'ki_reg_na_',
    'ki_reg_sa_',
    'ki_reg_oa_',
    'ki_reg_cn_',
    'ki_d3rt_case_',
  ].any(id.startsWith);

  setUpAll(() async {
    dataset = bundledDataset();
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(dataset);
  });
  tearDownAll(() => db.close());

  test(
    'production, business and service all have cited usable study content',
    () async {
      final items = dataset.knowledgeItems
          .where(
            (i) => relations.contains(i.relationType) && originalItem(i.id),
          )
          .toList();
      expect(items, hasLength(182));
      final counts = <String, int>{};
      for (final item in items) {
        counts.update(item.domainId, (n) => n + 1, ifAbsent: () => 1);
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue, reason: item.id);
        expect(
          dataset.knowledgeItemCitations.where(
            (c) => c.knowledgeItemId == item.id,
          ),
          isNotEmpty,
          reason: 'each mechanism or rubric point needs its own evidence',
        );
        expect(
          dataset.certificationKnowledgeMappings.where(
            (m) => m.knowledgeItemId == item.id,
          ),
          isNotEmpty,
        );
      }
      expect(counts, {
        'viticulture': 60,
        'winemaking': 66,
        'business': 38,
        'service': 18,
      });
      final questions = await db.select(db.questions).get();
      for (final item in items) {
        final modes = {
          for (final q in questions.where((q) => q.knowledgeItemId == item.id))
            dataset.questionTemplates
                .singleWhere((t) => t.id == q.questionTemplateId)
                .mode,
        };
        expect(modes, containsAll(['flashcard', 'typed']), reason: item.id);
        expect(
          modes,
          isNot(contains('mcq')),
          reason: 'conditional alternatives are not necessarily incorrect',
        );
      }
    },
  );

  test('every starter case is served only with its own four-point rubric after additions', () async {
    final templates = dataset.questionTemplates.where(
      (t) =>
          t.mode == 'short_answer' &&
          t.relationType == 'CASE_ACTION' &&
          originalCase(t.id),
    );
    expect(templates, hasLength(15));
    final pools = await db.select(db.exercisePools).get();
    final poolItems = await db.select(db.exercisePoolItems).get();
    for (final template in templates) {
      final scope = ShortAnswerFormat.scopeNodeIdsOf(template)!;
      expect(scope, hasLength(1));
      final matching = pools
          .where((p) => p.questionTemplateId == template.id)
          .toList();
      expect(matching, hasLength(1), reason: template.id);
      final pool = matching.single;
      expect(pool.scopeNodeId, scope.single);
      final ids = poolItems
          .where((i) => i.exercisePoolId == pool.id)
          .map((i) => i.knowledgeItemId)
          .toSet();
      final rubric = dataset.knowledgeItems
          .where((i) => ids.contains(i.id))
          .toList();
      expect(rubric, hasLength(4));
      expect(rubric.map((i) => i.subjectId).toSet(), scope);
      expect(
        rubric.map((i) => i.relationType).toSet(),
        relations.difference({'PRINCIPLE_EXPLANATION'}),
      );
    }
  });

  test('Diploma production and business progress includes new content without completing a level', () async {
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final snapshot = await WsetProgressRepository(
      db,
      scope: scope,
      clock: time.clock,
    ).snapshot();
    final diploma = snapshot.levels.singleWhere(
      (level) => level.scope.certificationId == 'WSET_L4',
    );
    expect(
      diploma.units.singleWhere((u) => u.scope.id == 'D1').counts.available,
      greaterThanOrEqualTo(126),
    );
    expect(
      diploma.units.singleWhere((u) => u.scope.id == 'D2').counts.available,
      133,
    );
    expect(diploma.appLevelComplete, isFalse);
    expect(
      snapshot.levels.every(
        (level) => !level.examPassed && !level.appLevelComplete,
      ),
      isTrue,
    );
    final lower = snapshot.levels.singleWhere(
      (level) => level.scope.certificationId == 'WSET_L2',
    );
    expect(
      lower.counts.available,
      greaterThan(7),
      reason: 'new foundations join lower-level progress',
    );
    final advanced = dataset.certificationKnowledgeMappings.where(
      (m) => m.certificationId == 'WSET_L4' && m.minimumDepth == 3,
    );
    expect(advanced.length, greaterThanOrEqualTo(54));
  });

  test('studied scenario marks its four canonical facts independently and retains the response', () async {
    final template = dataset.questionTemplates.firstWhere(
      (t) => t.id == 'qt_win_case_hot_red',
    );
    final scope = ShortAnswerFormat.scopeNodeIdsOf(template)!.single;
    final rubric = dataset.knowledgeItems
        .where((i) => i.subjectId == scope)
        .toList();
    final reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(1),
    );
    final templatesByRelation = {
      for (final t in dataset.questionTemplates.where(
        (t) => t.mode == 'flashcard' && relations.contains(t.relationType),
      ))
        t.relationType: t.id,
    };
    for (final point in rubric) {
      await reviews.record(
        knowledgeItemId: point.id,
        questionTemplateId: templatesByRelation[point.relationType]!,
        rating: fsrs.Rating.good,
      );
    }
    final presenter = ExercisePresenter(db, clock: time.clock);
    final action = rubric.singleWhere((i) => i.relationType == 'CASE_ACTION');
    final exercise = await presenter.present(
      action.id,
      template.id,
      seed: 4,
    ) as ShortAnswerExercise;
    expect(exercise.keyPoints, hasLength(4));
    expect(exercise.prompt, contains('Cooling capacity is limited'));
    expect(
      exercise.keyPoints.map((p) => p.statement).toSet(),
      rubric.map((i) => i.assertionText).toSet(),
    );
    final covered = exercise.keyPoints.take(2).map((p) => p.itemId).toSet();
    const text =
        'Monitor and cool the actively fermenting must; protect yeast activity.';
    final grades = const ShortAnswerFormat().grade(
      exercise,
      ShortAnswerResponse(text, covered),
    );
    expect(grades.where((g) => g.rating == fsrs.Rating.good), hasLength(2));
    expect(grades.where((g) => g.rating == fsrs.Rating.again), hasLength(2));
    await reviews.recordExercise(exercise, grades);
    final events = (await db.select(db.reviewEvents).get())
        .where((e) => e.questionTemplateId == template.id)
        .toList();
    expect(events, hasLength(4));
    expect(events.map((e) => e.exerciseId).toSet(), hasLength(1));
    expect(
      events.singleWhere((e) => e.knowledgeItemId == action.id).answerPayload,
      contains(text),
    );
    final typedTemplate = dataset.questionTemplates.singleWhere(
      (t) => t.mode == 'typed' && t.relationType == action.relationType,
    );
    final typed = await presenter.present(
      action.id,
      typedTemplate.id,
      seed: 1,
    ) as TypedQuestion;
    final alias = dataset.nodeAlternativeNames
        .firstWhere((n) => n.knowledgeNodeId == action.objectId)
        .name;
    expect(
      const TypedFormat().grade(typed, alias).single.rating,
      fsrs.Rating.good,
    );
    expect(
      const TypedFormat().grade(typed, '').single.rating,
      fsrs.Rating.again,
    );
  });

  test(
    'product, fault and regional terms are cited, mapped and answerable',
    () async {
      final presenter = ExercisePresenter(db, clock: time.clock);
      final templatesById = {
        for (final template in dataset.questionTemplates) template.id: template,
      };
      final typedTemplatesByItem = <String, List<String>>{};
      for (final question in await db.select(db.questions).get()) {
        final template = templatesById[question.questionTemplateId]!;
        if (template.mode == 'typed' && template.direction == 'forward') {
          typedTemplatesByItem
              .putIfAbsent(question.knowledgeItemId, () => [])
              .add(template.id);
        }
      }
      for (final prefix in [
        'ki_spark_',
        'ki_fort_',
        'ki_fault_',
        'ki_reg_fr_',
        'ki_reg_am_',
        'ki_reg_sh_',
        'ki_reg_inc_',
        'ki_reg_isi_',
        'ki_reg_ib_',
        'ki_reg_fe_',
        'ki_reg_fm_',
        'ki_reg_fs_',
        'ki_reg_de_',
        'ki_reg_ah_',
        'ki_reg_gr_',
        'ki_reg_na_',
        'ki_reg_sa_',
        'ki_reg_oa_',
        'ki_reg_cn_',
      ]) {
        final items = dataset.knowledgeItems.where(
          (i) => i.id.startsWith(prefix),
        );
        expect(
          items.length,
          {
            'ki_spark_': 58,
            'ki_fort_': 57,
            'ki_fault_': 58,
            'ki_reg_fr_': 44,
            'ki_reg_am_': 44,
            'ki_reg_sh_': 44,
            'ki_reg_inc_': 44,
            'ki_reg_isi_': 44,
            'ki_reg_ib_': 44,
            'ki_reg_fe_': 44,
            'ki_reg_fm_': 44,
            'ki_reg_fs_': 44,
            'ki_reg_de_': 44,
            'ki_reg_ah_': 44,
            'ki_reg_gr_': 44,
            'ki_reg_na_': 44,
            'ki_reg_sa_': 44,
            'ki_reg_oa_': 44,
            'ki_reg_cn_': 44,
          }[prefix],
          reason: prefix,
        );
        for (final item in items) {
          expect(item.verificationStatus, 'unverified');
          expect(item.mcqDisabled, isTrue);
          expect(
            dataset.knowledgeItemCitations.where(
              (c) => c.knowledgeItemId == item.id,
            ),
            isNotEmpty,
            reason: item.id,
          );
          expect(
            dataset.certificationKnowledgeMappings.where(
              (m) => m.knowledgeItemId == item.id,
            ),
            isNotEmpty,
          );
          final servedTemplates = typedTemplatesByItem[item.id] ?? [];
          expect(servedTemplates, hasLength(1), reason: item.id);
          final template = templatesById[servedTemplates.single]!;
          final exercise = await presenter.present(
            item.id,
            template.id,
            seed: 1,
          ) as TypedQuestion;
          final aliases = dataset.nodeAlternativeNames.where(
            (a) => a.knowledgeNodeId == item.objectId,
          );
          expect(aliases, isNotEmpty, reason: item.id);
          final cue = TypedFormat.itemCuesOf(template)?[item.id];
          final responsiveAnswers = cue?.acceptedAnswers
              .map(
                (answer) =>
                    TypedFormat.core(normalizeName(answer), exercise.typeWords),
              )
              .toSet();
          if (cue != null) {
            expect(exercise.prompt, cue.prompt, reason: item.id);
            expect(
              exercise.accepted.keys.toSet(),
              responsiveAnswers,
              reason: item.id,
            );
            for (final answer in cue.acceptedAnswers) {
              expect(
                const TypedFormat().grade(exercise, answer).single.rating,
                fsrs.Rating.good,
                reason: '${item.id}: authored response $answer',
              );
            }
            final canonical = dataset.knowledgeNodes
                .singleWhere((node) => node.id == item.objectId)
                .name;
            expect(exercise.canonicalAnswer, canonical, reason: item.id);
            expect(
              const TypedFormat().grade(exercise, canonical).single.rating,
              responsiveAnswers!.contains(
                    TypedFormat.core(
                      normalizeName(canonical),
                      exercise.typeWords,
                    ),
                  )
                  ? fsrs.Rating.good
                  : fsrs.Rating.again,
              reason: '${item.id}: canonical title must answer the actual cue',
            );
          }
          for (final alias in aliases) {
            expect(
              const TypedFormat().grade(exercise, alias.name).single.rating,
              cue == null ||
                      responsiveAnswers!.contains(
                        TypedFormat.core(alias.nameNorm, exercise.typeWords),
                      )
                  ? fsrs.Rating.good
                  : fsrs.Rating.again,
              reason: '${item.id}: ${alias.name}',
            );
          }
          expect(
            const TypedFormat().grade(exercise, '').single.rating,
            fsrs.Rating.again,
          );
        }
      }
    },
  );

  test('all product, fault and regional cases preserve conditions and independent rubric grades', () async {
    final templates = dataset.questionTemplates.where(
      (t) =>
          t.mode == 'short_answer' &&
          t.relationType == 'CASE_ACTION' &&
          const [
            'qt_spark_',
            'qt_fort_',
            'qt_fault_',
            'qt_reg_fr_',
            'qt_reg_am_',
            'qt_reg_sh_',
            'qt_reg_inc_',
            'qt_reg_isi_',
            'qt_reg_ib_',
            'qt_reg_fe_',
            'qt_reg_fm_',
            'qt_reg_fs_',
            'qt_reg_de_',
            'qt_reg_ah_',
            'qt_reg_gr_',
            'qt_reg_na_',
            'qt_reg_sa_',
            'qt_reg_oa_',
            'qt_reg_cn_',
          ].any(t.id.startsWith),
    );
    expect(templates, hasLength(79));
    final pools = await db.select(db.exercisePools).get();
    final poolItems = await db.select(db.exercisePoolItems).get();
    final presenter = ExercisePresenter(db, clock: time.clock);
    final reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(42),
    );
    for (final template in templates) {
      final subject = ShortAnswerFormat.scopeNodeIdsOf(template)!.single;
      if (template.id.startsWith('qt_reg_')) {
        expect(
          dataset.knowledgeNodes.singleWhere((n) => n.id == subject).name,
          contains(template.promptTemplate),
          reason: 'individual term/card practice must retain the case premises',
        );
      }
      final rubric = dataset.knowledgeItems
          .where((i) => i.subjectId == subject)
          .toList();
      expect(rubric, hasLength(4));
      expect(
        rubric.map((i) => i.relationType).toSet(),
        relations.difference({'PRINCIPLE_EXPLANATION'}),
      );
      final pool = pools.singleWhere(
        (p) => p.questionTemplateId == template.id,
      );
      expect(pool.scopeNodeId, subject);
      expect(
        poolItems
            .where((i) => i.exercisePoolId == pool.id)
            .map((i) => i.knowledgeItemId)
            .toSet(),
        rubric.map((i) => i.id).toSet(),
      );
      for (final point in rubric) {
        final card = dataset.questionTemplates.singleWhere(
          (t) => t.mode == 'flashcard' && t.relationType == point.relationType,
        );
        await reviews.record(
          knowledgeItemId: point.id,
          questionTemplateId: card.id,
          rating: fsrs.Rating.good,
        );
      }
      final action = rubric.singleWhere((i) => i.relationType == 'CASE_ACTION');
      final exercise = await presenter.present(
        action.id,
        template.id,
        seed: 4,
      ) as ShortAnswerExercise;
      expect(exercise.prompt, template.promptTemplate);
      expect(
        exercise.keyPoints.map((p) => p.itemId).toSet(),
        rubric.map((i) => i.id).toSet(),
      );
      const response =
          'A conditional practice explanation retained in learner history.';
      final grades = const ShortAnswerFormat().grade(
        exercise,
        ShortAnswerResponse(
          response,
          exercise.keyPoints.take(2).map((p) => p.itemId).toSet(),
        ),
      );
      await reviews.recordExercise(exercise, grades);
      final events = (await db.select(db.reviewEvents).get())
          .where((e) => e.questionTemplateId == template.id)
          .toList();
      expect(events, hasLength(4));
      expect(events.map((e) => e.exerciseId).toSet(), hasLength(1));
      expect(events.where((e) => e.rating == 3), hasLength(2));
      expect(
        jsonDecode(
          events
              .singleWhere((e) => e.knowledgeItemId == action.id)
              .answerPayload!,
        )['text'],
        response,
      );
      for (final event in events) {
        expect(jsonDecode(event.answerPayload!)['covered'], event.rating == 3);
      }
    }
  });

  test('D4 and D5 receive product lessons without inflating D1/D2 or claiming unit completion', () async {
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final snapshot = await WsetProgressRepository(
      db,
      scope: scope,
      clock: time.clock,
    ).snapshot();
    expect(snapshot.levels.map((level) => level.counts.mapped), [
      132,
      829,
      3439,
      4127,
    ]);
    final diploma = snapshot.levels.last;
    final unitIds = {
      for (final unit in scope.levels.last.units) unit.id: unit.itemIds.toSet(),
    };
    for (final entry in {
      'D4': [
        'ki_spark_',
        'ki_d4nw_',
        'ki_d4depth_',
        'ki_d4d5_bourgogne_',
        'ki_d4d5_saumur_',
        'ki_d4d5_trento_',
        'ki_d4d5_sorbara_',
        'ki_d4d5_grasparossa_',
        'ki_d4d5_case_italian_',
        'ki_d45taste_sparkling_',
      ],
      'D5': [
        'ki_fort_',
        'ki_d5f_',
        'ki_d4d5_palo_',
        'ki_d4d5_lbv_',
        'ki_d4d5_colheita_',
        'ki_d4d5_white_port_',
        'ki_d4d5_case_port_',
        'ki_d45taste_sherry_',
        'ki_d45taste_port_',
      ],
    }.entries) {
      final ids = dataset.knowledgeItems
          .where((i) => entry.value.any(i.id.startsWith))
          .map((i) => i.id)
          .toSet();
      expect(unitIds[entry.key], ids);
      final unit = diploma.units.singleWhere((u) => u.scope.id == entry.key);
      expect(unit.counts.available, greaterThan(ids.length));
      expect(unit.scope.gap, isNotEmpty);
    }
    expect(
      diploma.units.singleWhere((u) => u.scope.id == 'D2').counts.available,
      133,
    );
    expect(
      diploma.units.singleWhere((u) => u.scope.id == 'D3').scope.domains,
      contains('tasting'),
    );
    expect(
      diploma.units.fold(0, (int n, u) => n + u.counts.mapped) +
          diploma.unassigned.mapped,
      diploma.counts.mapped,
    );
    expect(
      dataset.knowledgeItems.where(
        (i) => productOrFaultItem(i.id) && i.domainId == 'tasting',
      ),
      isNotEmpty,
    );
    expect(diploma.appLevelComplete, isFalse);
    expect(diploma.examPassed, isFalse);
  });

  test(
    'regional comparison pools keep both cited points within one comparison',
    () async {
      final items = dataset.knowledgeItems
          .where(
            (i) =>
                regionalItem(i.id) && i.relationType == 'PRINCIPLE_EXPLANATION',
          )
          .toList();
      expect(items, hasLength(448));
      final bySubject = <String, List<KnowledgeItem>>{};
      for (final item in items) {
        bySubject.putIfAbsent(item.subjectId, () => []).add(item);
      }
      expect(bySubject, hasLength(224));
      final template = dataset.questionTemplates.singleWhere(
        (t) => t.id == 'qt_principle_explanation_short_answer',
      );
      final pools = await db.select(db.exercisePools).get();
      final poolItems = await db.select(db.exercisePoolItems).get();
      final presenter = ExercisePresenter(db, clock: time.clock);
      final reviews = ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
        random: Random(84),
      );
      final card = dataset.questionTemplates.singleWhere(
        (t) =>
            t.mode == 'flashcard' && t.relationType == 'PRINCIPLE_EXPLANATION',
      );
      for (final entry in bySubject.entries) {
        final points = entry.value;
        expect(points, hasLength(2), reason: entry.key);
        final pool = pools.singleWhere(
          (p) =>
              p.questionTemplateId == template.id && p.scopeNodeId == entry.key,
        );
        expect(
          poolItems
              .where((p) => p.exercisePoolId == pool.id)
              .map((p) => p.knowledgeItemId)
              .toSet(),
          points.map((p) => p.id).toSet(),
        );
        for (final point in points) {
          await reviews.record(
            knowledgeItemId: point.id,
            questionTemplateId: card.id,
            rating: fsrs.Rating.good,
          );
        }
        final exercise = await presenter.present(
          points.first.id,
          template.id,
          seed: 4,
        ) as ShortAnswerExercise;
        expect(
          exercise.keyPoints.map((p) => p.itemId).toSet(),
          points.map((p) => p.id).toSet(),
        );
        expect(
          exercise.keyPoints.map((p) => p.statement).toSet(),
          points.map((p) => p.assertionText).toSet(),
        );
        final subject = dataset.knowledgeNodes.singleWhere(
          (n) => n.id == entry.key,
        );
        expect(exercise.prompt, contains(subject.name));
        final grades = const ShortAnswerFormat().grade(
          exercise,
          ShortAnswerResponse('One supported comparison point.', {
            points.first.id,
          }),
        );
        expect(
          grades.singleWhere((g) => g.itemId == points.first.id).rating,
          fsrs.Rating.good,
        );
        expect(
          grades.singleWhere((g) => g.itemId == points.last.id).rating,
          fsrs.Rating.again,
        );
      }
    },
  );

  test('all regional analysis facts route to D3 across domains without completing a level', () async {
    final ids = dataset.knowledgeItems
        .where((i) => regionalItem(i.id))
        .map((i) => i.id)
        .toSet();
    expect(ids, hasLength(720));
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    expect(
      scope.levels.last.units.singleWhere((u) => u.id == 'D3').itemIds.toSet(),
      ids,
    );
    for (final unit in scope.levels.last.units.where((u) => u.id != 'D3')) {
      expect(unit.itemIds.toSet().intersection(ids), isEmpty, reason: unit.id);
    }
    final snapshot = await WsetProgressRepository(
      db,
      scope: scope,
      clock: time.clock,
    ).snapshot();
    final diploma = snapshot.levels.last;
    final d3 = diploma.units.singleWhere((u) => u.scope.id == 'D3');
    expect(d3.counts.available, greaterThan(ids.length));
    expect(d3.scope.gap, isNotEmpty);
    expect(
      diploma.units.fold(0, (int n, u) => n + u.counts.available) +
          diploma.unassigned.available,
      diploma.counts.available,
    );
    expect(
      snapshot.levels.every((l) => !l.appLevelComplete && !l.examPassed),
      isTrue,
    );
    for (final item in dataset.knowledgeItems.where(
      (i) => ids.contains(i.id),
    )) {
      final mappings = dataset.certificationKnowledgeMappings.where(
        (m) => m.knowledgeItemId == item.id,
      );
      expect(
        mappings
            .singleWhere((m) => m.certificationId == 'WSET_L4')
            .minimumDepth,
        3,
      );
      if (item.id.startsWith('ki_reg_cn_')) {
        expect(mappings.map((m) => m.certificationId), ['WSET_L4']);
      } else if (item.relationType != 'PRINCIPLE_EXPLANATION') {
        // Selected original case points now teach the required L3 decisions.
        // Every promotion must be declared in the independently reviewed
        // authoring evidence, while its Diploma depth remains unchanged.
        final europe = jsonDecode(
          File('docs/research/wset-regional-europe-evidence.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final production = jsonDecode(
          File('docs/research/wset-general-production-evidence.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final allowed = <String>{
          for (final row in europe['mapping_additions'] as List)
            '${row['certification_id']}|${row['knowledge_item_id']}',
          for (final id in production['case_point_ids'] as List) 'WSET_L3|$id',
        };
        for (final mapping in mappings.where(
          (m) => m.certificationId != 'WSET_L4',
        )) {
          expect(
            allowed,
            contains('${mapping.certificationId}|${item.id}'),
            reason: item.id,
          );
          expect(mapping.minimumDepth, lessThanOrEqualTo(2));
        }
      } else if (const [
        'ki_reg_inc_',
        'ki_reg_isi_',
        'ki_reg_ib_',
        'ki_reg_fe_',
        'ki_reg_fm_',
        'ki_reg_fs_',
        'ki_reg_de_',
        'ki_reg_ah_',
        'ki_reg_gr_',
        'ki_reg_na_',
        'ki_reg_sa_',
        'ki_reg_oa_',
      ].any(item.id.startsWith)) {
        expect(
          mappings.map((m) => m.certificationId).toSet(),
          containsAll({'WSET_L4', 'WSET_L3', 'CMS_CERTIFIED'}),
          reason: 'regional foundations remain available on lower tracks',
        );
        expect(
          mappings
              .where((m) => m.certificationId != 'WSET_L4')
              .every((m) => m.minimumDepth <= 2),
          isTrue,
        );
      }
    }
  });
}
