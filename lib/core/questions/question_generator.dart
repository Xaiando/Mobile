import 'package:drift/drift.dart';

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';
import 'template_renderer.dart';

/// Wrong options shown with every multiple-choice question: always four
/// options in total, or no MCQ at all (architecture audit QG-6).
const distractorsPerQuestion = 3;

/// Why an (item, template) pair produced no question.
enum SkipReason {
  /// A reverse question would not identify one answer (QG-3).
  notReverseSafe,

  /// A curator marked the item flashcard-only.
  mcqDisabled,

  /// Fewer than [distractorsPerQuestion] valid wrong answers exist.
  tooFewDistractors,
}

class SkippedQuestion {
  const SkippedQuestion(this.itemId, this.templateId, this.reason);

  final String itemId;
  final String templateId;
  final SkipReason reason;

  @override
  String toString() => '$itemId × $templateId: ${reason.name}';
}

/// What a generation run produced: the build report of QG-3.
class GenerationReport {
  int flashcards = 0;
  int multipleChoice = 0;
  final skipped = <SkippedQuestion>[];

  int get questions => flashcards + multipleChoice;
}

/// A valid wrong answer and how far from the subject it was found:
/// 0 is the nearest geographic scope.
class Distractor {
  const Distractor(this.nodeId, this.scopeRank);

  final String nodeId;
  final int scopeRank;

  @override
  String toString() => '$nodeId@$scopeRank';
}

/// Generates the servable questions from the curriculum (spec §H, TASK-004).
///
/// Each current item is phrased by every template of its relation type that
/// it is eligible for (QG-3). A multiple-choice question stores its pool of
/// distractors, found by walking up the subject's geographic scopes and
/// widening until [distractorsPerQuestion] exist (QG-4, QG-5).
class QuestionGenerator {
  QuestionGenerator(this.db, {required this.today});

  final AppDatabase db;

  /// The date, `YYYY-MM-DD`, on which relations must be in force.
  final String today;

