import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/curriculum_dataset.dart';
import '../../../database/app_database.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';

/// The four independent parts of a bounded decision-case response.
const caseCriterionRoles = [
  'CASE_ACTION',
  'CASE_REASON',
  'CASE_TRADEOFF',
  'CASE_LIMITATION',
];

const caseCriterionLabels = {
  'CASE_ACTION': 'Action',
  'CASE_REASON': 'Reason',
  'CASE_TRADEOFF': 'Tradeoff',
  'CASE_LIMITATION': 'Limitation',
};

final class CaseCriterionSource {
  const CaseCriterionSource({
    required this.title,
    required this.publisher,
    this.url,
    this.locator,
  });

  final String title;
  final String publisher;
  final String? url;
  final String? locator;
}

/// The summary is shown before answering; assertion and citations are shown
/// only afterward so they cannot reveal the role.
final class CaseCriterion {
  const CaseCriterion({
    required this.itemId,
    required this.role,
    required this.summary,
    required this.assertion,
    required this.sources,
  });

  final String itemId;
  final String role;
  final String summary;
  final String assertion;
  final List<CaseCriterionSource> sources;
}

/// An offered response statement. Two scenario-specific statements are
/// deliberately unsupported by the case; their explanations appear later.
final class CaseCriterionOption {
  const CaseCriterionOption({
    required this.id,
    required this.summary,
    this.explanation,
  });

  final String id;
  final String summary;
  final String? explanation;
}

final class CaseCriteriaExercise implements Exercise {
  const CaseCriteriaExercise({
    required this.primaryItemId,
    required this.questionTemplateId,
    required this.prompt,
    required this.seed,
    required this.criteria,
    required this.options,
  });

  @override
  final String primaryItemId;
  @override
  final String questionTemplateId;
  @override
  final String prompt;
  @override
  final int seed;

  /// Four assessed case assertions, one per role.
  final List<CaseCriterion> criteria;

  /// Four cited summaries plus two authored, case-specific false claims.
  final List<CaseCriterionOption> options;

  @override
  String get formatId => CaseCriteriaFormat.formatId;

  @override
  List<String> get itemIds => [
    primaryItemId,
    for (final criterion in criteria)
      if (criterion.itemId != primaryItemId) criterion.itemId,
  ];
}

/// One distinct offered response statement per role. The format does not
/// accept a partially completed rubric or one statement in multiple roles.
final class CaseCriteriaResponse {
  CaseCriteriaResponse(Map<String, String> assignments)
    : assignments = Map.unmodifiable(assignments);

  final Map<String, String> assignments;
}

/// Objective, whole-case role matching. It complements, but does not grade,
/// the learner's separately written four-criterion short answer.
class CaseCriteriaFormat extends ExerciseFormat {
  const CaseCriteriaFormat();

  static const formatId = 'case_criteria';

  @override
  String get id => formatId;
  @override
  String get label => 'Case criteria';
  @override
  FormatFamily get family => FormatFamily.structured;
  @override
  bool get isObjective => true;
  @override
  FormatGeneration get generation => FormatGeneration.pooled;
  @override
  int requiredDepth(String direction) => 2;
  @override
  int difficultyRank(String direction) => 9;

  static Map<String, dynamic> _parameters(QuestionTemplate template) {
    final parameters = jsonDecode(template.parameters ?? '{}');
    if (parameters is! Map<String, dynamic>) {
      throw const FormatException('case_criteria parameters must be a map');
    }
    return parameters;
  }

  static Set<String> scopeNodeIdsOf(QuestionTemplate template) {
    final ids = _parameters(template)['scope_node_ids'];
    if (ids is! List ||
        ids.isEmpty ||
        ids.any((id) => id is! String || id.trim().isEmpty) ||
        ids.toSet().length != ids.length) {
      throw const FormatException(
        'case_criteria needs unique, nonempty scope_node_ids',
      );
    }
    return ids.cast<String>().toSet();
  }

