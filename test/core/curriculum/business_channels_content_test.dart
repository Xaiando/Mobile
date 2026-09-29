import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/reasoning_paths.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

bool _businessItem(String id) =>
    id.startsWith('ki_biz_models_') || id.startsWith('ki_biz_routes_');

bool _businessTemplate(String id) =>
    id.startsWith('qt_biz_models_') || id.startsWith('qt_biz_routes_');

void main() {
  final dataset = bundledDataset();
  final business = dataset.knowledgeItems
      .where((item) => _businessItem(item.id))
      .toList();
  final businessIds = business.map((item) => item.id).toSet();
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  const caseRoles = [
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  ];
  const principleSuffixes = {
    'models': [
      'integration',
      'vineyard_commitment',
      'custom_capacity',
      'custom_scope',
      'cooperative_pool',
      'cooperative_control',
      'grape_purchase',
      'bulk_purchase',
    ],
    'routes': [
      'dtc_resources',
      'dtc_records',
      'downstream_sales',
      'service_scope',
      'retail_access',
      'ontrade_fit',
      'partner_fit',
      'reviewable_roles',
    ],
  };
  const caseSubjects = {
    'qt_biz_models_contract_pilot_case': 'n_biz_models_case_contract_pilot',
    'qt_biz_models_cooperative_pool_case': 'n_biz_models_case_cooperative_pool',
    'qt_biz_routes_dtc_capacity_case': 'n_biz_routes_case_dtc_capacity',
    'qt_biz_routes_downstream_review_case':
        'n_biz_routes_case_downstream_review',
  };
  const caseControls = {
    'qt_biz_models_contract_pilot_case': [
      'not an equipped new winery',
      'separate lot tracking',
      'approval roles, delivery window and service charges',
      'repeat demand is unknown',
      'No actual prices, legal label claim or guaranteed sales are supplied',
    ],
    'qt_biz_models_cooperative_pool_case': [
      "over exclusive control of each grower's wine brand",
      'member capital contributions',
      'any net pool proceeds after expenses',
      'No sales or returns are guaranteed',
      'not rules for every cooperative',
    ],
    'qt_biz_routes_dtc_capacity_case': [
      'customer support still its responsibility',
      'without sharing individual customer contacts',
      'no demand, margin or net-profit estimate is supplied',
      'More than one approach may be justified',
    ],
    'qt_biz_routes_downstream_review_case': [
      'no outlet reorders or consumer-sales reports',
      'limited promotional budget',
      'no sales guarantee, exclusivity rule or current law is specified',
      'More than one approach may be justified',
    ],
  };
  final cases = dataset.questionTemplates
      .where(
        (template) =>
            template.mode == 'short_answer' && _businessTemplate(template.id),
      )
      .toList();

  test(
    'new business facts have unique cited recall points and Diploma-only depth',
    () {
      expect(business, hasLength(32));
      expect(businessIds, {
        for (final module in principleSuffixes.entries)
          for (final suffix in module.value) 'ki_biz_${module.key}_$suffix',
        for (final subject in caseSubjects.values)
          for (final role in caseRoles)
            'ki_${subject.substring(2)}_${role.substring(5).toLowerCase()}',
      });
      for (final prefix in ['ki_biz_models_', 'ki_biz_routes_']) {
        final module = business
            .where((item) => item.id.startsWith(prefix))
            .toList();
        expect(module, hasLength(16), reason: prefix);
        expect(
          module.where((item) => item.relationType == 'PRINCIPLE_EXPLANATION'),
          hasLength(8),
        );
        expect(
          module.where((item) => caseRoles.contains(item.relationType)),
          hasLength(8),
        );
      }
      for (final item in business) {
        expect(item.domainId, 'business');
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue);
        expect(item.lastVerifiedAt.isUtc, isTrue);
        expect(item.supersededByItemId, isNull);
        expect(item.assertionText.trim(), isNotEmpty);
        final principle = item.relationType == 'PRINCIPLE_EXPLANATION';
        expect(
          nodes[item.subjectId]!.nodeType,
          principle ? 'production_principle' : 'production_case',
        );
        expect(nodes[item.objectId]!.nodeType, 'learning_point');
        final mappings = dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .toList();
        expect(mappings, hasLength(1), reason: item.id);
        expect(mappings.single.certificationId, 'WSET_L4');
        expect(mappings.single.importance, 'core');
        expect(mappings.single.minimumDepth, principle ? 2 : 3);
        expect(
          dataset.knowledgeRelations.where(
            (relation) =>
                relation.subjectId == item.subjectId &&
                relation.relationType == item.relationType &&
                relation.objectId == item.objectId &&
                relation.validFrom.compareTo('2026-10-01') <= 0 &&
                (relation.validUntil == null ||
                    relation.validUntil!.compareTo('2026-10-01') > 0),
          ),
          hasLength(1),
          reason: item.id,
        );
        final aliases = dataset.nodeAlternativeNames
            .where((alias) => alias.knowledgeNodeId == item.objectId)
            .toList();
        expect(aliases, isNotEmpty, reason: item.id);
        expect(
          aliases.map((alias) => alias.nameNorm).toSet(),
          hasLength(aliases.length),
        );
        for (final alias in aliases) {
          expect(alias.nameNorm, isNot(nodes[item.objectId]!.nameNorm));
        }
        final citations = dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == item.id)
            .toList();
        expect(citations, isNotEmpty, reason: item.id);
        for (final citation in citations) {
          expect(citation.locator?.trim(), isNotEmpty, reason: item.id);
          final source = sources[citation.sourceCitationId]!;
          expect(source.url, startsWith('https://'));
          expect(
            dataset.sourceCitations.where((other) => other.url == source.url),
            hasLength(1),
          );
        }
      }
      final raw = rowsOf(
        flattenDataset(curriculumAssetPath),
        'knowledge_items',
      ).cast<Map<String, dynamic>>();
      for (final item in raw.where((row) => businessIds.contains(row['id']))) {
        expect(item['last_verified_at'], isA<String>());
        expect(
          item['last_verified_at'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
        );
      }
    },
  );

  test('four original cases retain complete premises and disjoint four-role rubrics', () {
    expect(cases, hasLength(4));
    expect(
      cases.map((template) => template.id).toSet(),
      caseSubjects.keys.toSet(),
    );
    expect(caseControls.keys.toSet(), caseSubjects.keys.toSet());
    final subjects = <String>{};
    final rubricIds = <String>{};
    for (final prefix in ['qt_biz_models_', 'qt_biz_routes_']) {
      expect(
        cases.where((template) => template.id.startsWith(prefix)),
        hasLength(2),
      );
    }
    for (final template in cases) {
      expect(template.relationType, 'CASE_ACTION');
      expect(template.direction, 'forward');
      final scope = ShortAnswerFormat.scopeNodeIdsOf(template)!;
      expect(scope, hasLength(1));
      expect(scope.single, caseSubjects[template.id]);
      expect(
        subjects.add(scope.single),
        isTrue,
        reason: 'each prompt owns a distinct case',
      );
      expect(nodes[scope.single]!.nodeType, 'production_case');
      expect(template.promptTemplate, nodes[scope.single]!.name);
      expect(template.promptTemplate.toLowerCase(), contains('hypothetical'));
      expect(template.promptTemplate, isNot(matches(RegExp(r'[{}]'))));
      for (final control in caseControls[template.id]!) {
        expect(
          template.promptTemplate,
          contains(control),
          reason: '${template.id}: $control',
        );
      }
      expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toList(), caseRoles);
      final rubric = business
          .where((item) => item.subjectId == scope.single)
          .toList();
      expect(rubric, hasLength(4));
      expect(
        rubric.map((item) => item.relationType).toSet(),
        caseRoles.toSet(),
      );
      for (final item in rubric) {
        expect(
          rubricIds.add(item.id),
          isTrue,
          reason: 'case points cannot cross prompts',
        );
      }
    }
    expect(
      rubricIds,
      business
          .where((item) => caseRoles.contains(item.relationType))
          .map((item) => item.id)
          .toSet(),
    );
  });

  group('integrated business channels', () {
    late AppDatabase db;
    late TestClock time;
    late ExercisePresenter presenter;
    late StudyPlanner planner;
    final recallTemplates = <String, Map<String, String>>{};

    setUpAll(() async {
      // One real-bundle ingestion and one generated recall review per new fact.
      // These fixtures deliberately require both new areas in the manifest.
      expect(businessIds, hasLength(32));
      time = TestClock(DateTime.utc(2026, 10, 1, 9));
      db = openTestDatabase();
      await CurriculumIngester(
        db,
        clock: time.clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      presenter = ExercisePresenter(db, clock: time.clock);
      planner = StudyPlanner(db, clock: time.clock);
      final questions = await db.customSelect('''
        SELECT q.knowledge_item_id, q.question_template_id, t.mode
        FROM questions q JOIN question_templates t ON t.id = q.question_template_id
        ORDER BY q.question_template_id''').get();
      for (final question in questions) {
        final id = question.read<String>('knowledge_item_id');
        if (!businessIds.contains(id)) continue;
        recallTemplates
            .putIfAbsent(id, () => {})
            .putIfAbsent(
              question.read<String>('mode'),
              () => question.read<String>('question_template_id'),
            );
      }
      final reviews = ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
      );
      for (final item in business) {
        await reviews.record(
          knowledgeItemId: item.id,
          questionTemplateId: recallTemplates[item.id]!['flashcard']!,
          rating: fsrs.Rating.good,
        );
      }
    });
    tearDownAll(() => db.close());

    test(
      'generated recall and case pools do not expand the ten causal paths',
      () async {
        for (final id in businessIds) {
          expect(recallTemplates[id]!.keys.toSet(), {
            'flashcard',
            'typed',
          }, reason: id);
        }
        final pools = await db.select(db.exercisePools).get();
        final members = await db.select(db.exercisePoolItems).get();
        final businessPools = pools
            .where((pool) => _businessTemplate(pool.questionTemplateId))
            .toList();
        expect(businessPools, hasLength(4));
        final pooledIds = <String>{};
        for (final template in cases) {
          final pool = businessPools.singleWhere(
            (pool) => pool.questionTemplateId == template.id,
          );
          final subject = ShortAnswerFormat.scopeNodeIdsOf(template)!.single;
          expect(pool.scopeNodeId, subject);
          expect(pool.promptText, nodes[subject]!.name);
          final ids = members
              .where((member) => member.exercisePoolId == pool.id)
              .map((member) => member.knowledgeItemId)
              .toSet();
          expect(
            ids,
            business
                .where((item) => item.subjectId == subject)
                .map((item) => item.id)
                .toSet(),
          );
          expect(ids, hasLength(4));
          expect(pooledIds.intersection(ids), isEmpty);
          pooledIds.addAll(ids);
        }
        expect(pooledIds, hasLength(16));
        const preservedTargets = {
          'ki_reason_water_assimilation',
          'ki_reason_bloom_berries',
          'ki_reason_mlf_acidity',
          'ki_reason_so2_protection',
          'ki_climate_frost_wind_warming',
          'ki_climate_frost_sprinkler_temperature',
          'ki_climate_ripen_malate_remaining',
          'ki_climate_ripen_botrytis_risk',
          'ki_wset_reason_frost_clusters',
          'ki_wset_reason_ferment_ethanol',
        };
        final reasoning = dataset.questionTemplates
            .where((template) => template.mode == 'reasoning')
            .toList();
        expect(reasoning, hasLength(10));
        final targets = <String>{};
        for (final template in reasoning) {
          final result = ReasoningPaths.inspectDataset(
            dataset,
            template,
            on: '2026-10-01',
          );
          expect(result.diagnostics, isEmpty, reason: template.id);
          final path = result.paths.single;
          targets.add(path.target.id);
          expect(path.itemIds.toSet().intersection(businessIds), isEmpty);
          final pool = pools.singleWhere(
            (pool) => pool.questionTemplateId == template.id,
          );
          final ordered = members
              .where((member) => member.exercisePoolId == pool.id)
              .toList();
          expect(ordered.map((member) => member.rank), everyElement(isNotNull));
          ordered.sort((a, b) => a.rank!.compareTo(b.rank!));
          expect(
            ordered.map((member) => member.knowledgeItemId).toList(),
            path.itemIds,
          );
        }
        expect(targets, preservedTargets);
      },
    );

    test('authored aliases answer typed recall and cases grade only selected points', () async {
      expect(
        const ShortAnswerFormat().isObjective,
        isFalse,
        reason: 'written points are learner-checked, not essay marking',
      );
      for (final item in business) {
        final typed = await presenter.present(
          item.id,
          recallTemplates[item.id]!['typed']!,
          seed: 19,
        ) as TypedQuestion;
        for (final alias in dataset.nodeAlternativeNames.where(
          (alias) => alias.knowledgeNodeId == item.objectId,
        )) {
          final grade = presenter.grade(typed, alias.name).single;
          expect(grade.itemId, item.id);
          expect(
            grade.rating,
            fsrs.Rating.good,
            reason: '${item.id}: ${alias.name}',
          );
        }
        expect(presenter.grade(typed, '').single.rating, fsrs.Rating.again);
      }
      for (final template in cases) {
        final subject = ShortAnswerFormat.scopeNodeIdsOf(template)!.single;
        final rubric = business
            .where((item) => item.subjectId == subject)
            .toList();
        final action = rubric.singleWhere(
          (item) => item.relationType == 'CASE_ACTION',
        );
        final reason = rubric.singleWhere(
          (item) => item.relationType == 'CASE_REASON',
        );
        final exercise = await presenter.present(
          action.id,
          template.id,
          seed: 23,
        ) as ShortAnswerExercise;
        expect(exercise.prompt, nodes[subject]!.name);
        expect(exercise.itemIds.toSet(), rubric.map((item) => item.id).toSet());
        expect(
          exercise.keyPoints.map((point) => point.statement).toSet(),
          rubric.map((item) => item.assertionText).toSet(),
        );
        final covered = {action.id, reason.id};
        const text =
            'My response covers the decision and its mechanism; I did not cover the other points.';
        final grades = presenter.grade(
          exercise,
          ShortAnswerResponse(text, covered),
        );
        expect(
          grades.map((grade) => grade.itemId).toSet(),
          exercise.itemIds.toSet(),
        );
        expect(grades, hasLength(4));
        for (final grade in grades) {
          expect(
            grade.rating,
            covered.contains(grade.itemId)
                ? fsrs.Rating.good
                : fsrs.Rating.again,
          );
          final payload = grade.payload! as Map<String, Object?>;
          expect(payload['covered'], covered.contains(grade.itemId));
          expect(payload.containsKey('text'), grade.itemId == action.id);
        }
        expect(
          grades.singleWhere((grade) => grade.itemId == action.id).payload,
          {'text': text, 'covered': true},
        );
        final outside = businessIds.difference(exercise.itemIds.toSet()).first;
        expect(
          () => presenter.grade(exercise, ShortAnswerResponse(text, {outside})),
          throwsArgumentError,
        );
      }
    });

    test('32 actual recalls affect only D2 and preserve lower tracks and incomplete levels', () async {
      for (final entry in {
        'WSET_L1': 132,
        'WSET_L2': 829,
        'WSET_L3': 3439,
        'CMS_CERTIFIED': 2878,
        'WSET_L4': 3921,
      }.entries) {
        final mappings = await planner.effectiveMappings(entry.key);
        expect(mappings, hasLength(entry.value), reason: entry.key);
        expect(
          mappings.keys.toSet().intersection(businessIds),
          entry.key == 'WSET_L4' ? businessIds : isEmpty,
        );
      }
      final events = await db.select(db.reviewEvents).get();
      expect(events, hasLength(32));
      expect(events.map((event) => event.knowledgeItemId).toSet(), businessIds);
      final scope = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      final snapshot = await WsetProgressRepository(
        db,
        scope: scope,
        planner: planner,
        clock: time.clock,
      ).snapshot();
      final diploma = snapshot.levels.singleWhere(
        (level) => level.scope.certificationId == 'WSET_L4',
      );
      expect(diploma.counts.studied, 32);
      expect(diploma.counts.mastered, 0);
      expect(diploma.scope.curriculumComplete, isFalse);
      final d2 = diploma.units.singleWhere((unit) => unit.scope.id == 'D2');
      expect(d2.counts.studied, 32);
      expect(d2.counts.available, 116);
      expect(d2.scope.gap, isNotEmpty);
      for (final unit in diploma.units.where((unit) => unit.scope.id != 'D2')) {
        expect(unit.counts.studied, 0, reason: unit.scope.id);
        expect(unit.scope.itemIds.toSet().intersection(businessIds), isEmpty);
      }
      expect(diploma.unassigned.studied, 0);
      expect(
        diploma.units
            .singleWhere((unit) => unit.scope.id == 'D3')
            .scope
            .itemIds,
        hasLength(704),
      );
      expect(snapshot.levels.map((level) => level.counts.mapped).toList(), [
        132,
        829,
        3439,
        3921,
      ]);
      expect(
        snapshot.levels.take(3).map((level) => level.counts.studied),
        everyElement(0),
      );
      expect(
        snapshot.levels.every(
          (level) => !level.appLevelComplete && !level.examPassed,
        ),
        isTrue,
      );
    });
  });
}