  /// Rebuilds `questions` and `question_distractors`. Runs inside the
  /// ingestion transaction, which holds the curriculum write lock.
  Future<GenerationReport> generate() async {
    final report = GenerationReport();
    // Deleting a question cascades to its distractors.
    await db.delete(db.questions).go();

    final nodes = {
      for (final node in await db.select(db.knowledgeNodes).get())
        node.id: node,
    };
    final typeLabels = {
      for (final type in await db.select(db.nodeTypes).get())
        type.id: type.label,
    };
    final relationTypes = {
      for (final type in await db.select(db.relationTypes).get()) type.id: type,
    };
    final templates = <String, List<QuestionTemplate>>{};
    for (final template in await (db.select(
      db.questionTemplates,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get()) {
      templates.putIfAbsent(template.relationType, () => []).add(template);
    }

    final questions = <Question>[];
    final pools = <QuestionDistractor>[];
    for (final item in await _currentItems()) {
      final relationType = relationTypes[item.relationType]!;
      for (final template
          in templates[item.relationType] ?? const <QuestionTemplate>[]) {
        final reverse = template.direction == 'reverse';
        if (reverse && !relationType.isReverseSafe && !item.isDistinctive) {
          report.skipped.add(
            SkippedQuestion(item.id, template.id, SkipReason.notReverseSafe),
          );
          continue;
        }
        var pool = const <Distractor>[];
        if (template.mode == 'mcq') {
          if (item.mcqDisabled) {
            report.skipped.add(
              SkippedQuestion(item.id, template.id, SkipReason.mcqDisabled),
            );
            continue;
          }
          pool = await distractorPool(item, reverse: reverse);
          if (pool.length < distractorsPerQuestion) {
            report.skipped.add(
              SkippedQuestion(
                item.id,
                template.id,
                SkipReason.tooFewDistractors,
              ),
            );
            continue;
          }
          report.multipleChoice++;
        } else {
          report.flashcards++;
        }
        final object = nodes[item.objectId]!;
        questions.add(
          Question(
            knowledgeItemId: item.id,
            questionTemplateId: template.id,
            relationType: item.relationType,
            promptText: renderPrompt(
              template.promptTemplate,
              subjectName: nodes[item.subjectId]!.name,
              objectName: object.name,
              objectTypeLabel: typeLabels[object.nodeType]!,
            ),
          ),
        );
        pools.addAll([
          for (final distractor in pool)
            QuestionDistractor(
              knowledgeItemId: item.id,
              questionTemplateId: template.id,
              knowledgeNodeId: distractor.nodeId,
              scopeRank: distractor.scopeRank,
            ),
        ]);
      }
    }
    await db.batch((b) {
      b.insertAll(db.questions, questions);
      b.insertAll(db.questionDistractors, pools);
    });
    return report;
  }

  /// Items whose relation is in force and that nothing supersedes. Expired
  /// and superseded items keep their history but leave the question set
  /// (audit FS-13).
  Future<List<KnowledgeItem>> _currentItems() => db
      .customSelect(
        '''
    SELECT i.* FROM knowledge_items i
    JOIN knowledge_relations r ON r.subject_id = i.subject_id
      AND r.relation_type = i.relation_type AND r.object_id = i.object_id
    WHERE i.superseded_by_item_id IS NULL
      AND r.valid_from <= ?1 AND (r.valid_until IS NULL OR r.valid_until > ?1)
    ORDER BY i.id''',
        variables: [Variable(today)],
        readsFrom: {db.knowledgeItems, db.knowledgeRelations},
      )
      .map((row) => db.knowledgeItems.map(row.data))
      .get();

  /// The valid wrong answers for [item]: its object's peers for a forward
  /// question, its subject's peers for a [reverse] one, nearest first.
  ///
  /// Candidates are searched level by level, stopping at the first level
  /// that brings the pool to [distractorsPerQuestion]:
  /// 1. each geographic scope containing the subject, nearest first;
  /// 2. the relation anywhere in the curriculum;
  /// 3. every node of the answer's type.
  ///
  /// A candidate has the answer's node type, its berry colour (or other
  /// `distractor_match_relation_type` value) and its unit for quantities. It
  /// is never an answer that is correct in any validity period, nor a node
  /// whose normalized name matches one.
  Future<List<Distractor>> distractorPool(
    KnowledgeItem item, {
    required bool reverse,
  }) async {
    final relationType = await (db.select(
      db.relationTypes,
    )..where((t) => t.id.equals(item.relationType))).getSingle();
    final answerId = reverse ? item.subjectId : item.objectId;
    final answerType = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.equals(answerId))).map((n) => n.nodeType).getSingle();
    final match = reverse ? null : relationType.distractorMatchRelationType;
    final universe = await _candidates(answerType, match);
    final answer = universe[answerId];
    if (answer == null) return const [];

    final correct = reverse
        ? await _subjectsHolding(relationType, item.objectId)
        : await _objectsHeld(relationType, item.subjectId);
    correct.add(answerId);
    final correctNames = {
      for (final id in correct)
        if (universe[id] case final node?) node.nameNorm,
    };

    bool admissible(String id) {
      final candidate = universe[id];
      if (candidate == null || correct.contains(id)) return false;
      if (correctNames.contains(candidate.nameNorm)) return false;
      if (match != null &&
          answer.matchValue != null &&
          candidate.matchValue != answer.matchValue) {
        return false;
      }
      return answer.unit == null || candidate.unit == answer.unit;
    }

    final scopes = await KnowledgeGraph(db)
        .ancestors(item.subjectId, on: today);
    final levels = <Future<List<String>> Function()>[
      for (final scope in scopes)
        () => reverse
            ? _nodesWithin(scope.id)
            : _objectsWithin(item.relationType, scope.id, item.subjectId),
      () => reverse
          ? _subjectsOf(item.relationType)
          : _objectsOf(item.relationType, item.subjectId),
      () async => universe.keys.toList(),
    ];

    final pool = <Distractor>[];
    final seen = <String>{};
    for (final (rank, level) in levels.indexed) {
      for (final id in await level()) {
        if (admissible(id) && seen.add(id)) pool.add(Distractor(id, rank));
      }
      if (pool.length >= distractorsPerQuestion) break;
    }
    return pool;
  }

  static const _maxDepth = KnowledgeGraph.maxDepth;

  /// SQL for "relation [alias] is in force on the date bound to [date]".
  static String _current(String alias, String date) =>
      '$alias.valid_from <= $date '
      'AND ($alias.valid_until IS NULL OR $alias.valid_until > $date)';

