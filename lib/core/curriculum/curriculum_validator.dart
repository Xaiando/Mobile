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
  const ValidationIssue(this.rule, this.message, {this.isError = true});

  /// A short rule name, e.g. `dangling-relation`.
  final String rule;
  final String message;

  /// Errors block ingestion; warnings go to the build report.
  final bool isError;

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

  static String _triple(KnowledgeRelation r) =>
      '${r.subjectId} ${r.relationType} ${r.objectId}';

  void error(String rule, String message) =>
      issues.add(ValidationIssue(rule, message));

  void warning(String rule, String message) =>
      issues.add(ValidationIssue(rule, message, isError: false));

  List<ValidationIssue> run() {
    _uniqueKeys();
    _identifiers();
    _references();
    _signatures();
    _cycles();
    _certificationChains();
    _cardinality();
    _quantities();
    _provenance();
    _templates();
    _report();
    return issues;
  }

  void _unique<R>(String table, Iterable<R> rows, Object Function(R) key) {
    final seen = <Object>{};
    for (final row in rows) {
      final k = key(row);
      if (!seen.add(k)) error('duplicate-key', '$table: $k appears twice');
    }
  }

  void _uniqueKeys() {
    _unique('curriculum_domains', d.curriculumDomains, (r) => r.id);
    _unique('curriculum_domains', d.curriculumDomains, (r) => r.position);
    _unique('tasting_grids', d.tastingGrids, (r) => r.id);
    _unique('certifications', d.certifications, (r) => r.id);
    _unique(
      'certifications',
      d.certifications,
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
      (r) => '${r.relationType} ${r.direction} ${r.mode} ${r.locale}',
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
        );
      }
      names['${node.nodeType} ${node.nameNorm}'] = node.id;
    }
  }

  void _identifiers() {
    void check(String table, Iterable<String> ids, RegExp pattern) {
      for (final id in ids) {
        if (!pattern.hasMatch(id)) {
          error('id-format', '$table: "$id" does not match ${pattern.pattern}');
        }
      }
    }

    check('curriculum_domains', domains, RegExp(r'^[a-z_]+$'));
    check('tasting_grids', grids, RegExp(r'^tg_[a-z0-9_]+$'));
    check('certifications', certifications.keys, RegExp(r'^[A-Z0-9_]+$'));
    check('node_types', nodeTypes, RegExp(r'^[a-z_]+$'));
    check('relation_types', relationTypes.keys, RegExp(r'^[A-Z_]+$'));
    check('knowledge_nodes', nodes.keys, RegExp(r'^n_[a-z0-9_]+$'));
    check('knowledge_items', items.keys, RegExp(r'^ki_[a-z0-9_]+$'));
    check('source_citations', citations.keys, RegExp(r'^src_[a-z0-9_]+$'));
    check('question_templates', [
      for (final t in d.questionTemplates) t.id,
    ], RegExp(r'^qt_[a-z0-9_]+$'));
  }

  void _references() {
    void refer(String where, String? id, Iterable<String> targets, String to) {
      if (id != null && !targets.contains(id)) {
        error('unknown-reference', '$where refers to unknown $to "$id"');
      }
    }

    for (final c in d.certifications) {
      refer(
        'certification ${c.id}',
        c.includesCertificationId,
        certifications.keys,
        'certification',
      );
      refer(
        'certification ${c.id}',
        c.defaultTastingGridId,
        grids,
        'tasting grid',
      );
    }
    for (final t in d.relationTypes) {
      refer('relation type ${t.id}', t.defaultDomainId, domains, 'domain');
      refer(
        'relation type ${t.id}',
        t.distractorMatchRelationType,
        relationTypes.keys,
        'relation type',
      );
    }
    for (final s in d.relationTypeSignatures) {
      final where = 'signature ${s.relationType}';
      refer(where, s.relationType, relationTypes.keys, 'relation type');
      refer(where, s.subjectNodeType, nodeTypes, 'node type');
      refer(where, s.objectNodeType, nodeTypes, 'node type');
    }
    for (final n in d.knowledgeNodes) {
      refer('node ${n.id}', n.nodeType, nodeTypes, 'node type');
      final from = n.validFrom, until = n.validUntil;
      if (from != null && until != null && until.compareTo(from) <= 0) {
        error('validity', 'node ${n.id} ends before it starts');
      }
    }
    for (final a in d.nodeAlternativeNames) {
      refer(
        'alternative name "${a.name}"',
        a.knowledgeNodeId,
        nodes.keys,
        'node',
      );
    }

    // §S.1: every relation must connect existing nodes.
    for (final r in d.knowledgeRelations) {
      final where = 'relation ${_triple(r)}';
      for (final end in [r.subjectId, r.objectId]) {
        if (!nodes.containsKey(end)) {
          error('dangling-relation', '$where refers to unknown node "$end"');
        }
      }
      refer(where, r.relationType, relationTypes.keys, 'relation type');
      if (r.subjectId == r.objectId) {
        error('self-reference', '$where relates a node to itself');
      }
      final until = r.validUntil;
      if (until != null && until.compareTo(r.validFrom) <= 0) {
        error('validity', '$where ends before it starts');
      }
    }

    for (final i in d.knowledgeItems) {
      final where = 'item ${i.id}';
      final triple = '${i.subjectId} ${i.relationType} ${i.objectId}';
      if (!relations.containsKey(triple)) {
        error('item-relation', '$where asserts $triple, which is no relation');
      }
      refer(where, i.domainId, domains, 'domain');
      refer(where, i.supersededByItemId, items.keys, 'item');
      if (i.supersededByItemId == i.id) {
        error('self-reference', '$where supersedes itself');
      }
    }
    for (final p in d.knowledgeItemPrerequisites) {
      final where = 'prerequisite of ${p.knowledgeItemId}';
      refer(where, p.knowledgeItemId, items.keys, 'item');
      refer(where, p.prerequisiteItemId, items.keys, 'item');
    }
    for (final m in d.certificationKnowledgeMappings) {
      final where = 'mapping ${m.certificationId} ${m.knowledgeItemId}';
      refer(where, m.certificationId, certifications.keys, 'certification');
      refer(where, m.knowledgeItemId, items.keys, 'item');
    }
    for (final c in d.knowledgeItemCitations) {
      final where = 'citation of ${c.knowledgeItemId}';
      refer(where, c.knowledgeItemId, items.keys, 'item');
      refer(where, c.sourceCitationId, citations.keys, 'source citation');
    }
    for (final t in d.questionTemplates) {
      refer(
        'template ${t.id}',
        t.relationType,
        relationTypes.keys,
        'relation type',
      );
    }
    final attributes = {
      for (final a in d.tastingGridAttributes)
        '${a.tastingGridId} ${a.attributeKey}',
    };
    for (final a in d.tastingGridAttributes) {
      refer('grid attribute ${a.attributeKey}', a.tastingGridId, grids, 'grid');
    }
    for (final v in d.tastingGridValues) {
      final where = 'grid value ${v.valueKey}';
      refer(
        where,
        '${v.tastingGridId} ${v.attributeKey}',
        attributes,
        'attribute',
      );
      refer(where, v.knowledgeNodeId, nodes.keys, 'node');
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
        error('self-reference', '${p.knowledgeItemId} requires itself');
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
  }

  void _certificationChains() {
    for (final c in d.certifications) {
      final included = certifications[c.includesCertificationId];
      if (included == null) continue;
      if (included.organization != c.organization) {
        error(
          'certification-chain',
          '${c.id} includes ${included.id} from another organization',
        );
      }
      if (included.level >= c.level) {
        error(
          'certification-chain',
          '${c.id} includes ${included.id}, which is not a lower level',
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
            );
          }
        }
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
        error('quantity', 'quantity node ${node.id} has no quantity value');
      }
    }
    for (final q in d.quantityValues) {
      final node = nodes[q.knowledgeNodeId];
      if (node != null && node.nodeType != 'quantity') {
        error(
          'quantity',
          '${q.knowledgeNodeId} has a quantity value but is a '
              '${node.nodeType}',
        );
      }
      final maximum = q.maximum;
      if (maximum != null && maximum < q.minimum) {
        error('quantity', '${q.knowledgeNodeId}: maximum below minimum');
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
      final sources = cited[item.id] ?? const [];
      if (sources.isEmpty) {
        error('item-citation', '${item.id} cites no source');
      } else if (regulatoryRelationTypes.contains(item.relationType) &&
          !sources.any(
            (s) => s.kind == 'legislation' || s.kind == 'regulator_register',
          )) {
        error(
          'regulatory-citation',
          '${item.id} states wine law but cites no legislation or '
              'regulator register',
        );
      }
      if (!mapped.contains(item.id)) {
        error('item-mapping', '${item.id} is mapped to no certification');
      }
    }
  }

  void _templates() {
    final placeholder = RegExp(r'\{[^}]*\}');
    final forward = <String>{};
    for (final t in d.questionTemplates) {
      for (final match in placeholder.allMatches(t.promptTemplate)) {
        if (!templatePlaceholders.contains(match[0])) {
          error(
            'template-placeholder',
            '${t.id} uses unknown placeholder ${match[0]}',
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
