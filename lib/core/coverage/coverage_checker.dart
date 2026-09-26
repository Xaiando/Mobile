import 'package:drift/drift.dart';

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';
import '../questions/question_generator.dart';
import '../study/study_planner.dart';
import 'coverage_formats.dart';
import 'coverage_model.dart';
import 'coverage_policy.dart';

/// Measures which items each track can test, and with which formats
/// (question-system §8, backlog F1).
///
/// It reads an ingested database. The questions that ingestion generated are
/// the formats available, and a track serves them as the study planner does
/// (CM-3, CM-6, A-10). Every item in force that the track maps is counted,
/// by domain and by area; items the track does not map are not (CM-4).
final class CoverageChecker {
  CoverageChecker(this.db, this.policy);

  final AppDatabase db;
  final CoveragePolicy policy;

  /// Where the policy does not fit the curriculum in the database
  /// ([CoveragePolicy.problemsWith]). Empty when they agree.
  Future<List<String>> policyProblems() async => policy.problemsWith(
    relationTypes: {
      for (final type in await db.select(db.relationTypes).get()) type.id,
    },
    domains: {
      for (final domain in await db.select(db.curriculumDomains).get())
        domain.id,
    },
    tracks: {
      for (final track in await db.select(db.certifications).get()) track.id,
    },
    nodes: {
      for (final node in await (db.select(
        db.knowledgeNodes,
      )..where((n) => n.id.isIn(policy.regionalCountries))).get())
        node.id,
    },
  );

  /// The tracks a learner can select, by organization and level.
  Future<List<Certification>> selectableTracks() =>
      (db.select(db.certifications)
            ..where((c) => c.isSelectable.equals(true))
            ..orderBy([
              (c) => OrderingTerm(expression: c.organization),
              (c) => OrderingTerm(expression: c.level),
            ]))
          .get();

  /// The coverage of [trackId] on [on], `YYYY-MM-DD`: the date ingestion
  /// generated the questions for.
  ///
  /// [skipped] is the generation report's list of skipped questions. It
  /// says why an expected format is missing, e.g. too few distractors.
  ///
  /// Throws a [CoveragePolicyException] if the policy does not fit the
  /// curriculum.
  Future<TrackCoverage> check(
    String trackId, {
    required String on,
    Iterable<SkippedQuestion> skipped = const [],
  }) async {
    final problems = await policyProblems();
    if (problems.isNotEmpty) throw CoveragePolicyException(problems);
    final track = await (db.select(
      db.certifications,
    )..where((c) => c.id.equals(trackId))).getSingleOrNull();
    if (track == null) {
      throw ArgumentError.value(trackId, 'trackId', 'is not a track');
    }

    final mappings = await StudyPlanner(db).effectiveMappings(trackId);
    final generated = await _formatsByItem();
    final templates = await db.select(db.questionTemplates).get();
    final modesOf = <String, Set<String>>{};
    final pooledModes = <String>{};
    for (final template in templates) {
      modesOf.putIfAbsent(template.relationType, () => {}).add(template.mode);
      if (builtFormats[template.mode]?.isPooled ?? false) {
        pooledModes.add(template.mode);
      }
    }
    final whySkipped = _skipReasons(skipped, {
      for (final template in templates) template.id: template.mode,
    });
    final areas = await _Areas.load(db, policy, on);

    final items = <ItemCoverage>[];
    for (final item in await KnowledgeGraph(db).currentItems(on: on)) {
      final mapping = mappings[item.id];
      if (mapping == null) continue;
      final available = generated[item.id] ?? const <QuestionFormat>[];
      final expected =
          policy.capabilities[item.relationType]?.supports ?? const {};
      final present = {for (final format in available) format.mode};
      items.add(
        ItemCoverage(
          item: item,
          mapping: mapping,
          area: await areas.of(item.subjectId),
          generated: available,
          served: available.isEmpty
              ? const []
              : StudyPlanner.servedFormats(available, mapping.minimumDepth),
          expected: expected,
          missing: {
            for (final format in builtFormats.keys)
              if (expected.contains(format) && !present.contains(format))
                format: _whyMissing(
                  item,
                  format,
                  modesOf[item.relationType] ?? const {},
                  whySkipped[item.id]?[format],
                  pooledModes: pooledModes,
                ),
          },
          subjectType: areas.typeOf(item.subjectId),
          objectType: areas.typeOf(item.objectId),
          places: await areas.placesOf(item.subjectId),
        ),
      );
    }

    final counts = CoverageCounts();
    final byDomain = <String, DomainCoverage>{};
    final domainNames = {
      for (final domain in await (db.select(
        db.curriculumDomains,
      )..orderBy([(d) => OrderingTerm(expression: d.position)])).get())
        domain.id: domain.displayName,
    };
    for (final item in items) {
      counts.count(item);
      final id = item.item.domainId;
      final domain = byDomain.putIfAbsent(
        id,
        () => DomainCoverage(id, domainNames[id] ?? id),
      );
      domain.counts.count(item);
      domain.areas.putIfAbsent(item.area, CoverageCounts.new).count(item);
    }
    final domains = [for (final id in domainNames.keys) ?byDomain[id]];
    for (final domain in domains) {
      final sorted = domain.areas.entries.toList()
        ..sort((a, b) {
          final order = a.key.name.compareTo(b.key.name);
          return order != 0 ? order : a.key.id.compareTo(b.key.id);
        });
      domain.areas
        ..clear()
        ..addEntries(sorted);
    }

    return TrackCoverage(
      trackId: trackId,
      trackName: track.displayName,
      on: on,
      items: items,
      counts: counts,
      domains: domains,
      gaps: _gaps(items),
      thresholds: [
        for (final threshold in policy.thresholdsFor(trackId).values)
          ThresholdResult(
            threshold: threshold,
            value: counts[threshold.metric],
            base: counts[threshold.metric.base],
          ),
        for (final domain in domains)
          for (final threshold
              in policy.thresholdsFor(trackId, domain.id).values)
            ThresholdResult(
              domainId: domain.id,
              threshold: threshold,
              value: domain.counts[threshold.metric],
              base: domain.counts[threshold.metric.base],
            ),
      ],
    );
  }

