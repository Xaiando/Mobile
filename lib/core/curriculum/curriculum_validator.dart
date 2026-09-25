import 'package:drift/drift.dart' show DataClass;

import '../coverage/coverage_formats.dart';
import '../database/app_database.dart';
import 'curriculum_dataset.dart';

/// Relation types that state wine law. Their items need a `legislation` or
/// `regulator_register` citation (architecture audit PR-3).
const regulatoryRelationTypes = {
  'PERMITS_PRINCIPAL_GRAPE',
  'PERMITS_ACCESSORY_GRAPE',
  'MIN_AGEING',
  'MIN_WOOD_AGEING',
  'REQUIRES_METHOD',
};

/// The `valid_from` recorded while a fact's real effective date is not
/// curated yet. The fact is treated as in force.
const uncuratedEffectiveDate = '1900-01-01';

/// The placeholders a question template may use (architecture audit QG-2).
const templatePlaceholders = {
  '{subject.name}',
  '{object.name}',
  '{object.type_label}',
};

/// A broken dataset rule.
class ValidationIssue {
  const ValidationIssue(
    this.rule,
    this.message, {
    this.isError = true,
    this.row,
  });

  /// A short rule name, e.g. `dangling-relation`.
  final String rule;
  final String message;

  /// Errors block ingestion; warnings go to the build report.
  final bool isError;

  /// The row the issue is about, when it is about one. The dataset locates
  /// it in its files ([CurriculumDataset.locate]).
  final DatasetRowRef? row;

  @override
  String toString() => '$rule: $message';
}

class ValidationReport {
  const ValidationReport(this.issues);

  final List<ValidationIssue> issues;

  List<ValidationIssue> get errors => [
    for (final issue in issues)
      if (issue.isError) issue,
  ];

  List<ValidationIssue> get warnings => [
    for (final issue in issues)
      if (!issue.isError) issue,
  ];

  bool get isValid => errors.isEmpty;
}

/// Checks the rules that span rows (architecture audit §3.3, spec §S.1–§S.2).
///
/// The database enforces single-row rules as constraints; checking them here
/// too gives one readable report before anything is written.
ValidationReport validateDataset(CurriculumDataset dataset) =>
    ValidationReport(_Validator(dataset).run());

class _Validator {
  _Validator(this.d);

  final CurriculumDataset d;
  final issues = <ValidationIssue>[];

  late final domains = {for (final r in d.curriculumDomains) r.id};
  late final grids = {for (final r in d.tastingGrids) r.id};
  late final certifications = {for (final r in d.certifications) r.id: r};
  late final nodeTypes = {for (final r in d.nodeTypes) r.id};
  late final relationTypes = {for (final r in d.relationTypes) r.id: r};
  late final nodes = {for (final r in d.knowledgeNodes) r.id: r};
  late final items = {for (final r in d.knowledgeItems) r.id: r};
  late final citations = {for (final r in d.sourceCitations) r.id: r};
  late final relations = {for (final r in d.knowledgeRelations) _triple(r): r};
  late final layers = {for (final r in d.mapLayers) r.id: r};

  static String _triple(KnowledgeRelation r) =>
      '${r.subjectId} ${r.relationType} ${r.objectId}';

  void error(String rule, String message, {DatasetRowRef? row}) =>
      issues.add(ValidationIssue(rule, message, row: row));

  void warning(String rule, String message, {DatasetRowRef? row}) =>
      issues.add(ValidationIssue(rule, message, isError: false, row: row));

  static DatasetRowRef _ref(String section, DataClass row) =>
      (section: section, key: rowKey(section, row));

  List<ValidationIssue> run() {
    _uniqueKeys();
    _identifiers();
    _references();
    _signatures();
    _cycles();
    _certificationChains();
    _cardinality();
    _symmetry();
    _quantities();
    _provenance();
    _completeness();
    _mapLayers();
    _templates();
    _report();
    return issues;
  }

