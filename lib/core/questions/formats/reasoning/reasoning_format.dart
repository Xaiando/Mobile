import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/curriculum_dataset.dart';
import '../../../curriculum/reasoning_paths.dart';
import '../../../database/app_database.dart';
import '../../../time/utc_clock.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// A source and its item-specific locator, fetched in core before display.
final class ReasoningSource {
  const ReasoningSource({
    required this.sourceId,
    required this.title,
    required this.publisher,
    this.url,
    this.locator,
  });
  final String sourceId;
  final String title;
  final String publisher;
  final String? url;
  final String? locator;
}

final class ReasoningEvidence {
  const ReasoningEvidence({
    required this.itemId,
    required this.title,
    required this.statement,
    required this.sources,
  });
  final String itemId;
  final String title;
  final String statement;
  final List<ReasoningSource> sources;
}

/// Explanatory evidence is not an assessed or credited pool member.
final class ReasoningContrastExplanation {
  const ReasoningContrastExplanation({
    required this.option,
    required this.statement,
    required this.evidence,
  });
  final QuestionOption option;
  final String statement;
  final List<ReasoningEvidence> evidence;
}

final class ReasoningExercise implements Exercise {
  const ReasoningExercise({
    required this.primaryItemId,
    required this.questionTemplateId,
    required this.prompt,
    required this.seed,
    required this.premiseNodeId,
    required this.chain,
    required this.options,
    required this.answer,
    required this.chainEvidence,
    required this.contrasts,
  });

  @override
  final String primaryItemId;
  @override
  final String questionTemplateId;
  @override
  final String prompt;
  @override
  final int seed;
  final String premiseNodeId;

  /// Every assessed edge, in causal order, with the primary target last.
  final List<String> chain;
  final List<QuestionOption> options;
  final QuestionOption answer;
  final List<ReasoningEvidence> chainEvidence;
  final List<ReasoningContrastExplanation> contrasts;

  @override
  String get formatId => ReasoningFormat.formatId;
  @override
  List<String> get itemIds => [
    primaryItemId,
    for (final id in chain)
      if (id != primaryItemId) id,
  ];
}

/// Objective forward reasoning through complete cited two/three-edge paths.
class ReasoningFormat extends ExerciseFormat {
  const ReasoningFormat({this.onDiagnostic});
  static const formatId = 'reasoning';
  final void Function(String diagnostic)? onDiagnostic;
  @override
  String get id => formatId;
  @override
  String get label => 'Reasoning';
  @override
  FormatFamily get family => FormatFamily.reasoning;
  @override
  bool get isObjective => true;
  @override
  FormatGeneration get generation => FormatGeneration.pooled;
  @override
  int requiredDepth(String direction) => 4;
  @override
  int difficultyRank(String direction) => 6;

  /// Shared planner/coverage rule: support membership is not an assessment.
  /// Aliases are fixed SQL identifiers supplied by core callers, never input.
  static String scheduledPoolMemberSql({
    String memberAlias = 'i',
    String templateAlias = 't',
  }) {
    final identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    if (!identifier.hasMatch(memberAlias) ||
        !identifier.hasMatch(templateAlias)) {
      throw ArgumentError(
        'pool member/template aliases must be SQL identifiers',
      );
    }
    return "($templateAlias.mode <> 'reasoning' OR $memberAlias.rank = "
        '(SELECT MAX(reasoning_last.rank) FROM exercise_pool_items reasoning_last '
        'WHERE reasoning_last.exercise_pool_id = $memberAlias.exercise_pool_id))';
  }