  /// Each item's gaps: at most one of untestable, flashcard-only and core
  /// without useful practice, then its missing formats.
  static List<CoverageGap> _gaps(List<ItemCoverage> items) {
    final gaps = <CoverageGap>[];
    for (final item in items) {
      String missing(bool Function(String format) include) => [
        for (final MapEntry(key: format, value: reason) in item.missing.entries)
          if (include(format)) '$format: $reason',
      ].join('; ');

      if (!item.isTestable) {
        final why = missing((_) => true);
        gaps.add(
          CoverageGap(
            GapKind.untestable,
            item,
            why.isEmpty ? 'the policy expects no format for it' : why,
          ),
        );
      } else if (item.isFlashcardOnly) {
        final why = missing((f) => builtFormats[f]?.isObjective ?? false);
        gaps.add(
          CoverageGap(
            GapKind.flashcardOnly,
            item,
            why.isEmpty ? 'the policy expects no objective format' : why,
          ),
        );
      } else if (item.isCore && !item.hasUsefulPractice) {
        final families = [for (final family in item.families) family.name];
        gaps.add(
          CoverageGap(
            GapKind.noUsefulPractice,
            item,
            'served ${item.servedFormats.join(', ')} '
            '(${families.join(', ')}) at depth ${item.mapping.minimumDepth}',
          ),
        );
      }
      for (final MapEntry(key: format, value: reason) in item.missing.entries) {
        gaps.add(
          CoverageGap(GapKind.missingFormat, item, reason, format: format),
        );
      }
    }
    return gaps..sort((a, b) {
      var order = a.kind.index.compareTo(b.kind.index);
      if (order == 0) order = a.itemId.compareTo(b.itemId);
      return order != 0 ? order : (a.format ?? '').compareTo(b.format ?? '');
    });
  }

  /// Why [item] has no question in [format], a format its relation type's
  /// policy expects. [modes] are the formats of the type's templates. A
  /// pooled format's template gathers items of several relation types, so
  /// for the formats in [pooledModes] the item is simply in no pool.
  static String _whyMissing(
    KnowledgeItem item,
    String format,
    Set<String> modes,
    SkipReason? skip, {
    Set<String> pooledModes = const {},
  }) {
    if (pooledModes.contains(format)) return 'in no $format pool';
    if (!modes.contains(format)) {
      return 'no $format template for ${item.relationType}';
    }
    return switch (skip) {
      SkipReason.mcqDisabled => 'mcq_disabled',
      SkipReason.tooFewDistractors => 'too few distractors',
      SkipReason.notReverseSafe => 'not reverse-safe',
      SkipReason.notEligible => 'the format cannot ask it',
      null => 'not generated',
    };
  }

  /// The generation report's reasons, by item and format. A reason that
  /// applies to a forward question wins over "not reverse-safe", which only
  /// ever stops the reverse one.
  static Map<String, Map<String, SkipReason>> _skipReasons(
    Iterable<SkippedQuestion> skipped,
    Map<String, String> modeOf,
  ) {
    final reasons = <String, Map<String, SkipReason>>{};
    for (final skip in skipped) {
      final mode = modeOf[skip.templateId];
      if (mode == null) continue;
      final byMode = reasons.putIfAbsent(skip.itemId, () => {});
      final known = byMode[mode];
      if (known == null || known == SkipReason.notReverseSafe) {
        byMode[mode] = skip.reason;
      }
    }
    return reasons;
  }