  void _unique<R extends DataClass>(
    String table,
    Iterable<R> rows,
    Object Function(R) key,
  ) {
    final seen = <Object>{};
    for (final row in rows) {
      final k = key(row);
      if (!seen.add(k)) {
        error(
          'duplicate-key',
          '$table: $k appears twice',
          row: _ref(table, row),
        );
      }
    }
  }

  void _uniqueKeys() {
    _unique('curriculum_domains', d.curriculumDomains, (r) => r.id);
    _unique('curriculum_domains', d.curriculumDomains, (r) => r.position);
    _unique('tasting_grids', d.tastingGrids, (r) => r.id);
    _unique('certifications', d.certifications, (r) => r.id);
    _unique(
      'certifications',
      d.certifications.where((r) => r.organization != null),
      (r) => '${r.organization} level ${r.level}',
    );
    _unique('node_types', d.nodeTypes, (r) => r.id);
    _unique('relation_types', d.relationTypes, (r) => r.id);
    _unique(
      'relation_type_signatures',
      d.relationTypeSignatures,
      (r) => '${r.relationType} ${r.subjectNodeType} ${r.objectNodeType}',
    );
    _unique('knowledge_nodes', d.knowledgeNodes, (r) => r.id);
    _unique('quantity_values', d.quantityValues, (r) => r.knowledgeNodeId);
    _unique(
      'node_alternative_names',
      d.nodeAlternativeNames,
      (r) => '${r.knowledgeNodeId} "${r.nameNorm}"',
    );
    _unique('knowledge_relations', d.knowledgeRelations, _triple);
    _unique('knowledge_items', d.knowledgeItems, (r) => r.id);
    _unique(
      'knowledge_items',
      d.knowledgeItems,
      (r) => 'an item for ${r.subjectId} ${r.relationType} ${r.objectId}',
    );
    _unique(
      'knowledge_item_prerequisites',
      d.knowledgeItemPrerequisites,
      (r) => '${r.knowledgeItemId} -> ${r.prerequisiteItemId}',
    );
    _unique(
      'certification_knowledge_mappings',
      d.certificationKnowledgeMappings,
      (r) => '${r.certificationId} ${r.knowledgeItemId}',
    );
    _unique('source_citations', d.sourceCitations, (r) => r.id);
    _unique('source_citations', [
      for (final r in d.sourceCitations)
        if (r.url != null) r,
    ], (r) => r.url!);
    _unique(
      'knowledge_item_citations',
      d.knowledgeItemCitations,
      (r) => '${r.knowledgeItemId} ${r.sourceCitationId}',
    );
    _unique('question_templates', d.questionTemplates, (r) => r.id);
    _unique(
      'question_templates',
      d.questionTemplates,
      (r) =>
          '${r.relationType} ${r.direction} ${r.mode}'
          '${r.variant.isEmpty ? '' : ' (${r.variant})'} ${r.locale}',
    );
    _unique(
      'relation_set_assertions',
      d.relationSetAssertions,
      (r) =>
          '${r.nodeId} ${r.relationType} ${r.direction} '
          '${r.memberNodeType} from ${r.validFrom}',
    );
    _unique('map_layers', d.mapLayers, (r) => r.id);
    _unique('map_layers', d.mapLayers, (r) => r.assetPath);
    _unique(
      'map_layer_citations',
      d.mapLayerCitations,
      (r) => '${r.mapLayerId} ${r.sourceCitationId}',
    );
    _unique(
      'map_layer_citations',
      d.mapLayerCitations,
      (r) => '${r.mapLayerId} position ${r.position}',
    );
    _unique(
      'node_geometries',
      d.nodeGeometries,
      (r) => '${r.knowledgeNodeId} in ${r.mapLayerId}',
    );
    _unique(
      'node_geometries',
      d.nodeGeometries,
      (r) => '${r.mapLayerId} feature ${r.featureKey}',
    );

    // Normalized names are the matching key: near-duplicates are errors.
    final names = <String, String>{};
    for (final node in d.knowledgeNodes) {
      final other = names['${node.nodeType} ${node.nameNorm}'];
      if (other != null) {
        error(
          'name-norm',
          '${node.id} and $other are both ${node.nodeType} '
              '"${node.nameNorm}"',
          row: _ref('knowledge_nodes', node),
        );
      }
      names['${node.nodeType} ${node.nameNorm}'] = node.id;
    }
  }

