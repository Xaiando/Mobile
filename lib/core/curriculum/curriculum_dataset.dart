import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show ValueSerializer;
import 'package:yaml/yaml.dart';

import '../database/app_database.dart';
import 'name_normalizer.dart';

/// Where the bundled dataset lives in the app's assets.
const curriculumAssetPath = 'assets/curriculum/curriculum.yaml';

/// Thrown when a dataset does not follow the canonical format.
class DatasetFormatException implements Exception {
  DatasetFormatException(this.message);

  final String message;

  @override
  String toString() => 'Invalid curriculum dataset: $message';
}

/// The columns one dataset section may set.
///
/// Sections are named after their table and keys are column names
/// (docs/domain-model.md §7), so there is no mapping layer.
class DatasetSection {
  const DatasetSection({
    required this.required,
    this.optional = const {},
    this.defaults = const {},
    this.dates = const {},
    this.instants = const {},
    this.computed = const {},
  });

  /// Non-null columns the dataset must set.
  final Set<String> required;

  /// Nullable columns.
  final Set<String> optional;

  /// Non-null columns with the schema's default when the dataset omits them.
  final Map<String, Object> defaults;

  /// Date-only columns, `YYYY-MM-DD`.
  final Set<String> dates;

  /// UTC instants, `YYYY-MM-DDTHH:MM:SS.sssZ`.
  final Set<String> instants;

  /// Columns ingestion fills in, with their fixed value or `null` when the
  /// value is derived (`name_norm`). The dataset must not set them.
  final Map<String, Object?> computed;

  /// Every column the dataset may set.
  Set<String> get accepted => {...required, ...optional, ...defaults.keys};

  /// Every column of the table.
  Set<String> get columns => {...accepted, ...computed.keys};
}

/// Every authored table, in the order ingestion writes them.
const datasetSections = <String, DatasetSection>{
  'curriculum_domains': DatasetSection(
    required: {'id', 'display_name', 'position'},
  ),
  'tasting_grids': DatasetSection(
    required: {'id', 'framework', 'version', 'display_name'},
  ),
  'certifications': DatasetSection(
    required: {'id', 'organization', 'level', 'display_name'},
    optional: {'includes_certification_id', 'default_tasting_grid_id'},
    defaults: {'is_selectable': false},
  ),
  'node_types': DatasetSection(required: {'id', 'label'}),
  'relation_types': DatasetSection(
    required: {
      'id',
      'label',
      'reverse_label',
      'cardinality',
      'default_domain_id',
    },
    optional: {'distractor_match_relation_type'},
    defaults: {'is_transitive': false, 'is_reverse_safe': false},
  ),
  'relation_type_signatures': DatasetSection(
    required: {'relation_type', 'subject_node_type', 'object_node_type'},
  ),
  'knowledge_nodes': DatasetSection(
    required: {'id', 'node_type', 'name'},
    optional: {'valid_from', 'valid_until'},
    dates: {'valid_from', 'valid_until'},
    computed: {'name_norm': null},
  ),
  'quantity_values': DatasetSection(
    required: {'knowledge_node_id', 'minimum', 'unit'},
    optional: {'maximum'},
    computed: {'node_type': 'quantity'},
  ),
  'node_alternative_names': DatasetSection(
    required: {'knowledge_node_id', 'name', 'kind'},
    computed: {'name_norm': null},
  ),
  'knowledge_relations': DatasetSection(
    required: {'subject_id', 'relation_type', 'object_id', 'valid_from'},
    optional: {'valid_until'},
    dates: {'valid_from', 'valid_until'},
  ),
  'knowledge_items': DatasetSection(
    required: {
      'id',
      'subject_id',
      'relation_type',
      'object_id',
      'domain_id',
      'assertion_text',
      'last_verified_at',
    },
    optional: {'superseded_by_item_id'},
    defaults: {
      'revision': 1,
      'verification_status': 'unverified',
      'is_distinctive': false,
      'mcq_disabled': false,
    },
    instants: {'last_verified_at'},
  ),
  'knowledge_item_prerequisites': DatasetSection(
    required: {'knowledge_item_id', 'prerequisite_item_id'},
  ),
  'certification_knowledge_mappings': DatasetSection(
    required: {
      'certification_id',
      'knowledge_item_id',
      'importance',
      'minimum_depth',
    },
    optional: {'syllabus_ref'},
  ),
  'source_citations': DatasetSection(
    required: {'id', 'kind', 'title', 'publisher', 'accessed_on'},
    optional: {
      'jurisdiction',
      'document_identifier',
      'url',
      'published_on',
      'license',
      'attribution_text',
    },
    dates: {'published_on', 'accessed_on'},
  ),
  'knowledge_item_citations': DatasetSection(
    required: {'knowledge_item_id', 'source_citation_id'},
    optional: {'locator'},
  ),
  'question_templates': DatasetSection(
    required: {'id', 'relation_type', 'direction', 'mode', 'prompt_template'},
    defaults: {'locale': 'en'},
  ),
  'tasting_grid_attributes': DatasetSection(
    required: {
      'tasting_grid_id',
      'attribute_key',
      'section',
      'label',
      'position',
      'selection',
    },
    defaults: {'is_required': true},
  ),
  'tasting_grid_values': DatasetSection(
    required: {
      'tasting_grid_id',
      'attribute_key',
      'value_key',
      'label',
      'position',
    },
    optional: {'knowledge_node_id'},
  ),
};

