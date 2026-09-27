import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/formats/reasoning/reasoning_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';

import '../../support/fixture.dart';
import '../../support/curriculum_fixture.dart';
import '../../support/reasoning_fixture.dart';

void main() {
  late AppDatabase db;
  const format = ReasoningFormat();
  final now = DateTime.utc(2026, 1, 2);
  setUp(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: Clock.fixed(now),
    ).ingest(reasoningDataset());
  });
  tearDown(() => db.close());
  Future<ReasoningExercise> present({
    String item = reasoningThreeTargetId,
    String template = reasoningThreeTemplateId,
    int seed = 19,
  }) async => await format.present(
    PresentationContext(db, now: now),
    itemId: item,
    questionTemplateId: template,
    seed: seed,
  ) as ReasoningExercise;

  test('format metadata requires mature objective depth-four reasoning', () {
    expect(format.family, FormatFamily.reasoning);
    expect(format.generation, FormatGeneration.pooled);
    expect(format.isObjective, isTrue);
    expect(format.requiredDepth('forward'), 4);
    expect(format.difficultyRank('forward'), 6);
    expect(format.preferredBands('forward'), {MemoryBand.mature});
  });

  test(
    'pool keeps the complete ordered chain with only its last item primary',
    () async {
      final pools =
          await (db.select(db.exercisePools)..where(
                (p) => p.questionTemplateId.equals(reasoningThreeTemplateId),
              ))
              .get();
      expect(pools, hasLength(1));
      expect(pools.single.scopeNodeId, 'n_reason_three_0');
      expect(
        pools.single.promptText,
        'Given three supplied starting conditions, which conclusion follows?',
      );
      final members =
          await (db.select(db.exercisePoolItems)
                ..where((i) => i.exercisePoolId.equals(pools.single.id))
                ..orderBy([(i) => OrderingTerm(expression: i.rank)]))
              .get();
      expect(members.map((i) => i.knowledgeItemId), reasoningThreeChain);
      expect(members.map((i) => i.rank), [1, 2, 3]);
      final targets = await db.customSelect('''
      SELECT i.knowledge_item_id AS item FROM exercise_pool_items i
      JOIN exercise_pools p ON p.id=i.exercise_pool_id
      JOIN question_templates t ON t.id=p.question_template_id
      WHERE t.mode='reasoning' AND ${ReasoningFormat.scheduledPoolMemberSql()}
      ORDER BY i.knowledge_item_id
    ''').get();
      expect(
        targets.map((r) => r.read<String>('item')),
        unorderedEquals([reasoningTwoTargetId, reasoningThreeTargetId]),
      );
      expect(
        () =>
            ReasoningFormat.scheduledPoolMemberSql(memberAlias: 'unsafe;drop'),
        throwsArgumentError,
      );
    },
  );

  test(
    'support-only requests and unstudied support are independently rejected',
    () async {
      await expectLater(
        present(item: reasoningThreeChain.first),
        throwsArgumentError,
      );
      await expectLater(present(), throwsStateError);
      await studyReasoningSupports(db, itemIds: [reasoningThreeChain.first]);
      await expectLater(present(), throwsStateError);
      await studyReasoningSupports(db);
      expect((await present()).chain, reasoningThreeChain);
    },
  );

  test(
    'seeded replay retains the full chain and four distinct options',
    () async {
      await studyReasoningSupports(db);
      final first = await present(), again = await present();
      expect(first.chain, reasoningThreeChain);
      expect(first.itemIds, [
        reasoningThreeTargetId,
        reasoningThreeChain[0],
        reasoningThreeChain[1],
      ]);
      expect(first.premiseNodeId, 'n_reason_three_0');
      expect(first.prompt, contains('three supplied starting conditions'));
      expect(first.prompt, isNot(contains('three consequence 2')));
      expect(first.options, again.options);
      expect(first.options, hasLength(4));
      expect(first.options.toSet(), hasLength(4));
      expect(first.options.where((o) => o == first.answer), hasLength(1));
      final orders = <String>{};
      for (var seed = 0; seed < 10; seed++) {
        orders.add(
          (await present(seed: seed)).options.map((o) => o.nodeId).join('/'),
        );
      }
      expect(orders.length, greaterThan(1));
    },
  );

  test(
    'two-edge and three-edge presentations are never shortened or supplemented',
    () async {
      await studyReasoningSupports(db);
      final two = await present(
        item: reasoningTwoTargetId,
        template: reasoningTwoTemplateId,
      );
      final three = await present();
      expect(two.chain, reasoningTwoChain);
      expect(three.chain, reasoningThreeChain);
      expect(two.itemIds.toSet(), reasoningTwoChain.toSet());
      expect(three.itemIds.toSet(), reasoningThreeChain.toSet());
    },
  );

  test(
    'feedback has cited ordered chain and unassessed contradiction evidence',
    () async {
      await studyReasoningSupports(db);
      final exercise = await present();
      expect(exercise.chainEvidence.map((e) => e.itemId), reasoningThreeChain);
      expect(exercise.contrasts, hasLength(3));
      for (final evidence in [
        ...exercise.chainEvidence,
        for (final c in exercise.contrasts) ...c.evidence,
      ]) {
        expect(evidence.statement, isNotEmpty);
        expect(evidence.sources.single.title, 'Synthetic mechanism source');
        expect(evidence.sources.single.publisher, 'Fixture publisher');
        expect(
          evidence.sources.single.url,
          'https://example.invalid/reasoning-fixture',
        );
        expect(evidence.sources.single.locator, contains(evidence.itemId));
      }
      final explanationIds = exercise.contrasts
          .expand((c) => c.evidence)
          .map((e) => e.itemId)
          .toSet();
      expect(explanationIds.intersection(exercise.itemIds.toSet()), isEmpty);
      final credited = format.grade(exercise, exercise.answer);
      expect(
        credited.map((g) => g.itemId).toSet().intersection(explanationIds),
        isEmpty,
      );
    },
  );

  test(
    'right credits each chain item once; wrong blames only the target',
    () async {
      await studyReasoningSupports(db);
      final exercise = await present();
      final right = format.grade(exercise, exercise.answer);
      expect(right.map((g) => g.itemId), exercise.itemIds);
      expect(right.every((g) => g.rating == fsrs.Rating.good), isTrue);
      final wrongOption = exercise.options.firstWhere(
        (o) => o != exercise.answer,
      );
      final wrong = format.grade(exercise, wrongOption);
      expect(wrong.single.itemId, reasoningThreeTargetId);
      expect(wrong.single.rating, fsrs.Rating.again);
      for (final grade in [...right, ...wrong]) {
        expect(grade.optionNodeIds, exercise.options.map((o) => o.nodeId));
        expect(grade.payload, isA<Map<String, Object>>());
        final payload =
            jsonDecode(jsonEncode(grade.payload)) as Map<String, dynamic>;
        expect(payload['seed'], 19);
        expect(payload['chain'], reasoningThreeChain);
        expect(payload['premise_node_id'], 'n_reason_three_0');
        expect(payload['shown_options'], grade.optionNodeIds);
        expect(payload['selected_node_id'], grade.selectedNodeId);
      }
      expect(() => format.grade(exercise, 'text'), throwsArgumentError);
      expect(
        () => format.grade(
          exercise,
          const QuestionOption('n_unshown', 'Unshown'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'presentation rejects a corrupted shortened pool rather than sampling',
    () async {
      await studyReasoningSupports(db);
      await db.writeCurriculum(() async {
        await (db.delete(
          db.exercisePoolItems,
        )..where((i) => i.knowledgeItemId.equals(reasoningThreeChain[1]))).go();
      });
      await expectLater(present(), throwsStateError);
    },
  );

  test('presentation rechecks current citation and retirement state after generation', () async {
    await studyReasoningSupports(db);
    await db.writeCurriculum(() async {
      await (db.delete(db.knowledgeItemCitations)..where(
            (c) => c.knowledgeItemId.equals('ki_reason_three_contrast_1'),
          ))
          .go();
    });
    await expectLater(present(), throwsStateError);
  });

  test('grade rejects an externally constructed duplicate chain', () async {
    await studyReasoningSupports(db);
    final e = await present();
    final invalid = ReasoningExercise(
      primaryItemId: e.primaryItemId,
      questionTemplateId: e.questionTemplateId,
      prompt: e.prompt,
      seed: e.seed,
      premiseNodeId: e.premiseNodeId,
      chain: [
        reasoningThreeChain.first,
        reasoningThreeChain.first,
        e.primaryItemId,
      ],
      options: e.options,
      answer: e.answer,
      chainEvidence: e.chainEvidence,
      contrasts: e.contrasts,
    );
    expect(() => format.grade(invalid, e.answer), throwsArgumentError);
  });

  test(
    'a studied alternative path outside the active track is never selected',
    () async {
      final data = reasoningDatasetMap(),
          params =
              rowOf(
                    data,
                    'question_templates',
                    'id',
                    reasoningTwoTemplateId,
                  )['parameters']
                  as Map;
      (params['scope_node_ids'] as List).add('n_reason_alternate');
      rowsOf(data, 'knowledge_nodes').add({
        'id': 'n_reason_alternate',
        'node_type': 'causal_state',
        'name': 'Alternate starting conditions',
      });
      void edge(String id, String type, String object) {
        rowsOf(data, 'knowledge_relations').add({
          'subject_id': 'n_reason_alternate',
          'relation_type': type,
          'object_id': object,
          'valid_from': '2020-01-01',
        });
        rowsOf(data, 'knowledge_items').add({
          'id': id,
          'subject_id': 'n_reason_alternate',
          'relation_type': type,
          'object_id': object,
          'domain_id': 'viticulture',
          'assertion_text': 'Alternate supplied condition evidence.',
          'last_verified_at': '2026-01-01T00:00:00.000Z',
        });
        rowsOf(data, 'knowledge_item_citations').add({
          'knowledge_item_id': id,
          'source_citation_id': 'src_reason_fixture',
        });
        rowsOf(data, 'certification_knowledge_mappings').add({
          'certification_id': 'WSET_L2',
          'knowledge_item_id': id,
          'importance': 'secondary',
          'minimum_depth': 3,
        });
      }

      edge('ki_reason_alternate', 'CAUSES_STATE', 'n_reason_two_1');
      final alternatives = <Map<String, dynamic>>[];
      for (var i = 1; i <= 3; i++) {
        edge(
          'ki_reason_alternate_contrast_$i',
          'CONTRADICTS',
          'n_reason_two_wrong_$i',
        );
        alternatives.add({
          'option_node_id': 'n_reason_two_wrong_$i',
          'evidence_item_ids': ['ki_reason_alternate_contrast_$i'],
          'explanation':
              'This alternative contradicts the alternate starting conditions.',
        });
      }
      params['contrasts'][reasoningTwoTargetId]['n_reason_alternate'] =
          alternatives;
      await CurriculumIngester(
        db,
        clock: Clock.fixed(now),
      ).ingest(datasetOf(data));
      await studyReasoningSupports(
        db,
        itemIds: [...reasoningSupportIds, 'ki_reason_alternate'],
      );
      for (var seed = 0; seed < 10; seed++) {
        final exercise = await format.present(
          PresentationContext(
            db,
            now: now,
            allowedItemIds: reasoningTwoChain.toSet(),
          ),
          itemId: reasoningTwoTargetId,
          questionTemplateId: reasoningTwoTemplateId,
          seed: seed,
        ) as ReasoningExercise;
        expect(exercise.chain, reasoningTwoChain);
        expect(exercise.premiseNodeId, 'n_reason_two_0');
      }
      await expectLater(
        format.present(
          PresentationContext(
            db,
            now: now,
            allowedItemIds: {reasoningTwoTargetId},
          ),
          itemId: reasoningTwoTargetId,
          questionTemplateId: reasoningTwoTemplateId,
          seed: 1,
        ),
        throwsStateError,
      );
    },
  );
}