  void _identifiers() {
    void check<R extends DataClass>(
      String table,
      Iterable<R> rows,
      String Function(R) id,
      RegExp pattern,
    ) {
      for (final row in rows) {
        if (!pattern.hasMatch(id(row))) {
          error(
            'id-format',
            '$table: "${id(row)}" does not match ${pattern.pattern}',
            row: _ref(table, row),
          );
        }
      }
    }

    check(
      'curriculum_domains',
      d.curriculumDomains,
      (r) => r.id,
      RegExp(r'^[a-z_]+$'),
    );
    check(
      'tasting_grids',
      d.tastingGrids,
      (r) => r.id,
      RegExp(r'^tg_[a-z0-9_]+$'),
    );
    check(
      'certifications',
      d.certifications,
      (r) => r.id,
      RegExp(r'^[A-Z0-9_]+$'),
    );
    check('node_types', d.nodeTypes, (r) => r.id, RegExp(r'^[a-z_]+$'));
    check('relation_types', d.relationTypes, (r) => r.id, RegExp(r'^[A-Z_]+$'));
    check(
      'knowledge_nodes',
      d.knowledgeNodes,
      (r) => r.id,
      RegExp(r'^n_[a-z0-9_]+$'),
    );
    check(
      'knowledge_items',
      d.knowledgeItems,
      (r) => r.id,
      RegExp(r'^ki_[a-z0-9_]+$'),
    );
    check(
      'source_citations',
      d.sourceCitations,
      (r) => r.id,
      RegExp(r'^src_[a-z0-9_]+$'),
    );
    check(
      'question_templates',
      d.questionTemplates,
      (r) => r.id,
      RegExp(r'^qt_[a-z0-9_]+$'),
    );
    check(
      'question_templates',
      d.questionTemplates,
      (r) => r.variant,
      RegExp(r'^[a-z0-9_]*$'),
    );
    check('map_layers', d.mapLayers, (r) => r.id, RegExp(r'^ml_[a-z0-9_]+$'));
  }

