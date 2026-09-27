import 'dart:convert';

import '../database/app_database.dart';
import 'curriculum_dataset.dart';
import 'knowledge_graph.dart';
import 'name_normalizer.dart';

/// An authored, scoped contradiction, never inferred from a missing edge.
final class ReasoningContrast {
  const ReasoningContrast({
    required this.optionNodeId,
    required this.evidenceItemIds,
    required this.explanation,
  });

  final String optionNodeId;
  final List<String> evidenceItemIds;
  final String explanation;
}

/// Validated parameters of a forward two/three-edge reasoning template.
final class ReasoningParameters {
  const ReasoningParameters({
    required this.pathRelationTypes,
    required this.scopeNodeIds,
    required this.contrasts,
  });

  final List<String> pathRelationTypes;
  final Set<String>? scopeNodeIds;

  /// Target item -> starting premise -> explicit wrong alternatives.
  final Map<String, Map<String, List<ReasoningContrast>>> contrasts;

  static ReasoningParameters parse(QuestionTemplate template) {
    final Object? decoded;
    try {
      decoded = jsonDecode(template.parameters ?? 'null');
    } on FormatException {
      throw const FormatException('reasoning parameters must be a JSON object');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('reasoning parameters must be an object');
    }
    List<String> ids(Object? value, String field, {bool unique = true}) {
      if (value is! List ||
          value.isEmpty ||
          value.any((id) => id is! String || id.trim().isEmpty) ||
          (unique && value.toSet().length != value.length)) {
        throw FormatException('$field must be a nonempty list of unique IDs');
      }
      return List<String>.unmodifiable(value.cast<String>());
    }

    final types = ids(
      decoded['path_relation_types'],
      'path_relation_types',
      unique: false,
    );
    if (types.length < 2 || types.length > 3) {
      throw const FormatException(
        'path_relation_types needs two or three edges',
      );
    }
    // Repeated causal types are allowed; unlike an ID set they describe steps.
    final rawTypes = decoded['path_relation_types'] as List;
    final scope = decoded.containsKey('scope_node_ids')
        ? ids(decoded['scope_node_ids'], 'scope_node_ids').toSet()
        : null;
    final raw = decoded['contrasts'];
    if (raw is! Map<String, dynamic> || raw.isEmpty) {
      throw const FormatException(
        'contrasts must map target items to starting premises',
      );
    }
    final contrasts = <String, Map<String, List<ReasoningContrast>>>{};
    for (final target in raw.entries) {
      if (target.key.trim().isEmpty ||
          target.value is! Map<String, dynamic> ||
          (target.value as Map).isEmpty) {
        throw const FormatException(
          'each contrasts target needs starting-premise entries',
        );
      }
      final starts = <String, List<ReasoningContrast>>{};
      for (final start in (target.value as Map<String, dynamic>).entries) {
        if (start.key.trim().isEmpty ||
            start.value is! List ||
            (start.value as List).isEmpty) {
          throw const FormatException(
            'each contrasts premise needs a list of alternatives',
          );
        }
        final options = <ReasoningContrast>[];
        for (final alternative in start.value as List) {
          if (alternative is! Map<String, dynamic> ||
              alternative['option_node_id'] is! String ||
              (alternative['option_node_id'] as String).trim().isEmpty ||
              alternative['explanation'] is! String ||
              (alternative['explanation'] as String).trim().isEmpty) {
            throw const FormatException(
              'a contrast needs option_node_id and a nonempty explanation',
            );
          }
          options.add(
            ReasoningContrast(
              optionNodeId: alternative['option_node_id'] as String,
              evidenceItemIds: ids(
                alternative['evidence_item_ids'],
                'evidence_item_ids',
              ),
              explanation: alternative['explanation'] as String,
            ),
          );
        }
        starts[start.key] = List.unmodifiable(options);
      }
      contrasts[target.key] = Map.unmodifiable(starts);
    }
    return ReasoningParameters(
      pathRelationTypes: List<String>.unmodifiable(rawTypes.cast<String>()),
      scopeNodeIds: scope == null ? null : Set.unmodifiable(scope),
      contrasts: Map.unmodifiable(contrasts),
    );
  }
}

/// A complete causal chain. Its final edge is the only scheduling target.
final class ReasoningPath {
  const ReasoningPath({
    required this.premiseNodeId,
    required this.items,
    required this.contrasts,
  });

  final String premiseNodeId;
  final List<KnowledgeItem> items;
  final List<ReasoningContrast> contrasts;
  KnowledgeItem get target => items.last;
  List<String> get itemIds => [for (final item in items) item.id];
}