final _semanticVersion = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _utcMilliseconds = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);

/// Compares two `major.minor.patch` versions.
int compareVersions(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final order = left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return 0;
}

/// One curriculum release: a row list per authored table.
///
/// Generated tables (questions) and user data are never part of a dataset.
class CurriculumDataset {
  const CurriculumDataset({
    required this.version,
    required this.publishedAt,
    required this.checksum,
    required this.curriculumDomains,
    required this.tastingGrids,
    required this.certifications,
    required this.nodeTypes,
    required this.relationTypes,
    required this.relationTypeSignatures,
    required this.knowledgeNodes,
    required this.quantityValues,
    required this.nodeAlternativeNames,
    required this.knowledgeRelations,
    required this.knowledgeItems,
    required this.knowledgeItemPrerequisites,
    required this.certificationKnowledgeMappings,
    required this.sourceCitations,
    required this.knowledgeItemCitations,
    required this.questionTemplates,
    required this.tastingGridAttributes,
    required this.tastingGridValues,
  });

  /// Parses the canonical YAML format, rejecting unknown sections and
  /// columns, missing required columns and malformed dates.
  factory CurriculumDataset.parse(String source) => _Parser(source).parse();

  /// `dataset_version`, a semantic version (architecture audit V-7).
  final String version;
  final DateTime publishedAt;

  /// `sha256:` followed by the hex digest of the dataset text.
  final String checksum;

  final List<CurriculumDomain> curriculumDomains;
  final List<TastingGrid> tastingGrids;
  final List<Certification> certifications;
  final List<NodeType> nodeTypes;
  final List<RelationType> relationTypes;
  final List<RelationTypeSignature> relationTypeSignatures;
  final List<KnowledgeNode> knowledgeNodes;
  final List<QuantityValue> quantityValues;
  final List<NodeAlternativeName> nodeAlternativeNames;
  final List<KnowledgeRelation> knowledgeRelations;
  final List<KnowledgeItem> knowledgeItems;
  final List<KnowledgeItemPrerequisite> knowledgeItemPrerequisites;
  final List<CertificationKnowledgeMapping> certificationKnowledgeMappings;
  final List<SourceCitation> sourceCitations;
  final List<KnowledgeItemCitation> knowledgeItemCitations;
  final List<QuestionTemplate> questionTemplates;
  final List<TastingGridAttribute> tastingGridAttributes;
  final List<TastingGridValue> tastingGridValues;
}

typedef _FromJson<D> = D Function(
  Map<String, dynamic> json, {
  ValueSerializer? serializer,
});

class _Parser {
  _Parser(this.source);

  final String source;
  late final YamlMap _document;

  static const _serializer = ValueSerializer.defaults(
    serializeDateTimeValuesAsString: true,
  );