  /// Current nodes of [nodeType], with the values distractors must share.
  Future<Map<String, _Candidate>> _candidates(
    String nodeType,
    String? matchRelation,
  ) async {
    final rows = await db
        .customSelect(
          '''
      SELECT n.id, n.name_norm, q.unit,
        (SELECT m.object_id FROM knowledge_relations m
         WHERE m.subject_id = n.id AND m.relation_type = ?2
           AND ${_current('m', '?3')}
         ORDER BY m.object_id LIMIT 1) AS match_value
      FROM knowledge_nodes n
      LEFT JOIN quantity_values q ON q.knowledge_node_id = n.id
      WHERE n.node_type = ?1
        AND (n.valid_from IS NULL OR n.valid_from <= ?3)
        AND (n.valid_until IS NULL OR n.valid_until > ?3)
      ORDER BY n.id''',
          variables: [
            Variable(nodeType),
            Variable(matchRelation),
            Variable(today),
          ],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): _Candidate(
          nameNorm: row.read<String>('name_norm'),
          unit: row.readNullable<String>('unit'),
          matchValue: row.readNullable<String>('match_value'),
        ),
    };
  }

  /// Every object [subjectId] holds for the relation, in any validity
  /// period, transitively for a transitive relation type (QG-4).
  Future<Set<String>> _objectsHeld(RelationType type, String subjectId) =>
      _reach(type, subjectId, from: 'subject_id', to: 'object_id');

  /// Every subject that holds the relation to [objectId], in any validity
  /// period (QG-5).
  Future<Set<String>> _subjectsHolding(RelationType type, String objectId) =>
      _reach(type, objectId, from: 'object_id', to: 'subject_id');

  Future<Set<String>> _reach(
    RelationType type,
    String start, {
    required String from,
    required String to,
  }) async {
    final rows = await db
        .customSelect(
          type.isTransitive
              ? '''
      WITH RECURSIVE reach(id, depth) AS (
        SELECT $to, 1 FROM knowledge_relations
        WHERE $from = ?1 AND relation_type = ?2
        UNION
        SELECT r.$to, reach.depth + 1
        FROM knowledge_relations r JOIN reach ON r.$from = reach.id
        WHERE r.relation_type = ?2 AND reach.depth < $_maxDepth
      )
      SELECT DISTINCT id FROM reach'''
              : '''
      SELECT $to AS id FROM knowledge_relations
      WHERE $from = ?1 AND relation_type = ?2''',
          variables: [Variable(start), Variable(type.id)],
        )
        .get();
    return {for (final row in rows) row.read<String>('id')};
  }

  /// SQL for the nodes inside [scope] (bound to `?1`), the scope included.
  static String _within() =>
      '''
    within(id, depth) AS (
      SELECT ?1, 0
      UNION
      SELECT r.subject_id, within.depth + 1
      FROM knowledge_relations r JOIN within ON r.object_id = within.id
      WHERE r.relation_type = 'LOCATED_IN' AND within.depth < $_maxDepth
        AND ${_current('r', '?2')}
    )''';

  /// Objects of the relation held by other subjects inside [scopeId].
  Future<List<String>> _objectsWithin(
    String relationType,
    String scopeId,
    String subjectId,
  ) => _ids(
    '''
    WITH RECURSIVE ${_within()}
    SELECT DISTINCT r.object_id AS id FROM knowledge_relations r
    WHERE r.relation_type = ?3 AND r.subject_id <> ?4
      AND r.subject_id IN (SELECT id FROM within)
      AND ${_current('r', '?2')}
    ORDER BY id''',
    [scopeId, today, relationType, subjectId],
  );

  /// Every node inside [scopeId].
  Future<List<String>> _nodesWithin(String scopeId) => _ids(
    'WITH RECURSIVE ${_within()} SELECT id FROM within ORDER BY id',
    [scopeId, today],
  );

  /// Objects of the relation held by any other subject.
  Future<List<String>> _objectsOf(String relationType, String subjectId) =>
      _ids(
        '''
    SELECT DISTINCT r.object_id AS id FROM knowledge_relations r
    WHERE r.relation_type = ?1 AND r.subject_id <> ?3
      AND ${_current('r', '?2')}
    ORDER BY id''',
        [relationType, today, subjectId],
      );

  /// Subjects of the relation, whatever their object.
  Future<List<String>> _subjectsOf(String relationType) => _ids(
    '''
    SELECT DISTINCT r.subject_id AS id FROM knowledge_relations r
    WHERE r.relation_type = ?1 AND ${_current('r', '?2')}
    ORDER BY id''',
    [relationType, today],
  );

  Future<List<String>> _ids(String sql, List<String> variables) async {
    final rows = await db
        .customSelect(sql, variables: [for (final v in variables) Variable(v)])
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }
}

class _Candidate {
  const _Candidate({required this.nameNorm, this.unit, this.matchValue});

  final String nameNorm;
  final String? unit;

  /// The node's value for the relation type's `distractor_match_relation_type`,
  /// e.g. its berry colour.
  final String? matchValue;
}