  void _references() {
    void refer(
      String where,
      String? id,
      Iterable<String> targets,
      String to,
      DatasetRowRef row,
    ) {
      if (id != null && !targets.contains(id)) {
        error(
          'unknown-reference',
          '$where refers to unknown $to "$id"',
          row: row,
        );
      }
    }

    for (final c in d.certifications) {
      final row = _ref('certifications', c);
      refer(
        'certification ${c.id}',
        c.includesCertificationId,
        certifications.keys,
        'certification',
        row,
      );
      refer(
        'certification ${c.id}',
        c.defaultTastingGridId,
        grids,
        'tasting grid',
        row,
      );
    }
    for (final t in d.relationTypes) {
      final row = _ref('relation_types', t);
      refer('relation type ${t.id}', t.defaultDomainId, domains, 'domain', row);
      refer(
        'relation type ${t.id}',
        t.distractorMatchRelationType,
        relationTypes.keys,
        'relation type',
        row,
      );
    }
    for (final s in d.relationTypeSignatures) {
      final where = 'signature ${s.relationType}';
      final row = _ref('relation_type_signatures', s);
      refer(where, s.relationType, relationTypes.keys, 'relation type', row);
      refer(where, s.subjectNodeType, nodeTypes, 'node type', row);
      refer(where, s.objectNodeType, nodeTypes, 'node type', row);
    }
    for (final n in d.knowledgeNodes) {
      final row = _ref('knowledge_nodes', n);
      refer('node ${n.id}', n.nodeType, nodeTypes, 'node type', row);
      final from = n.validFrom, until = n.validUntil;
      if (from != null && until != null && until.compareTo(from) <= 0) {
        error('validity', 'node ${n.id} ends before it starts', row: row);
      }
    }
    for (final a in d.nodeAlternativeNames) {
      refer(
        'alternative name "${a.name}"',
        a.knowledgeNodeId,
        nodes.keys,
        'node',
        _ref('node_alternative_names', a),
      );
    }

    // §S.1: every relation must connect existing nodes.
    for (final r in d.knowledgeRelations) {
      final where = 'relation ${_triple(r)}';
      final row = _ref('knowledge_relations', r);
      for (final end in [r.subjectId, r.objectId]) {
        if (!nodes.containsKey(end)) {
          error(
            'dangling-relation',
            '$where refers to unknown node "$end"',
            row: row,
          );
        }
      }
      refer(where, r.relationType, relationTypes.keys, 'relation type', row);
      if (r.subjectId == r.objectId) {
        error('self-reference', '$where relates a node to itself', row: row);
      }
      final until = r.validUntil;
      if (until != null && until.compareTo(r.validFrom) <= 0) {
        error('validity', '$where ends before it starts', row: row);
      }
    }

    for (final i in d.knowledgeItems) {
      final where = 'item ${i.id}';
      final row = _ref('knowledge_items', i);
      final triple = '${i.subjectId} ${i.relationType} ${i.objectId}';
      if (!relations.containsKey(triple)) {
        error(
          'item-relation',
          '$where asserts $triple, which is no relation',
          row: row,
        );
      }
      refer(where, i.domainId, domains, 'domain', row);
      refer(where, i.supersededByItemId, items.keys, 'item', row);
      if (i.supersededByItemId == i.id) {
        error('self-reference', '$where supersedes itself', row: row);
      }
    }
    for (final p in d.knowledgeItemPrerequisites) {
      final where = 'prerequisite of ${p.knowledgeItemId}';
      final row = _ref('knowledge_item_prerequisites', p);
      refer(where, p.knowledgeItemId, items.keys, 'item', row);
      refer(where, p.prerequisiteItemId, items.keys, 'item', row);
    }
    for (final m in d.certificationKnowledgeMappings) {
      final where = 'mapping ${m.certificationId} ${m.knowledgeItemId}';
      final row = _ref('certification_knowledge_mappings', m);
      refer(
        where,
        m.certificationId,
        certifications.keys,
        'certification',
        row,
      );
      refer(where, m.knowledgeItemId, items.keys, 'item', row);
    }
    for (final c in d.knowledgeItemCitations) {
      final where = 'citation of ${c.knowledgeItemId}';
      final row = _ref('knowledge_item_citations', c);
      refer(where, c.knowledgeItemId, items.keys, 'item', row);
      refer(where, c.sourceCitationId, citations.keys, 'source citation', row);
    }
    for (final t in d.questionTemplates) {
      refer(
        'template ${t.id}',
        t.relationType,
        relationTypes.keys,
        'relation type',
        _ref('question_templates', t),
      );
    }
    for (final a in d.relationSetAssertions) {
      final where = 'completeness assertion ${_set(a)}';
      final row = _ref('relation_set_assertions', a);
      refer(where, a.nodeId, nodes.keys, 'node', row);
      refer(where, a.relationType, relationTypes.keys, 'relation type', row);
      refer(where, a.memberNodeType, nodeTypes, 'node type', row);
      refer(where, a.sourceCitationId, citations.keys, 'source citation', row);
      final until = a.validUntil;
      if (until != null && until.compareTo(a.validFrom) <= 0) {
        error('validity', '$where ends before it starts', row: row);
      }
    }
    for (final l in d.mapLayers) {
      refer(
        'map layer ${l.id}',
        l.parentLayerId,
        layers.keys,
        'map layer',
        _ref('map_layers', l),
      );
    }
    for (final c in d.mapLayerCitations) {
      final where = 'citation of map layer ${c.mapLayerId}';
      final row = _ref('map_layer_citations', c);
      refer(where, c.mapLayerId, layers.keys, 'map layer', row);
      refer(where, c.sourceCitationId, citations.keys, 'source citation', row);
    }
    for (final g in d.nodeGeometries) {
      final where = 'geometry of ${g.knowledgeNodeId} in ${g.mapLayerId}';
      final row = _ref('node_geometries', g);
      refer(where, g.knowledgeNodeId, nodes.keys, 'node', row);
      refer(where, g.mapLayerId, layers.keys, 'map layer', row);
    }
    final attributes = {
      for (final a in d.tastingGridAttributes)
        '${a.tastingGridId} ${a.attributeKey}',
    };
    for (final a in d.tastingGridAttributes) {
      refer(
        'grid attribute ${a.attributeKey}',
        a.tastingGridId,
        grids,
        'grid',
        _ref('tasting_grid_attributes', a),
      );
    }
    for (final v in d.tastingGridValues) {
      final where = 'grid value ${v.valueKey}';
      final row = _ref('tasting_grid_values', v);
      refer(
        where,
        '${v.tastingGridId} ${v.attributeKey}',
        attributes,
        'attribute',
        row,
      );
      refer(where, v.knowledgeNodeId, nodes.keys, 'node', row);
    }
  }