/// Generation skips invalid/ambiguous candidates and explains why.
final class ReasoningPathResult {
  const ReasoningPathResult({required this.paths, required this.diagnostics});
  final List<ReasoningPath> paths;
  final List<String> diagnostics;
}

/// Current cited item paths, rather than arbitrary graph-edge or case order.
class ReasoningPaths {
  const ReasoningPaths(this.db);
  final AppDatabase db;

  static const contradictionRelationType = 'CONTRADICTS';

  static bool _starType(String type) =>
      type == 'PRINCIPLE_EXPLANATION' || type.startsWith('CASE_');

  static List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    final ReasoningParameters parameters;
    try {
      parameters = ReasoningParameters.parse(template);
    } on FormatException catch (error) {
      return [error.message];
    }
    return [
      if (template.direction != 'forward')
        'reasoning templates must be forward',
      if (template.mode != 'reasoning')
        'reasoning templates must have reasoning mode',
      if (parameters.pathRelationTypes.last != template.relationType)
        'the final path relation must be the template relation type',
      for (final type in parameters.pathRelationTypes) ...[
        if (!relationTypes.contains(type))
          'path_relation_types names unknown relation $type',
        if (_starType(type) || type == contradictionRelationType)
          '$type cannot establish a forward causal step',
      ],
      if (!relationTypes.contains(contradictionRelationType))
        'reasoning needs the explicit CONTRADICTS relation type',
      if (template.promptTemplate
          .replaceAll('{subject.name}', '')
          .contains(RegExp(r'[{}]')))
        'reasoning prompts may name only {subject.name}',
      if (!template.promptTemplate.contains('{') &&
          parameters.scopeNodeIds?.length != 1)
        'a fixed reasoning prompt needs exactly one starting scope_node_id',
    ];
  }

  /// Checks referenced nodes/items and scoped negative evidence before ingest.
  /// The root validator can report each returned problem with the template ID.
  static List<String> templateReferenceProblems(
    CurriculumDataset dataset,
    QuestionTemplate template, {
    required String on,
  }) {
    final structural = templateProblems(
      template,
      relationTypes: dataset.relationTypes.map((r) => r.id).toSet(),
    );
    if (structural.isNotEmpty) {
      return structural;
    }
    final graph = _ReasoningGraph.fromDataset(dataset, on);
    return _resolve(graph, template).diagnostics;
  }

  /// A pure in-memory counterpart useful to dataset validators and fixtures.
  static ReasoningPathResult inspectDataset(
    CurriculumDataset dataset,
    QuestionTemplate template, {
    required String on,
  }) {
    return _resolve(_ReasoningGraph.fromDataset(dataset, on), template);
  }

  Future<ReasoningPathResult> enumerate(
    QuestionTemplate template, {
    required String on,
    Set<String>? eligibleItemIds,
  }) async {
    final graph = await _ReasoningGraph.fromDatabase(db, on);
    return _resolve(graph, template, eligibleItemIds: eligibleItemIds);
  }

  /// Existing pools that still have a complete cited path and three evidenced
  /// contrasts on [on]. Planner and coverage use this before track filtering.
  /// One graph snapshot and one enumeration per template avoid per-pool reads.
  Future<Set<int>> validPoolIds({required String on}) async {
    final graph = await _ReasoningGraph.fromDatabase(db, on);
    final templates = {
      for (final template in await db.select(db.questionTemplates).get())
        if (template.mode == 'reasoning') template.id: template,
    };
    final members = <int, List<ExercisePoolItem>>{};
    for (final member in await db.select(db.exercisePoolItems).get()) {
      members.putIfAbsent(member.exercisePoolId, () => []).add(member);
    }
    final enumerations = <String, ReasoningPathResult>{};
    final valid = <int>{};
    for (final pool in await db.select(db.exercisePools).get()) {
      final template = templates[pool.questionTemplateId];
      if (template == null || pool.scopeNodeId == null) {
        continue;
      }
      final ordered = [...(members[pool.id] ?? const <ExercisePoolItem>[])]
        ..sort((a, b) => (a.rank ?? 0).compareTo(b.rank ?? 0));
      if (ordered.length < 2 ||
          ordered.length > 3 ||
          ordered.map((m) => m.knowledgeItemId).toSet().length !=
              ordered.length ||
          ordered.indexed.any((pair) => pair.$2.rank != pair.$1 + 1)) {
        continue;
      }
      final result = enumerations.putIfAbsent(
        template.id,
        () => _resolve(graph, template),
      );
      if (result.paths.any(
        (path) =>
            path.premiseNodeId == pool.scopeNodeId &&
            path.items.length == ordered.length &&
            path.items.indexed.every(
              (pair) => pair.$2.id == ordered[pair.$1].knowledgeItemId,
            ),
      )) {
        valid.add(pool.id);
      }
    }
    return Set<int>.unmodifiable(valid);
  }

  static ReasoningPathResult _resolve(
    _ReasoningGraph graph,
    QuestionTemplate template, {
    Set<String>? eligibleItemIds,
  }) {
    final problems = templateProblems(
      template,
      relationTypes: graph.relationTypes,
    );
    if (problems.isNotEmpty) {
      return ReasoningPathResult(paths: const [], diagnostics: problems);
    }
    final parameters = ReasoningParameters.parse(template),
        diagnostics = <String>[];
    final available = <KnowledgeItem>[];
    for (final item in graph.items.values.where(
      (i) => graph.cited.contains(i.id),
    )) {
      if (!graph.nodes.containsKey(item.subjectId) ||
          !graph.nodes.containsKey(item.objectId)) {
        diagnostics.add('reasoning item ${item.id} has an unknown chain node');
      } else {
        available.add(item);
      }
    }
    available.sort((a, b) => a.id.compareTo(b.id));
    final assessed = available
        .where((i) => eligibleItemIds == null || eligibleItemIds.contains(i.id))
        .toList();
    final candidates = <List<KnowledgeItem>>[];
    void extend(List<KnowledgeItem> chain, Set<String> nodes) {
      if (chain.length == parameters.pathRelationTypes.length) {
        candidates.add(List.unmodifiable(chain));
        return;
      }
      final subject = chain.last.objectId,
          type = parameters.pathRelationTypes[chain.length];
      for (final next in assessed.where(
        (i) => i.subjectId == subject && i.relationType == type,
      )) {
        if (nodes.contains(next.objectId) ||
            chain.any((i) => i.id == next.id)) {
          diagnostics.add('cyclic reasoning path at ${next.id}');
          continue;
        }
        extend([...chain, next], {...nodes, next.objectId});
      }
    }

    for (final first in assessed.where(
      (i) =>
          i.relationType == parameters.pathRelationTypes.first &&
          (parameters.scopeNodeIds == null ||
              parameters.scopeNodeIds!.contains(i.subjectId)),
    )) {
      if (first.subjectId == first.objectId) {
        diagnostics.add('cyclic reasoning path at ${first.id}');
      } else {
        extend([first], {first.subjectId, first.objectId});
      }
    }
    for (final scope in parameters.scopeNodeIds ?? <String>{}) {
      if (!graph.nodes.containsKey(scope)) {
        diagnostics.add('unknown starting scope node $scope');
      }
    }
    // Validate every authored contrast, including references unused by a path.
    for (final target in parameters.contrasts.entries) {
      final targetItem = graph.items[target.key];
      if (targetItem == null || !graph.cited.contains(target.key)) {
        diagnostics.add(
          'contrast target ${target.key} is not a current cited item',
        );
      } else if (targetItem.relationType != template.relationType) {
        diagnostics.add(
          'contrast target ${target.key} has the wrong final relation',
        );
      }
      for (final start in target.value.entries) {
        if (!graph.nodes.containsKey(start.key)) {
          diagnostics.add('unknown contrast premise ${start.key}');
        }
        if (parameters.scopeNodeIds != null &&
            !parameters.scopeNodeIds!.contains(start.key)) {
          diagnostics.add(
            'contrast premise ${start.key} is outside starting scope',
          );
        }
        if (!candidates.any(
          (c) => c.first.subjectId == start.key && c.last.id == target.key,
        )) {
          diagnostics.add(
            'contrast target ${target.key} has no complete cited path from ${start.key}',
          );
        }
        final seen = <String>{};
        for (final contrast in start.value) {
          if (!seen.add(contrast.optionNodeId)) {
            diagnostics.add(
              'duplicate contrast option ${contrast.optionNodeId}',
            );
          }
          final problem = _contrastProblem(
            graph,
            contrast,
            start.key,
            targetItem?.objectId,
          );
          if (problem != null) {
            diagnostics.add(problem);
          }
        }
      }
    }
    final conclusions = <String, Set<String>>{};
    for (final chain in candidates) {
      conclusions
          .putIfAbsent(chain.first.subjectId, () => {})
          .add(chain.last.objectId);
    }
    final paths = <ReasoningPath>[];
    for (final chain in candidates) {
      final start = chain.first.subjectId, target = chain.last;
      if (conclusions[start]!.length != 1) {
        diagnostics.add('ambiguous conclusions from premise $start');
        continue;
      }
      final authored =
          parameters.contrasts[target.id]?[start] ??
          const <ReasoningContrast>[];
      final valid = <ReasoningContrast>[], ids = <String>{}, names = <String>{};
      for (final contrast in authored) {
        if (_contrastProblem(graph, contrast, start, target.objectId) != null) {
          continue;
        }
        final name = normalizeName(graph.nodes[contrast.optionNodeId]!.name);
        if (!ids.add(contrast.optionNodeId) || !names.add(name)) {
          continue;
        }
        valid.add(contrast);
      }
      if (valid.length < 3) {
        diagnostics.add(
          '${target.id} from $start needs three distinct evidenced wrong options',
        );
        continue;
      }
      paths.add(
        ReasoningPath(
          premiseNodeId: start,
          items: List.unmodifiable(chain),
          contrasts: List.unmodifiable(valid),
        ),
      );
    }
    return ReasoningPathResult(
      paths: List.unmodifiable(paths),
      diagnostics: List.unmodifiable(diagnostics.toSet()),
    );
  }

  static String? _contrastProblem(
    _ReasoningGraph graph,
    ReasoningContrast contrast,
    String premise,
    String? answer,
  ) {
    final option = graph.nodes[contrast.optionNodeId];
    if (option == null) {
      return 'unknown contrast option ${contrast.optionNodeId}';
    }
    if (answer != null && !graph.nodes.containsKey(answer)) {
      return 'unknown correct answer node $answer';
    }
    if (contrast.optionNodeId == answer ||
        (answer != null &&
            normalizeName(option.name) ==
                normalizeName(graph.nodes[answer]!.name))) {
      return 'contrast option ${contrast.optionNodeId} duplicates the correct answer';
    }
    for (final id in contrast.evidenceItemIds) {
      if (!graph.items.containsKey(id) || !graph.cited.contains(id)) {
        return 'contrast evidence $id is not a current cited item';
      }
    }
    if (!contrast.evidenceItemIds.any((id) {
      final item = graph.items[id]!;
      return item.subjectId == premise &&
          item.objectId == contrast.optionNodeId &&
          item.relationType == contradictionRelationType;
    })) {
      return 'contrast ${contrast.optionNodeId} lacks a cited CONTRADICTS edge from premise $premise';
    }
    return null;
  }
}