  CurriculumDataset parse() {
    final Object? document;
    try {
      document = loadYaml(source);
    } on YamlException catch (error) {
      throw DatasetFormatException('not valid YAML: ${error.message}');
    }
    if (document is! YamlMap) {
      throw DatasetFormatException('the top level must be a mapping');
    }
    _document = document;

    final known = {'dataset_version', 'published_at', ...datasetSections.keys};
    final unknown = [
      for (final key in document.keys)
        if (!known.contains(key)) '$key',
    ];
    if (unknown.isNotEmpty) {
      throw DatasetFormatException('unknown sections: ${unknown.join(', ')}');
    }

    final version = _text('dataset_version');
    if (!_semanticVersion.hasMatch(version)) {
      throw DatasetFormatException(
        'dataset_version "$version" is not major.minor.patch',
      );
    }
    final publishedAt = _text('published_at');
    if (!_utcMilliseconds.hasMatch(publishedAt)) {
      throw DatasetFormatException(
        'published_at "$publishedAt" is not a UTC instant with milliseconds',
      );
    }

    return CurriculumDataset(
      version: version,
      publishedAt: DateTime.parse(publishedAt),
      checksum: 'sha256:${sha256.convert(utf8.encode(source))}',
      curriculumDomains: _rows('curriculum_domains', CurriculumDomain.fromJson),
      tastingGrids: _rows('tasting_grids', TastingGrid.fromJson),
      certifications: _rows('certifications', Certification.fromJson),
      nodeTypes: _rows('node_types', NodeType.fromJson),
      relationTypes: _rows('relation_types', RelationType.fromJson),
      relationTypeSignatures: _rows(
        'relation_type_signatures',
        RelationTypeSignature.fromJson,
      ),
      knowledgeNodes: _rows('knowledge_nodes', KnowledgeNode.fromJson),
      quantityValues: _rows('quantity_values', QuantityValue.fromJson),
      nodeAlternativeNames: _rows(
        'node_alternative_names',
        NodeAlternativeName.fromJson,
      ),
      knowledgeRelations: _rows(
        'knowledge_relations',
        KnowledgeRelation.fromJson,
      ),
      knowledgeItems: _rows('knowledge_items', KnowledgeItem.fromJson),
      knowledgeItemPrerequisites: _rows(
        'knowledge_item_prerequisites',
        KnowledgeItemPrerequisite.fromJson,
      ),
      certificationKnowledgeMappings: _rows(
        'certification_knowledge_mappings',
        CertificationKnowledgeMapping.fromJson,
      ),
      sourceCitations: _rows('source_citations', SourceCitation.fromJson),
      knowledgeItemCitations: _rows(
        'knowledge_item_citations',
        KnowledgeItemCitation.fromJson,
      ),
      questionTemplates: _rows('question_templates', QuestionTemplate.fromJson),
      tastingGridAttributes: _rows(
        'tasting_grid_attributes',
        TastingGridAttribute.fromJson,
      ),
      tastingGridValues: _rows(
        'tasting_grid_values',
        TastingGridValue.fromJson,
      ),
    );
  }

  String _text(String key) {
    final value = _document[key];
    if (value is! String || value.isEmpty) {
      throw DatasetFormatException('"$key" must be a quoted string');
    }
    return value;
  }

  List<D> _rows<D>(String table, _FromJson<D> fromJson) {
    final entries = _document[table];
    if (entries is! YamlList) {
      throw DatasetFormatException(
        'section "$table" must be a list (use [] when empty)',
      );
    }
    return [
      for (final (index, entry) in entries.indexed)
        _row(table, index, entry, fromJson),
    ];
  }

  D _row<D>(String table, int index, Object? entry, _FromJson<D> fromJson) {
    final section = datasetSections[table]!;
    if (entry is! YamlMap) {
      throw DatasetFormatException('$table[$index] must be a mapping');
    }
    final row = <String, dynamic>{
      for (final MapEntry(:key, :value) in entry.entries) '$key': value,
    };
    final id = row['id'];
    final where = '$table[$index]${id == null ? '' : ' ($id)'}';

    final unknown = row.keys.where((c) => !section.accepted.contains(c));
    if (unknown.isNotEmpty) {
      throw DatasetFormatException(
        '$where: unknown columns ${unknown.join(', ')}',
      );
    }
    final missing = section.required.where((c) => row[c] == null);
    if (missing.isNotEmpty) {
      throw DatasetFormatException('$where: missing ${missing.join(', ')}');
    }
    for (final column in section.dates) {
      final Object? value = row[column];
      if (value != null && !_isIsoDate(value)) {
        throw DatasetFormatException(
          '$where: $column "$value" is not a YYYY-MM-DD date',
        );
      }
    }
    for (final column in section.instants) {
      final value = row[column];
      if (value is! String || !_utcMilliseconds.hasMatch(value)) {
        throw DatasetFormatException(
          '$where: $column "$value" is not a UTC instant with milliseconds',
        );
      }
    }

    for (final MapEntry(:key, :value) in section.defaults.entries) {
      row[key] ??= value;
    }
    for (final MapEntry(:key, :value) in section.computed.entries) {
      if (key == 'name_norm') {
        final name = row['name'];
        if (name is! String) {
          throw DatasetFormatException('$where: name must be text');
        }
        row[key] = normalizeName(name);
      } else {
        row[key] = value;
      }
    }

    try {
      return fromJson(row, serializer: _serializer);
    } on TypeError catch (error) {
      throw DatasetFormatException(
        '$where: a value has the wrong type: $error',
      );
    }
  }

  static bool _isIsoDate(Object value) {
    if (value is! String || !_isoDate.hasMatch(value)) return false;
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    return parsed != null && parsed.toIso8601String().startsWith(value);
  }
}