  void _signatures() {
    final allowed = {
      for (final s in d.relationTypeSignatures)
        '${s.relationType} ${s.subjectNodeType} ${s.objectNodeType}',
    };
    for (final r in d.knowledgeRelations) {
      final subject = nodes[r.subjectId], object = nodes[r.objectId];
      if (subject == null || object == null) continue;
      final signature =
          '${r.relationType} ${subject.nodeType} ${object.nodeType}';
      if (!allowed.contains(signature)) {
        error(
          'relation-signature',
          '${_triple(r)}: ${r.relationType} does not allow '
              '${subject.nodeType} -> ${object.nodeType}',
          row: _ref('knowledge_relations', r),
        );
      }
    }
  }

  void _cycles() {
    void check(String what, Map<String, List<String>> edges) {
      final cycle = findCycle(edges);
      if (cycle != null) error('cycle', '$what: ${cycle.join(' -> ')}');
    }

    // §S.2: no item may (transitively) be its own prerequisite.
    final prerequisites = <String, List<String>>{};
    for (final p in d.knowledgeItemPrerequisites) {
      if (p.knowledgeItemId == p.prerequisiteItemId) {
        error(
          'self-reference',
          '${p.knowledgeItemId} requires itself',
          row: _ref('knowledge_item_prerequisites', p),
        );
      }
      prerequisites
          .putIfAbsent(p.knowledgeItemId, () => [])
          .add(p.prerequisiteItemId);
    }
    check('prerequisite cycle', prerequisites);

    final containment = <String, List<String>>{};
    for (final r in d.knowledgeRelations) {
      if (r.relationType == 'LOCATED_IN') {
        containment.putIfAbsent(r.subjectId, () => []).add(r.objectId);
      }
    }
    check('LOCATED_IN cycle', containment);

    check('certification chain cycle', {
      for (final c in d.certifications)
        if (c.includesCertificationId != null)
          c.id: [c.includesCertificationId!],
    });
    check('map layer cycle', {
      for (final l in d.mapLayers)
        if (l.parentLayerId != null) l.id: [l.parentLayerId!],
    });
  }

  /// A certification has an examining body and a level, and includes only a
  /// lower level of its own body. A study pack has neither, and may include
  /// any track (PK-2).
  void _certificationChains() {
    for (final c in d.certifications) {
      final row = _ref('certifications', c);
      final isPack = c.kind == 'pack';
      if (isPack != (c.organization == null) || isPack != (c.level == null)) {
        error(
          'track-kind',
          isPack
              ? 'pack ${c.id} has an organization or a level; a pack has '
                    'neither'
              : 'certification ${c.id} needs an organization and a level',
          row: row,
        );
      }
      final included = certifications[c.includesCertificationId];
      if (included == null || isPack) continue;
      if (included.kind == 'pack') {
        error(
          'certification-chain',
          '${c.id} includes the pack ${included.id}',
          row: row,
        );
        continue;
      }
      if (included.organization != c.organization) {
        error(
          'certification-chain',
          '${c.id} includes ${included.id} from another organization',
          row: row,
        );
      }
      final (level, lower) = (c.level, included.level);
      if (level != null && lower != null && lower >= level) {
        error(
          'certification-chain',
          '${c.id} includes ${included.id}, which is not a lower level',
          row: row,
        );
      }
    }
  }

