import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/reasoning_paths.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/reasoning_fixture.dart';

void main() {
  ReasoningPathResult inspect(
    Map<String, dynamic> data, {
    String templateId = reasoningTwoTemplateId,
  }) {
    final dataset = datasetOf(data);
    return ReasoningPaths.inspectDataset(
      dataset,
      dataset.questionTemplates.singleWhere((t) => t.id == templateId),
      on: reasoningFixtureDate,
    );
  }

  Map<String, dynamic> template(Map<String, dynamic> data) =>
      rowOf(data, 'question_templates', 'id', reasoningTwoTemplateId);
  List<dynamic> contrasts(Map<String, dynamic> data) =>
      (template(data)['parameters']
              as Map)['contrasts'][reasoningTwoTargetId]['n_reason_two_0']
          as List<dynamic>;

  test(
    'two and three cited edges preserve causal order and repeated types',
    () {
      final data = reasoningDatasetMap();
      final two = inspect(data),
          three = inspect(data, templateId: reasoningThreeTemplateId);
      expect(two.diagnostics, isEmpty);
      expect(two.paths.single.itemIds, reasoningTwoChain);
      expect(two.paths.single.premiseNodeId, 'n_reason_two_0');
      expect(two.paths.single.target.id, reasoningTwoTargetId);
      expect(three.diagnostics, isEmpty);
      expect(three.paths.single.itemIds, reasoningThreeChain);
      expect(two.paths.single.contrasts, hasLength(3));
    },
  );

  test('retired, superseded or uncited edges cannot complete a path', () {
    for (final mutation in ['retired', 'superseded', 'uncited']) {
      final data = reasoningDatasetMap();
      if (mutation == 'retired') {
        rowsOf(
              data,
              'knowledge_relations',
            ).cast<Map<String, dynamic>>().singleWhere(
              (r) =>
                  r['subject_id'] == 'n_reason_two_1' &&
                  r['relation_type'] == 'LEADS_TO',
            )['valid_until'] =
            reasoningFixtureDate;
      } else if (mutation == 'superseded') {
        rowOf(
          data,
          'knowledge_items',
          'id',
          reasoningTwoTargetId,
        )['superseded_by_item_id'] = reasoningThreeTargetId;
      } else {
        rowsOf(
          data,
          'knowledge_item_citations',
        ).removeWhere((r) => r['knowledge_item_id'] == reasoningTwoTargetId);
      }
      final result = inspect(data);
      expect(result.paths, isEmpty, reason: mutation);
      expect(result.diagnostics, isNotEmpty, reason: mutation);
    }
  });

  test('uncited structural branches are not assessed paths', () {
    final data = reasoningDatasetMap();
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': 'n_reason_two_1',
      'relation_type': 'LEADS_TO',
      'object_id': 'n_reason_two_wrong_1',
      'valid_from': '2020-01-01',
    });
    expect(inspect(data).paths.single.itemIds, reasoningTwoChain);
  });

  test('a second cited conclusion makes the same premise ambiguous', () {
    final data = reasoningDatasetMap();
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': 'n_reason_two_1',
      'relation_type': 'LEADS_TO',
      'object_id': 'n_reason_two_wrong_1',
      'valid_from': '2020-01-01',
    });
    rowsOf(data, 'knowledge_items').add({
      'id': 'ki_reason_branch',
      'subject_id': 'n_reason_two_1',
      'relation_type': 'LEADS_TO',
      'object_id': 'n_reason_two_wrong_1',
      'domain_id': 'viticulture',
      'assertion_text': 'A conflicting branch.',
      'last_verified_at': '2026-01-01T00:00:00.000Z',
    });
    rowsOf(data, 'knowledge_item_citations').add({
      'knowledge_item_id': 'ki_reason_branch',
      'source_citation_id': 'src_reason_fixture',
    });
    final result = inspect(data);
    expect(result.paths, isEmpty);
    expect(result.diagnostics, contains(contains('ambiguous conclusions')));
  });

  test('cycles at the first or later edge are diagnosed', () {
    for (final first in [true, false]) {
      final data = reasoningDatasetMap();
      final item = rowOf(
        data,
        'knowledge_items',
        'id',
        first ? reasoningTwoChain.first : reasoningTwoTargetId,
      );
      final relation = rowsOf(data, 'knowledge_relations')
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (r) =>
                r['subject_id'] == item['subject_id'] &&
                r['relation_type'] == item['relation_type'] &&
                r['object_id'] == item['object_id'],
          );
      item['object_id'] = 'n_reason_two_0';
      relation['object_id'] = 'n_reason_two_0';
      final result = inspect(data);
      expect(result.paths, isEmpty);
      expect(result.diagnostics, contains(contains('cyclic reasoning path')));
    }
  });

  test('invalid node references produce diagnostics without throwing', () {
    final data = reasoningDatasetMap();
    rowsOf(
      data,
      'knowledge_nodes',
    ).removeWhere((n) => n['id'] == 'n_reason_two_1');
    final result = inspect(data);
    expect(result.paths, isEmpty);
    expect(result.diagnostics, contains(contains('unknown chain node')));
  });

  test(
    'wrong options need direct scoped negative evidence, not positive context',
    () {
      final data = reasoningDatasetMap();
      contrasts(data).first['evidence_item_ids'] = [reasoningTwoChain.first];
      final result = inspect(data);
      expect(result.paths, isEmpty);
      expect(
        result.diagnostics,
        contains(contains('lacks a cited CONTRADICTS edge')),
      );
    },
  );

  test(
    'retired or uncited contradiction evidence does not validate an option',
    () {
      for (final retired in [false, true]) {
        final data = reasoningDatasetMap();
        if (retired) {
          rowsOf(
                data,
                'knowledge_relations',
              ).cast<Map<String, dynamic>>().singleWhere(
                (r) =>
                    r['relation_type'] == 'CONTRADICTS' &&
                    r['object_id'] == 'n_reason_two_wrong_1',
              )['valid_until'] =
              reasoningFixtureDate;
        } else {
          rowsOf(data, 'knowledge_item_citations').removeWhere(
            (c) => c['knowledge_item_id'] == 'ki_reason_two_contrast_1',
          );
        }
        expect(inspect(data).paths, isEmpty);
      }
    },
  );

  test('correct, duplicate and indistinguishable wrong options cannot make four choices', () {
    for (final kind in ['correct', 'duplicate', 'same name']) {
      final data = reasoningDatasetMap(), options = contrasts(data);
      if (kind == 'correct') {
        options.first['option_node_id'] = 'n_reason_two_2';
      }
      if (kind == 'duplicate') {
        options[2] = copyOf({'entry': options[0]})['entry'];
      }
      if (kind == 'same name') {
        rowOf(
          data,
          'knowledge_nodes',
          'id',
          'n_reason_two_wrong_3',
        )['name'] = rowOf(
          data,
          'knowledge_nodes',
          'id',
          'n_reason_two_wrong_2',
        )['name'];
      }
      final result = inspect(data);
      expect(result.paths, isEmpty, reason: kind);
      expect(result.diagnostics, isNotEmpty, reason: kind);
    }
  });

  test(
    'the reference helper checks unused authored targets and unknown scope',
    () {
      final data = reasoningDatasetMap(),
          parameters = template(data)['parameters'] as Map;
      parameters['scope_node_ids'] = ['n_missing'];
      final dataset = datasetOf(data),
          t = dataset.questionTemplates.singleWhere(
            (t) => t.id == reasoningTwoTemplateId,
          );
      final errors = ReasoningPaths.templateReferenceProblems(
        dataset,
        t,
        on: reasoningFixtureDate,
      );
      expect(errors, contains(contains('unknown starting scope')));
      expect(errors, contains(contains('outside starting scope')));
    },
  );

  test(
    'parameters reject star relations, reverse paths and answer placeholders',
    () {
      final dataset = reasoningDataset();
      final base = dataset.questionTemplates.singleWhere(
        (t) => t.id == reasoningTwoTemplateId,
      );
      final types = dataset.relationTypes.map((t) => t.id).toSet();
      expect(
        ReasoningPaths.templateProblems(
          base.copyWith(direction: 'reverse'),
          relationTypes: types,
        ),
        contains('reasoning templates must be forward'),
      );
      expect(
        ReasoningPaths.templateProblems(
          base.copyWith(promptTemplate: 'What follows from {object.name}?'),
          relationTypes: types,
        ),
        contains(contains('only {subject.name}')),
      );
      for (final type in ['CASE_REASON', 'PRINCIPLE_EXPLANATION']) {
        final data = reasoningDatasetMap();
        (template(data)['parameters'] as Map)['path_relation_types'] = [
          type,
          'LEADS_TO',
        ];
        final t = datasetOf(data).questionTemplates
            .singleWhere((t) => t.id == reasoningTwoTemplateId);
        expect(
          ReasoningPaths.templateProblems(t, relationTypes: {...types, type}),
          contains('$type cannot establish a forward causal step'),
        );
      }
    },
  );

  test('existing pool loses eligibility when required negative evidence is uncited or expired', () async {
    for (final change in ['uncited', 'expired', 'superseded']) {
      final db = openTestDatabase();
      try {
        await CurriculumIngester(
          db,
          clock: Clock.fixed(DateTime.utc(2026, 1, 1)),
        ).ingest(reasoningDataset());
        final pools = await db.select(db.exercisePools).get();
        final two = pools
            .singleWhere((p) => p.questionTemplateId == reasoningTwoTemplateId)
            .id;
        final three = pools
            .singleWhere(
              (p) => p.questionTemplateId == reasoningThreeTemplateId,
            )
            .id;
        final paths = ReasoningPaths(db);
        expect(await paths.validPoolIds(on: reasoningFixtureDate), {
          two,
          three,
        });
        await db.writeCurriculum(() async {
          if (change == 'uncited') {
            await (db.delete(db.knowledgeItemCitations)..where(
                  (c) => c.knowledgeItemId.equals('ki_reason_two_contrast_1'),
                ))
                .go();
          } else if (change == 'expired') {
            await (db.update(db.knowledgeRelations)..where(
                  (r) =>
                      r.subjectId.equals('n_reason_two_0') &
                      r.relationType.equals('CONTRADICTS') &
                      r.objectId.equals('n_reason_two_wrong_1'),
                ))
                .write(
                  const KnowledgeRelationsCompanion(
                    validUntil: Value(reasoningFixtureDate),
                  ),
                );
          } else {
            await (db.update(
              db.knowledgeItems,
            )..where((i) => i.id.equals('ki_reason_two_contrast_1'))).write(
              const KnowledgeItemsCompanion(
                supersededByItemId: Value('ki_reason_three_contrast_1'),
              ),
            );
          }
        });
        expect(await paths.validPoolIds(on: reasoningFixtureDate), {
          three,
        }, reason: change);
        expect(
          (await db.select(db.exercisePoolItems).get()).where(
            (m) => m.exercisePoolId == two,
          ),
          hasLength(2),
          reason: 'positive members remain complete; loss is in explanatory contradiction evidence',
        );
      } finally {
        await db.close();
      }
    }
  });

  test('pool eligibility validates exact stored premise, ordered members and ranks', () async {
    final db = openTestDatabase();
    try {
      await CurriculumIngester(
        db,
        clock: Clock.fixed(DateTime.utc(2026, 1, 1)),
      ).ingest(reasoningDataset());
      final pools = await db.select(db.exercisePools).get();
      final two = pools
          .singleWhere((p) => p.questionTemplateId == reasoningTwoTemplateId)
          .id;
      final three = pools
          .singleWhere((p) => p.questionTemplateId == reasoningThreeTemplateId)
          .id;
      final paths = ReasoningPaths(db);
      expect(await paths.validPoolIds(on: reasoningFixtureDate), {two, three});
      await db.writeCurriculum(() async {
        await (db.update(db.exercisePoolItems)..where(
              (m) =>
                  m.exercisePoolId.equals(two) &
                  m.knowledgeItemId.equals(reasoningTwoTargetId),
            ))
            .write(const ExercisePoolItemsCompanion(rank: Value(3)));
        await (db.update(
          db.exercisePools,
        )..where((p) => p.id.equals(three))).write(
          const ExercisePoolsCompanion(scopeNodeId: Value('n_reason_two_0')),
        );
      });
      expect(await paths.validPoolIds(on: reasoningFixtureDate), isEmpty);
    } finally {
      await db.close();
    }
  });
}