final class _ReasoningGraph {
  const _ReasoningGraph({
    required this.nodes,
    required this.items,
    required this.cited,
    required this.relationTypes,
  });
  final Map<String, KnowledgeNode> nodes;
  final Map<String, KnowledgeItem> items;
  final Set<String> cited;
  final Set<String> relationTypes;

  static _ReasoningGraph fromDataset(CurriculumDataset dataset, String on) {
    final edges = {
      for (final r in dataset.knowledgeRelations)
        if (r.validFrom.compareTo(on) <= 0 &&
            (r.validUntil == null || r.validUntil!.compareTo(on) > 0))
          '${r.subjectId}/${r.relationType}/${r.objectId}',
    };
    final sources = dataset.sourceCitations.map((s) => s.id).toSet();
    return _ReasoningGraph(
      nodes: {for (final n in dataset.knowledgeNodes) n.id: n},
      items: {
        for (final i in dataset.knowledgeItems)
          if (i.supersededByItemId == null &&
              edges.contains('${i.subjectId}/${i.relationType}/${i.objectId}'))
            i.id: i,
      },
      cited: {
        for (final c in dataset.knowledgeItemCitations)
          if (sources.contains(c.sourceCitationId)) c.knowledgeItemId,
      },
      relationTypes: dataset.relationTypes.map((r) => r.id).toSet(),
    );
  }

  static Future<_ReasoningGraph> fromDatabase(AppDatabase db, String on) async {
    final items = await KnowledgeGraph(db).currentItems(on: on);
    final sources = (await db.select(db.sourceCitations).get())
        .map((s) => s.id)
        .toSet();
    return _ReasoningGraph(
      nodes: {
        for (final n in await db.select(db.knowledgeNodes).get()) n.id: n,
      },
      items: {for (final i in items) i.id: i},
      cited: {
        for (final c in await db.select(db.knowledgeItemCitations).get())
          if (sources.contains(c.sourceCitationId)) c.knowledgeItemId,
      },
      relationTypes: (await db.select(db.relationTypes).get())
          .map((r) => r.id)
          .toSet(),
    );
  }
}