  /// A `cardinality = one` relation holds at most one object per subject at
  /// any date (architecture audit §9).
  void _cardinality() {
    final bySubject = <String, List<KnowledgeRelation>>{};
    for (final r in d.knowledgeRelations) {
      if (relationTypes[r.relationType]?.cardinality != 'one') continue;
      bySubject
          .putIfAbsent('${r.subjectId} ${r.relationType}', () => [])
          .add(r);
    }
    for (final group in bySubject.values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          if (_overlap(group[i], group[j])) {
            error(
              'cardinality-one',
              '${group[i].subjectId} has two ${group[i].relationType} '
                  'relations in force at once: ${group[i].objectId} and '
                  '${group[j].objectId}',
              row: _ref('knowledge_relations', group[j]),
            );
          }
        }
      }
    }
  }

  /// A symmetric relation holds both ways, so each pair is stored once, with
  /// the smaller node ID as its subject, and its type's signatures allow
  /// both directions.
  void _symmetry() {
    final allowed = {
      for (final s in d.relationTypeSignatures)
        '${s.relationType} ${s.subjectNodeType} ${s.objectNodeType}',
    };
    for (final s in d.relationTypeSignatures) {
      if (relationTypes[s.relationType]?.isSymmetric != true) continue;
      if (!allowed.contains(
        '${s.relationType} ${s.objectNodeType} ${s.subjectNodeType}',
      )) {
        error(
          'symmetric-relation',
          '${s.relationType} is symmetric, but allows ${s.subjectNodeType} '
              '-> ${s.objectNodeType} and not ${s.objectNodeType} -> '
              '${s.subjectNodeType}',
          row: _ref('relation_type_signatures', s),
        );
      }
    }
    for (final r in d.knowledgeRelations) {
      if (relationTypes[r.relationType]?.isSymmetric != true) continue;
      if (r.subjectId.compareTo(r.objectId) > 0) {
        error(
          'symmetric-relation',
          '${_triple(r)}: ${r.relationType} is symmetric, so the pair is '
              'stored once, as ${r.objectId} ${r.relationType} ${r.subjectId}',
          row: _ref('knowledge_relations', r),
        );
      }
    }
  }

  static bool _overlap(KnowledgeRelation a, KnowledgeRelation b) {
    // Periods are [valid_from, valid_until); a null end is open.
    bool before(String? end, String start) =>
        end != null && end.compareTo(start) <= 0;
    return !before(a.validUntil, b.validFrom) &&
        !before(b.validUntil, a.validFrom);
  }

  void _quantities() {
    final values = {for (final q in d.quantityValues) q.knowledgeNodeId: q};
    for (final node in d.knowledgeNodes) {
      if (node.nodeType == 'quantity' && !values.containsKey(node.id)) {
        error(
          'quantity',
          'quantity node ${node.id} has no quantity value',
          row: _ref('knowledge_nodes', node),
        );
      }
    }
    for (final q in d.quantityValues) {
      final row = _ref('quantity_values', q);
      final node = nodes[q.knowledgeNodeId];
      if (node != null && node.nodeType != 'quantity') {
        error(
          'quantity',
          '${q.knowledgeNodeId} has a quantity value but is a '
              '${node.nodeType}',
          row: row,
        );
      }
      final maximum = q.maximum;
      if (maximum != null && maximum < q.minimum) {
        error(
          'quantity',
          '${q.knowledgeNodeId}: maximum below minimum',
          row: row,
        );
      }
    }
  }

  /// Every item is cited and mapped to at least one track (§8, §7).
  void _provenance() {
    final cited = <String, List<SourceCitation>>{};
    for (final c in d.knowledgeItemCitations) {
      final source = citations[c.sourceCitationId];
      if (source != null) {
        cited.putIfAbsent(c.knowledgeItemId, () => []).add(source);
      }
    }
    final mapped = {
      for (final m in d.certificationKnowledgeMappings) m.knowledgeItemId,
    };
    for (final item in d.knowledgeItems) {
      final row = _ref('knowledge_items', item);
      final sources = cited[item.id] ?? const [];
      if (sources.isEmpty) {
        error('item-citation', '${item.id} cites no source', row: row);
      } else if (regulatoryRelationTypes.contains(item.relationType) &&
          !sources.any(
            (s) => s.kind == 'legislation' || s.kind == 'regulator_register',
          )) {
        error(
          'regulatory-citation',
          '${item.id} states wine law but cites no legislation or '
              'regulator register',
          row: row,
        );
      }
      if (!mapped.contains(item.id)) {
        error(
          'item-mapping',
          '${item.id} is mapped to no certification',
          row: row,
        );
      }
    }
  }

  static String _set(RelationSetAssertion a) =>
      '${a.nodeId} ${a.relationType} (${a.direction}, ${a.memberNodeType})';

  /// A completeness assertion (QF-8) names a set its relation type's
  /// signatures allow, has members, and cites legislation or a register
  /// when the relation states wine law. A symmetric relation type's set is
  /// read both ways, so its assertions are forward.
  void _completeness() {
    final allowed = {
      for (final s in d.relationTypeSignatures)
        '${s.relationType} ${s.subjectNodeType} ${s.objectNodeType}',
    };
    for (final a in d.relationSetAssertions) {
      final where = 'completeness assertion ${_set(a)}';
      final row = _ref('relation_set_assertions', a);
      final type = relationTypes[a.relationType];
      final symmetric = type?.isSymmetric ?? false;
      final forward = a.direction == 'forward';
      if (symmetric && !forward) {
        error(
          'assertion-direction',
          '$where: ${a.relationType} is symmetric, so its sets are read both '
              'ways and asserted forward',
          row: row,
        );
      }
      final node = nodes[a.nodeId];
      if (node != null) {
        final (subject, object) = forward
            ? (node.nodeType, a.memberNodeType)
            : (a.memberNodeType, node.nodeType);
        if (!allowed.contains('${a.relationType} $subject $object')) {
          error(
            'assertion-signature',
            '$where: ${a.relationType} does not allow $subject -> $object',
            row: row,
          );
        }
      }
      bool isMember(String? id) => nodes[id]?.nodeType == a.memberNodeType;
      final members = [
        for (final r in d.knowledgeRelations)
          if (r.relationType == a.relationType &&
              ((forward || symmetric) &&
                      r.subjectId == a.nodeId &&
                      isMember(r.objectId) ||
                  (!forward || symmetric) &&
                      r.objectId == a.nodeId &&
                      isMember(r.subjectId)))
            (r.validFrom, r.validUntil),
      ];
      // A set asserted complete must have a member on every date the
      // assertion covers, or a format would ask for an empty set.
      final gap = firstGap(a.validFrom, a.validUntil, members);
      if (gap != null) {
        error(
          'assertion-members',
          members.isEmpty
              ? '$where asserts a complete set, but the curriculum holds '
                    'none of its members'
              : '$where asserts a complete set, but none of its members is '
                    'in force on $gap',
          row: row,
        );
      }
      final source = citations[a.sourceCitationId];
      if (source != null &&
          regulatoryRelationTypes.contains(a.relationType) &&
          source.kind != 'legislation' &&
          source.kind != 'regulator_register') {
        error(
          'regulatory-citation',
          '$where states wine law but cites no legislation or regulator '
              'register',
          row: row,
        );
      }
    }
  }

  /// Every map layer cites its sources, each a dataset with the licence and
  /// the attribution the map shows (GEO-5, GEO-14).
  void _mapLayers() {
    final cited = <String>{};
    for (final c in d.mapLayerCitations) {
      cited.add(c.mapLayerId);
      final source = citations[c.sourceCitationId];
      if (source == null) continue;
      final lacks = [
        if (source.kind != 'dataset') 'is a ${source.kind}, not a dataset',
        if ((source.license ?? '').trim().isEmpty) 'has no licence',
        if ((source.attributionText ?? '').trim().isEmpty)
          'has no attribution text',
      ];
      if (lacks.isNotEmpty) {
        error(
          'layer-citation',
          'map layer ${c.mapLayerId} cites ${source.id}, which '
              '${lacks.join(' and ')}',
          row: _ref('map_layer_citations', c),
        );
      }
    }
    for (final l in d.mapLayers) {
      if (!cited.contains(l.id)) {
        error(
          'layer-citation',
          'map layer ${l.id} cites no source',
          row: _ref('map_layers', l),
        );
      }
    }
  }

  void _templates() {
    final placeholder = RegExp(r'\{[^}]*\}');
    final forward = <String>{};
    for (final t in d.questionTemplates) {
      // The schema checks only a mode's form; the formats decide (QF-2).
      if (!builtFormats.containsKey(t.mode)) {
        error(
          'template-format',
          '${t.id} has mode "${t.mode}", which is no format; the formats '
              'are ${builtFormats.keys.join(', ')}',
          row: _ref('question_templates', t),
        );
      }
      for (final match in placeholder.allMatches(t.promptTemplate)) {
        if (!templatePlaceholders.contains(match[0])) {
          error(
            'template-placeholder',
            '${t.id} uses unknown placeholder ${match[0]}',
            row: _ref('question_templates', t),
          );
        }
      }
      if (t.direction == 'forward') forward.add(t.relationType);
    }
    // Register §4: every relation type that carries an item can be asked.
    for (final type in {for (final i in d.knowledgeItems) i.relationType}) {
      if (!forward.contains(type)) {
        error('template-coverage', 'no forward template for $type');
      }
    }
  }

  void _report() {
    final uncurated = d.knowledgeRelations
        .where((r) => r.validFrom == uncuratedEffectiveDate)
        .length;
    if (uncurated > 0) {
      warning(
        'uncurated-date',
        '$uncurated relations have no curated effective date '
            '($uncuratedEffectiveDate)',
      );
    }
    final asserted = {
      for (final i in d.knowledgeItems)
        '${i.subjectId} ${i.relationType} ${i.objectId}',
    };
    final structural = d.knowledgeRelations
        .where((r) => !asserted.contains(_triple(r)))
        .length;
    warning(
      'structural-relation',
      '$structural relations carry no item or citation and need curator '
          'review (PR-5)',
    );
    final unverified = d.knowledgeItems
        .where((i) => i.verificationStatus != 'verified')
        .length;
    if (unverified > 0) {
      warning(
        'unverified',
        '$unverified of ${d.knowledgeItems.length} items await expert review',
      );
    }
  }
}