  /// Some case subjects have a concise title rather than the full premise.
  /// An explicit override can show the original scenario without changing the
  /// shared subject node used by other question formats.
  static Map<String, String> scenarioPromptsOf(QuestionTemplate template) {
    final scope = scopeNodeIdsOf(template);
    final raw = _parameters(template)['scenario_prompts'];
    if (raw == null) return const {};
    if (raw is! Map<String, dynamic> ||
        raw.keys.toSet().difference(scope).isNotEmpty) {
      throw const FormatException(
        'case_criteria scenario_prompts must be scoped to this template',
      );
    }
    final prompts = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! String || value.trim().length < 80 || value.contains('{')) {
        throw FormatException(
          '${entry.key} needs a full case scenario without placeholders',
        );
      }
      prompts[entry.key] = value.trim();
    }
    return prompts;
  }

  static Map<String, List<CaseCriterionOption>> distractorsOf(
    QuestionTemplate template,
  ) {
    final scope = scopeNodeIdsOf(template);
    final raw = _parameters(template)['distractors'];
    if (raw is! Map<String, dynamic> ||
        raw.keys.toSet().difference(scope).isNotEmpty ||
        scope.difference(raw.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'case_criteria needs distractors for exactly its scoped subjects',
      );
    }
    final result = <String, List<CaseCriterionOption>>{};
    for (final subject in scope) {
      final rows = raw[subject];
      if (rows is! List || rows.length != 2) {
        throw FormatException('$subject needs two case distractors');
      }
      final options = <CaseCriterionOption>[];
      for (final (index, row) in rows.indexed) {
        if (row is! Map<String, dynamic> ||
            row['summary'] is! String ||
            (row['summary'] as String).trim().isEmpty ||
            row['explanation'] is! String ||
            (row['explanation'] as String).trim().isEmpty) {
          throw FormatException(
            '$subject distractor ${index + 1} needs summary and explanation',
          );
        }
        options.add(
          CaseCriterionOption(
            id: '$subject:distractor:${index + 1}',
            summary: row['summary'] as String,
            explanation: row['explanation'] as String,
          ),
        );
      }
      if (options[0].summary.toLowerCase() ==
          options[1].summary.toLowerCase()) {
        throw FormatException('$subject repeats a distractor summary');
      }
      result[subject] = options;
    }
    return result;
  }

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    final problems = <String>[];
    if (template.direction != 'forward' ||
        template.relationType != 'CASE_ACTION') {
      problems.add('case_criteria needs a forward CASE_ACTION template');
    }
    try {
      scopeNodeIdsOf(template);
      distractorsOf(template);
      scenarioPromptsOf(template);
    } on FormatException catch (error) {
      problems.add(error.message);
    }
    if (!template.promptTemplate.contains('{subject.name}') ||
        template.promptTemplate
            .replaceAll('{subject.name}', '')
            .contains('{')) {
      problems.add('case_criteria prompt may use only {subject.name}');
    }
    return problems;
  }

  /// Reject an accidental partial rubric before it can create a pool that
  /// offers only two or three of the four decision criteria.
  static List<String> datasetProblems(
    QuestionTemplate template,
    CurriculumDataset dataset,
  ) {
    final scope = scopeNodeIdsOf(template);
    final distractors = distractorsOf(template);
    final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
    final cited = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId,
    };
    final problems = <String>[];
    for (final subjectId in scope) {
      if (!nodes.containsKey(subjectId)) {
        problems.add('$subjectId is no subject node');
        continue;
      }
      final items = [
        for (final item in dataset.knowledgeItems)
          if (item.subjectId == subjectId &&
              caseCriterionRoles.contains(item.relationType))
            item,
      ];
      if (items.length != 4 ||
          items.map((item) => item.relationType).toSet().length != 4) {
        problems.add('$subjectId needs exactly one item in each case role');
        continue;
      }
      if (items.any((item) => !cited.contains(item.id))) {
        problems.add('$subjectId has a criterion without a source citation');
      }
      final summaries = {for (final item in items) nodes[item.objectId]?.name};
      if (summaries.length != 4 || summaries.contains(null)) {
        problems.add('$subjectId needs four distinct response summaries');
      }
      final allSummaries = {
        ...summaries.map((summary) => summary?.toLowerCase()),
        for (final option in distractors[subjectId]!)
          option.summary.toLowerCase(),
      };
      if (allSummaries.length != 6) {
        problems.add('$subjectId repeats a correct or false response');
      }
    }
    return problems;
  }

  @override
  Future<int> generatePools(
    GeneratorContext context,
    QuestionTemplate template,
  ) async {
    final scope = scopeNodeIdsOf(template);
    final scenarioPrompts = scenarioPromptsOf(template);
    final bySubject = <String, List<KnowledgeItem>>{};
    for (final item in context.items) {
      if (scope.contains(item.subjectId) &&
          caseCriterionRoles.contains(item.relationType)) {
        bySubject.putIfAbsent(item.subjectId, () => []).add(item);
      }
    }
    final subjects = {
      for (final entry in bySubject.entries)
        if (entry.value.length == 4 &&
            entry.value.map((item) => item.relationType).toSet().length == 4)
          entry.key: entry.value,
    };
    final names = {
      for (final node in await (context.db.select(
        context.db.knowledgeNodes,
      )..where((n) => n.id.isIn(subjects.keys))).get())
        node.id: node.name,
    };
    for (final entry in subjects.entries) {
      final poolId = await context.db
          .into(context.db.exercisePools)
          .insert(
            ExercisePoolsCompanion.insert(
              questionTemplateId: template.id,
              scopeNodeId: Value(entry.key),
              promptText:
                  scenarioPrompts[entry.key] ??
                  template.promptTemplate.replaceAll(
                    '{subject.name}',
                    names[entry.key]!,
                  ),
            ),
          );
      final byRole = {for (final item in entry.value) item.relationType: item};
      await context.db.batch(
        (batch) => batch.insertAll(context.db.exercisePoolItems, [
          for (final (rank, role) in caseCriterionRoles.indexed)
            ExercisePoolItemsCompanion.insert(
              exercisePoolId: poolId,
              knowledgeItemId: byRole[role]!.id,
              rank: Value(rank + 1),
            ),
        ]),
      );
    }
    return subjects.length;
  }

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final db = context.db;
    final rows = await db
        .customSelect(
          '''
      SELECT p.prompt_text, p.scope_node_id AS subject,
             i.knowledge_item_id AS item, i.rank,
             k.relation_type, k.assertion_text, n.name AS summary
      FROM exercise_pools p
      JOIN exercise_pool_items mine ON mine.exercise_pool_id = p.id
        AND mine.knowledge_item_id = ?1
      JOIN exercise_pool_items i ON i.exercise_pool_id = p.id
      JOIN knowledge_items k ON k.id = i.knowledge_item_id
      JOIN knowledge_nodes n ON n.id = k.object_id
      WHERE p.question_template_id = ?2
      ORDER BY i.rank
    ''',
          variables: [Variable(itemId), Variable(questionTemplateId)],
          readsFrom: {
            db.exercisePools,
            db.exercisePoolItems,
            db.knowledgeItems,
            db.knowledgeNodes,
          },
        )
        .get();
    final ids = [for (final row in rows) row.read<String>('item')];
    final roles = [for (final row in rows) row.read<String>('relation_type')];
    if (rows.length != 4 ||
        ids.toSet().length != 4 ||
        roles.toSet().length != 4 ||
        !roles.toSet().containsAll(caseCriterionRoles) ||
        (context.allowedItemIds != null &&
            ids.any((id) => !context.allowedItemIds!.contains(id)))) {
      throw StateError(
        '$itemId has no complete in-track case rubric in $questionTemplateId',
      );
    }
    final citations = await (db.select(
      db.knowledgeItemCitations,
    )..where((c) => c.knowledgeItemId.isIn(ids))).get();
    final sourceIds = citations.map((c) => c.sourceCitationId).toSet();
    final sources = {
      for (final source in await (db.select(
        db.sourceCitations,
      )..where((s) => s.id.isIn(sourceIds))).get())
        source.id: source,
    };
    final criteria = [
      for (final row in rows)
        CaseCriterion(
          itemId: row.read<String>('item'),
          role: row.read<String>('relation_type'),
          summary: row.read<String>('summary'),
          assertion: row.read<String>('assertion_text'),
          sources: [
            for (final citation in citations)
              if (citation.knowledgeItemId == row.read<String>('item'))
                CaseCriterionSource(
                  title: sources[citation.sourceCitationId]!.title,
                  publisher: sources[citation.sourceCitationId]!.publisher,
                  url: sources[citation.sourceCitationId]!.url,
                  locator: citation.locator,
                ),
          ],
        ),
    ];
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    final subjectId = rows.first.read<String>('subject');
    final options = [
      for (final criterion in criteria)
        CaseCriterionOption(id: criterion.itemId, summary: criterion.summary),
      ...distractorsOf(template)[subjectId]!,
    ]..shuffle(Random(seed));
    return CaseCriteriaExercise(
      primaryItemId: itemId,
      questionTemplateId: questionTemplateId,
      prompt: rows.first.read<String>('prompt_text'),
      seed: seed,
      criteria: List.unmodifiable(criteria),
      options: List.unmodifiable(options),
    );
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (exercise is! CaseCriteriaExercise ||
        answer is! CaseCriteriaResponse ||
        exercise.criteria.length != 4 ||
        exercise.options.length != 6 ||
        exercise.options.map((o) => o.id).toSet().length != 6 ||
        exercise.criteria.map((c) => c.itemId).toSet().length != 4 ||
        exercise.criteria.map((c) => c.role).toSet().length != 4 ||
        !exercise.criteria
            .map((c) => c.role)
            .toSet()
            .containsAll(caseCriterionRoles) ||
        !exercise.options
            .map((o) => o.id)
            .toSet()
            .containsAll(exercise.itemIds) ||
        !answer.assignments.keys.toSet().containsAll(caseCriterionRoles) ||
        answer.assignments.length != 4 ||
        answer.assignments.values.toSet().length != 4 ||
        !exercise.options
            .map((o) => o.id)
            .toSet()
            .containsAll(answer.assignments.values)) {
      throw ArgumentError.value(answer, 'answer', 'is not a full case rubric');
    }
    return [
      for (final criterion in exercise.criteria)
        ItemGrade(
          criterion.itemId,
          answer.assignments[criterion.role] == criterion.itemId
              ? fsrs.Rating.good
              : fsrs.Rating.again,
          payload: {
            'role': criterion.role,
            'selected_item_id': answer.assignments[criterion.role],
          },
        ),
    ];
  }
}