  /// Every question's format, by item, and every pooled format an item's
  /// pools give it, as the planner serves them.
  Future<Map<String, List<QuestionFormat>>> _formatsByItem() async {
    final rows = await db
        .customSelect(
          '''
      SELECT q.knowledge_item_id, q.question_template_id, t.direction, t.mode
      FROM questions q
      JOIN question_templates t ON t.id = q.question_template_id
      UNION
      SELECT i.knowledge_item_id, p.question_template_id, t.direction, t.mode
      FROM exercise_pool_items i
      JOIN exercise_pools p ON p.id = i.exercise_pool_id
      JOIN question_templates t ON t.id = p.question_template_id
      ORDER BY 1, 2''',
          readsFrom: {
            db.questions,
            db.questionTemplates,
            db.exercisePools,
            db.exercisePoolItems,
          },
        )
        .get();
    final formats = <String, List<QuestionFormat>>{};
    for (final row in rows) {
      formats
          .putIfAbsent(row.read<String>('knowledge_item_id'), () => [])
          .add(
            QuestionFormat(
              questionTemplateId: row.read<String>('question_template_id'),
              direction: row.read<String>('direction'),
              mode: row.read<String>('mode'),
            ),
          );
    }
    return formats;
  }
}

/// Finds the area of a subject (question-system §8).
final class _Areas {
  _Areas._(
    this._graph,
    this._policy,
    this._on,
    this._nodes,
    this._typeLabels,
    this._places,
    this._placed,
  );

  static Future<_Areas> load(
    AppDatabase db,
    CoveragePolicy policy,
    String on,
  ) async {
    final signatures = await (db.select(
      db.relationTypeSignatures,
    )..where((s) => s.relationType.equals('LOCATED_IN'))).get();
    return _Areas._(
      KnowledgeGraph(db),
      policy,
      on,
      {
        for (final node in await db.select(db.knowledgeNodes).get())
          node.id: node,
      },
      {
        for (final type in await db.select(db.nodeTypes).get())
          type.id: type.label,
      },
      {
        for (final s in signatures) ...[s.subjectNodeType, s.objectNodeType],
      },
      {for (final s in signatures) s.subjectNodeType},
    );
  }

  final KnowledgeGraph _graph;
  final CoveragePolicy _policy;
  final String _on;
  final Map<String, KnowledgeNode> _nodes;
  final Map<String, String> _typeLabels;

  /// The node types of places: either end of a `LOCATED_IN` signature.
  final Set<String> _places;

  /// The node types of places that lie inside another place.
  final Set<String> _placed;

  final _cache = <String, CoverageArea>{};
  final _ancestors = <String, List<GraphNode>>{};

  Future<CoverageArea> of(String nodeId) async =>
      _cache[nodeId] ??= await _find(nodeId);

  /// The node type of [nodeId].
  String typeOf(String nodeId) => _nodes[nodeId]!.nodeType;

  /// [nodeId] and every place that contains it.
  Future<Set<String>> placesOf(String nodeId) async => {
    nodeId,
    for (final ancestor in await _ancestorsOf(nodeId)) ancestor.id,
  };

  Future<List<GraphNode>> _ancestorsOf(String nodeId) async =>
      _ancestors[nodeId] ??= await _graph.ancestors(nodeId, on: _on);

  /// A place's country, or its region in a regional country. A place that
  /// should lie in another but reaches no top-level place is unplaced. A
  /// subject that is not a place is counted under its node type.
  Future<CoverageArea> _find(String nodeId) async {
    final node = _nodes[nodeId]!;
    if (!_places.contains(node.nodeType)) {
      return CoverageArea.ofType(
        node.nodeType,
        _typeLabels[node.nodeType] ?? node.nodeType,
      );
    }
    final ancestors = await _ancestorsOf(nodeId);
    if (ancestors.isEmpty) {
      return _placed.contains(node.nodeType)
          ? CoverageArea.unplaced
          : CoverageArea(node.id, node.name);
    }
    // Nearest first, then by name: the first of the farthest wins a tie.
    var top = ancestors.first;
    for (final ancestor in ancestors) {
      if (ancestor.depth > top.depth) top = ancestor;
    }
    if (_placed.contains(top.nodeType)) return CoverageArea.unplaced;
    if (!_policy.regionalCountries.contains(top.id)) {
      return CoverageArea(top.id, top.name);
    }
    if (top.depth == 1) return CoverageArea(node.id, node.name);
    final region = ancestors.firstWhere((a) => a.depth == top.depth - 1);
    return CoverageArea(region.id, region.name);
  }
}