/// The first date of [from, until) on which none of [periods] is in force,
/// or `null` when they cover it all. Every period is [from, until) of
/// `YYYY-MM-DD` dates, and a null end is open.
String? firstGap(
  String from,
  String? until,
  Iterable<(String, String?)> periods,
) {
  bool reached(String date) => until != null && date.compareTo(until) >= 0;
  var covered = from;
  for (final (start, end)
      in periods.toList()..sort((a, b) => a.$1.compareTo(b.$1))) {
    if (end != null && end.compareTo(covered) <= 0) continue;
    if (start.compareTo(covered) > 0) break;
    if (end == null) return null;
    covered = end;
    if (reached(covered)) return null;
  }
  return reached(covered) ? null : covered;
}

/// A cycle in a directed graph given as adjacency lists, or `null`.
List<String>? findCycle(Map<String, List<String>> edges) {
  const visiting = 1, done = 2;
  final state = <String, int>{};
  final path = <String>[];

  List<String>? visit(String node) {
    state[node] = visiting;
    path.add(node);
    for (final next in edges[node] ?? const <String>[]) {
      if (state[next] == visiting) {
        return [...path.sublist(path.indexOf(next)), next];
      }
      if (state[next] == null) {
        final cycle = visit(next);
        if (cycle != null) return cycle;
      }
    }
    path.removeLast();
    state[node] = done;
    return null;
  }

  for (final node in edges.keys) {
    if (state[node] == null) {
      final cycle = visit(node);
      if (cycle != null) return cycle;
    }
  }
  return null;
}