  static List<String> datasetProblems(
    QuestionTemplate template,
    CurriculumDataset dataset, {
    String? on,
  }) => ReasoningPaths.templateReferenceProblems(
    dataset,
    template,
    on: on ?? dataset.publishedAt.toUtc().toIso8601String().substring(0, 10),
  );

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) => ReasoningPaths.templateProblems(template, relationTypes: relationTypes);

  static String _prompt(QuestionTemplate template, String premiseName) =>
      template.promptTemplate.replaceAll('{subject.name}', premiseName);

  @override
  Future<int> generatePools(
    GeneratorContext context,
    QuestionTemplate template,
  ) async {
    final result = await ReasoningPaths(context.db).enumerate(
      template,
      on: context.today,
      eligibleItemIds: context.items.map((i) => i.id).toSet(),
    );
    for (final diagnostic in result.diagnostics) {
      onDiagnostic?.call('${template.id}: $diagnostic');
    }
    final db = context.db,
        nodes = {
          for (final n in await db.select(db.knowledgeNodes).get()) n.id: n,
        };
    for (final path in result.paths) {
      final pool = await db
          .into(db.exercisePools)
          .insert(
            ExercisePoolsCompanion.insert(
              questionTemplateId: template.id,
              scopeNodeId: Value(path.premiseNodeId),
              promptText: _prompt(template, nodes[path.premiseNodeId]!.name),
            ),
          );
      await db.batch(
        (b) => b.insertAll(db.exercisePoolItems, [
          for (final (index, item) in path.items.indexed)
            ExercisePoolItemsCompanion.insert(
              exercisePoolId: pool,
              knowledgeItemId: item.id,
              rank: Value(index + 1),
            ),
        ]),
      );
    }
    return result.paths.length;
  }

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final db = context.db;
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    final date = isoDate(context.now.toLocal());
    final validated = await ReasoningPaths(db).enumerate(template, on: date);
    for (final diagnostic in validated.diagnostics) {
      onDiagnostic?.call('${template.id}: $diagnostic');
    }
    final rows = await db
        .customSelect(
          '''
      SELECT p.id AS pool, p.scope_node_id AS premise, member.knowledge_item_id AS item, member.rank
      FROM exercise_pools p
      JOIN question_templates t ON t.id = p.question_template_id
      JOIN exercise_pool_items mine ON mine.exercise_pool_id = p.id AND mine.knowledge_item_id = ?1
      JOIN exercise_pool_items member ON member.exercise_pool_id = p.id
      WHERE p.question_template_id = ?2 AND ${scheduledPoolMemberSql(memberAlias: 'mine')}
      ORDER BY p.id, member.rank
    ''',
          variables: [Variable(itemId), Variable(questionTemplateId)],
          readsFrom: {
            db.exercisePools,
            db.exercisePoolItems,
            db.questionTemplates,
          },
        )
        .get();
    if (rows.isEmpty) {
      throw ArgumentError.value(
        itemId,
        'itemId',
        'is not a primary target of $questionTemplateId',
      );
    }
    final grouped = <int, List<QueryRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.read<int>('pool'), () => []).add(row);
    }
    final studied = (await db.select(db.reviewStates).get())
        .map((s) => s.knowledgeItemId)
        .toSet();
    final candidates = <ReasoningPath>[];
    for (final pool in grouped.values) {
      final ids = pool.map((r) => r.read<String>('item')).toList();
      if (ids.length < 2 ||
          ids.length > 3 ||
          ids.last != itemId ||
          pool.indexed.any(
            (pair) => pair.$2.readNullable<int>('rank') != pair.$1 + 1,
          )) {
        onDiagnostic?.call('invalid or incomplete reasoning pool for $itemId');
        continue;
      }
      if (ids.take(ids.length - 1).any((id) => !studied.contains(id))) {
        onDiagnostic?.call(
          'reasoning supports must already be studied for $itemId',
        );
        continue;
      }
      if (context.allowedItemIds != null &&
          ids.any((id) => !context.allowedItemIds!.contains(id))) {
        onDiagnostic?.call(
          'reasoning chain contains an item outside the active track for $itemId',
        );
        continue;
      }
      for (final path in validated.paths) {
        if (path.premiseNodeId == pool.first.readNullable<String>('premise') &&
            path.itemIds.length == ids.length &&
            path.itemIds.indexed.every((pair) => pair.$2 == ids[pair.$1])) {
          candidates.add(path);
        }
      }
    }
    if (candidates.isEmpty) {
      throw StateError(
        '$itemId has no complete current reasoning pool with studied supports in $questionTemplateId',
      );
    }
    final random = Random(seed),
        path = candidates[random.nextInt(candidates.length)];
    final wrong = [...path.contrasts]..shuffle(random);
    final shown = wrong.take(3).toList();
    final nodes = {
      for (final n in await db.select(db.knowledgeNodes).get()) n.id: n,
    };
    QuestionOption option(String id) => QuestionOption(id, nodes[id]!.name);
    final answer = option(path.target.objectId);
    final options = [
      answer,
      for (final contrast in shown) option(contrast.optionNodeId),
    ]..shuffle(random);
    final evidenceIds = {
      for (final item in path.items) item.id,
      for (final contrast in shown) ...contrast.evidenceItemIds,
    };
    final items = {
      for (final item in await (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.isIn(evidenceIds))).get())
        item.id: item,
    };
    final citations = await (db.select(
      db.knowledgeItemCitations,
    )..where((c) => c.knowledgeItemId.isIn(evidenceIds))).get();
    final sourceIds = citations.map((c) => c.sourceCitationId).toSet();
    final sources = {
      for (final s in await (db.select(
        db.sourceCitations,
      )..where((s) => s.id.isIn(sourceIds))).get())
        s.id: s,
    };
    ReasoningEvidence evidence(String id) {
      final item = items[id]!;
      final itemSources =
          citations.where((c) => c.knowledgeItemId == id).toList()
            ..sort((a, b) => a.sourceCitationId.compareTo(b.sourceCitationId));
      return ReasoningEvidence(
        itemId: id,
        title: '${nodes[item.subjectId]!.name} → ${nodes[item.objectId]!.name}',
        statement: item.assertionText,
        sources: List.unmodifiable([
          for (final c in itemSources)
            ReasoningSource(
              sourceId: c.sourceCitationId,
              title: sources[c.sourceCitationId]!.title,
              publisher: sources[c.sourceCitationId]!.publisher,
              url: sources[c.sourceCitationId]!.url,
              locator: c.locator,
            ),
        ]),
      );
    }

    return ReasoningExercise(
      primaryItemId: itemId,
      questionTemplateId: questionTemplateId,
      prompt: _prompt(template, nodes[path.premiseNodeId]!.name),
      seed: seed,
      premiseNodeId: path.premiseNodeId,
      chain: List.unmodifiable(path.itemIds),
      options: List.unmodifiable(options),
      answer: answer,
      chainEvidence: List.unmodifiable([
        for (final id in path.itemIds) evidence(id),
      ]),
      contrasts: List.unmodifiable([
        for (final contrast in shown)
          ReasoningContrastExplanation(
            option: option(contrast.optionNodeId),
            statement: contrast.explanation,
            evidence: List.unmodifiable([
              for (final id in contrast.evidenceItemIds) evidence(id),
            ]),
          ),
      ]),
    );
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (exercise is! ReasoningExercise ||
        answer is! QuestionOption ||
        !exercise.options.contains(answer)) {
      throw ArgumentError.value(
        answer,
        'answer',
        'is not an option of a reasoning exercise',
      );
    }
    if (exercise.chain.length < 2 ||
        exercise.chain.length > 3 ||
        exercise.chain.toSet().length != exercise.chain.length ||
        exercise.chain.last != exercise.primaryItemId ||
        exercise.options.length != 4 ||
        exercise.options.map((o) => o.nodeId).toSet().length != 4 ||
        !exercise.options.contains(exercise.answer)) {
      throw ArgumentError(
        'reasoning exercise has an invalid chain or answer options',
      );
    }
    final correct = answer == exercise.answer;
    final shown = [for (final option in exercise.options) option.nodeId];
    final payload = <String, Object>{
      'seed': exercise.seed,
      'chain': exercise.chain,
      'premise_node_id': exercise.premiseNodeId,
      'shown_options': shown,
      'selected_node_id': answer.nodeId,
      'correct': correct,
    };
    return [
      for (final id in correct ? exercise.itemIds : [exercise.primaryItemId])
        ItemGrade(
          id,
          correct ? fsrs.Rating.good : fsrs.Rating.again,
          optionNodeIds: shown,
          selectedNodeId: answer.nodeId,
          payload: payload,
        ),
    ];
  }
}
