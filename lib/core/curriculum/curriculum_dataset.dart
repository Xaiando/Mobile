import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DataClass, ValueSerializer;
import 'package:yaml/yaml.dart';

import '../database/app_database.dart';
import 'name_normalizer.dart';

/// Where the bundled dataset's manifest lives in the app's assets.
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
    required this.key,
    required this.required,
    this.optional = const {},
    this.defaults = const {},
    this.dates = const {},
    this.instants = const {},
    this.json = const {},
    this.computed = const {},
  });

  /// The columns that identify a row: the table's primary key.
  final List<String> key;

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

  /// JSON object columns: a mapping in the dataset, stored as JSON text.
  final Set<String> json;

  /// Columns ingestion fills in, with their fixed value or `null` when the
  /// value is derived (`name_norm`). The dataset must not set them.
  final Map<String, Object?> computed;

  /// Every column the dataset may set.
  Set<String> get accepted => {...required, ...optional, ...defaults.keys};

  /// Every column of the table.
  Set<String> get columns => {...accepted, ...computed.keys};

  /// The key of [row]: its [key] columns' values, joined by spaces.
  String keyOf(Map<String, Object?> row) =>
      [for (final column in key) row[column]].join(' ');
}

/// Every authored table, in the order ingestion writes them.
const datasetSections = <String, DatasetSection>{
  'curriculum_domains': DatasetSection(
    key: ['id'],
    required: {'id', 'display_name', 'position'},
  ),
  'tasting_grids': DatasetSection(
    key: ['id'],
    required: {'id', 'framework', 'version', 'display_name'},
  ),
  // A certification has an organization and a level; a pack has neither.
  'certifications': DatasetSection(
    key: ['id'],
    required: {'id', 'display_name'},
    optional: {
      'organization',
      'level',
      'description',
      'includes_certification_id',
      'default_tasting_grid_id',
    },
    defaults: {'is_selectable': false, 'kind': 'certification'},
  ),
  'node_types': DatasetSection(key: ['id'], required: {'id', 'label'}),
  'relation_types': DatasetSection(
    key: ['id'],
    required: {
      'id',
      'label',
      'reverse_label',
      'cardinality',
      'default_domain_id',
    },
    optional: {'distractor_match_relation_type'},
    defaults: {
      'is_transitive': false,
      'is_reverse_safe': false,
      'is_symmetric': false,
    },
  ),
  'relation_type_signatures': DatasetSection(
    key: ['relation_type', 'subject_node_type', 'object_node_type'],
    required: {'relation_type', 'subject_node_type', 'object_node_type'},
  ),
  'knowledge_nodes': DatasetSection(
    key: ['id'],
    required: {'id', 'node_type', 'name'},
    optional: {'valid_from', 'valid_until'},
    dates: {'valid_from', 'valid_until'},
    computed: {'name_norm': null},
  ),
  'quantity_values': DatasetSection(
    key: ['knowledge_node_id'],
    required: {'knowledge_node_id', 'minimum', 'unit'},
    optional: {'maximum'},
    computed: {'node_type': 'quantity'},
  ),
  'node_alternative_names': DatasetSection(
    key: ['knowledge_node_id', 'name_norm'],
    required: {'knowledge_node_id', 'name', 'kind'},
    computed: {'name_norm': null},
  ),
  'knowledge_relations': DatasetSection(
    key: ['subject_id', 'relation_type', 'object_id'],
    required: {'subject_id', 'relation_type', 'object_id', 'valid_from'},
    optional: {'valid_until'},
    dates: {'valid_from', 'valid_until'},
  ),
  'knowledge_items': DatasetSection(
    key: ['id'],
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
    key: ['knowledge_item_id', 'prerequisite_item_id'],
    required: {'knowledge_item_id', 'prerequisite_item_id'},
  ),
  'certification_knowledge_mappings': DatasetSection(
    key: ['certification_id', 'knowledge_item_id'],
    required: {
      'certification_id',
      'knowledge_item_id',
      'importance',
      'minimum_depth',
    },
    optional: {'syllabus_ref'},
  ),
  'source_citations': DatasetSection(
    key: ['id'],
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
    key: ['knowledge_item_id', 'source_citation_id'],
    required: {'knowledge_item_id', 'source_citation_id'},
    optional: {'locator'},
  ),
  'question_templates': DatasetSection(
    key: ['id'],
    required: {'id', 'relation_type', 'direction', 'mode', 'prompt_template'},
    optional: {'parameters'},
    defaults: {'locale': 'en', 'variant': ''},
    json: {'parameters'},
  ),
  'tasting_grid_attributes': DatasetSection(
    key: ['tasting_grid_id', 'attribute_key'],
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
    key: ['tasting_grid_id', 'attribute_key', 'value_key'],
    required: {
      'tasting_grid_id',
      'attribute_key',
      'value_key',
      'label',
      'position',
    },
    optional: {'knowledge_node_id'},
  ),
  'relation_set_assertions': DatasetSection(
    key: [
      'node_id',
      'relation_type',
      'direction',
      'member_node_type',
      'valid_from',
    ],
    required: {
      'node_id',
      'relation_type',
      'direction',
      'member_node_type',
      'valid_from',
      'source_citation_id',
    },
    optional: {'valid_until', 'locator'},
    dates: {'valid_from', 'valid_until'},
  ),
  'map_layers': DatasetSection(
    key: ['id'],
    required: {
      'id',
      'display_name',
      'geometry_kind',
      'asset_path',
      'asset_sha256',
      'min_zoom',
      'max_zoom',
    },
    optional: {'parent_layer_id'},
  ),
  'map_layer_citations': DatasetSection(
    key: ['map_layer_id', 'source_citation_id'],
    required: {'map_layer_id', 'source_citation_id', 'position'},
  ),
  'node_geometries': DatasetSection(
    key: ['knowledge_node_id', 'map_layer_id'],
    required: {
      'knowledge_node_id',
      'map_layer_id',
      'feature_key',
      'min_lon',
      'min_lat',
      'max_lon',
      'max_lat',
      'label_lon',
      'label_lat',
    },
  ),
};

/// The manifest's own keys; every other top-level key is a section.
const _manifestKeys = {
  'dataset_version',
  'published_at',
  'includes',
  'geography',
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

/// One file of a dataset: the path it was read from, and its text.
final class DatasetFile {
  const DatasetFile(this.path, this.text);

  final String path;
  final String text;
}

/// Where a row is written: a file, and a line counted from 1.
final class DatasetLocation {
  const DatasetLocation(this.path, this.line);

  final String path;
  final int line;

  @override
  bool operator ==(Object other) =>
      other is DatasetLocation && other.path == path && other.line == line;

  @override
  int get hashCode => Object.hash(path, line);

  @override
  String toString() => '$path:$line';
}

/// A row of a dataset, by its section and its key ([DatasetSection.keyOf]).
typedef DatasetRowRef = ({String section, String key});

/// The key of [row], a row of [section], as [DatasetSection.keyOf] gives it.
String rowKey(String section, DataClass row) =>
    datasetSections[section]!.keyOf(row.toJson());

/// The paths of the files the manifest [path] includes, in order, resolved
/// against the manifest's folder.
///
/// A dataset is one manifest, `curriculum.yaml`, which holds the release's
/// `dataset_version` and `published_at` and lists its other files under
/// `includes:` (architecture audit DL-4).
List<String> datasetIncludes(String path, String manifest) {
  final document = _loadYaml(DatasetFile(path, manifest));
  final folder = _folderOf(path);
  return [
    for (final include in _includes(path, document))
      folder.isEmpty ? include : '$folder/$include',
  ];
}

/// The path of the geography manifest that the manifest [path] names under
/// `geography:`, resolved against the manifest's folder, or null when it
/// names none.
///
/// tool/geography generates the map layers and their node geometries into
/// that manifest (geography §7); the release includes it, after the files
/// under `includes:`.
String? datasetGeography(String path, String manifest) =>
    _geography(path, _loadYaml(DatasetFile(path, manifest)));

/// One curriculum release: a row list per authored table.
///
/// Generated tables (questions) and user data are never part of a dataset.
class CurriculumDataset {
  CurriculumDataset({
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
    required this.relationSetAssertions,
    required this.mapLayers,
    required this.mapLayerCitations,
    required this.nodeGeometries,
    this.files = const [],
    this.locations = const {},
  });

  /// Parses a dataset written as a single file, which includes no other.
  factory CurriculumDataset.parse(
    String source, {
    String path = 'curriculum.yaml',
  }) => CurriculumDataset.fromFiles([DatasetFile(path, source)]);

  /// Parses a dataset from its files: the manifest first, then each file it
  /// includes, in the order it lists them ([datasetIncludes]).
  ///
  /// Rejects unknown sections and columns, missing required columns,
  /// malformed dates, and a key defined twice, in one file or two.
  factory CurriculumDataset.fromFiles(List<DatasetFile> files) =>
      _Parser(files).parse();

  /// Reads the dataset whose manifest is at [manifestPath], then parses it.
  /// [read] returns the text of the file at a path.
  static Future<CurriculumDataset> load(
    String manifestPath,
    Future<String> Function(String path) read,
  ) async {
    final path = _slashes(manifestPath);
    final manifest = DatasetFile(path, await read(path));
    final files = [manifest];
    for (final include in [
      ...datasetIncludes(path, manifest.text),
      ?datasetGeography(path, manifest.text),
    ]) {
      files.add(DatasetFile(include, await _readIncluded(include, read)));
    }
    return CurriculumDataset.fromFiles(files);
  }

  /// [load], for a synchronous [read], as tools and tests have.
  static CurriculumDataset loadSync(
    String manifestPath,
    String Function(String path) read,
  ) {
    final path = _slashes(manifestPath);
    final files = [DatasetFile(path, read(path))];
    for (final include in [
      ...datasetIncludes(path, files.first.text),
      ?datasetGeography(path, files.first.text),
    ]) {
      try {
        files.add(DatasetFile(include, read(include)));
      } on Object catch (error) {
        throw DatasetFormatException('$include cannot be read: $error');
      }
    }
    return CurriculumDataset.fromFiles(files);
  }

  static Future<String> _readIncluded(
    String path,
    Future<String> Function(String path) read,
  ) async {
    try {
      return await read(path);
    } on Object catch (error) {
      throw DatasetFormatException('$path cannot be read: $error');
    }
  }

  /// `dataset_version`, a semantic version (architecture audit V-7).
  final String version;
  final DateTime publishedAt;

  /// `sha256:` followed by the hex digest of the dataset's files: the
  /// manifest's text, then each included file's path and text. A dataset in
  /// one file has the digest of that file.
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
  final List<RelationSetAssertion> relationSetAssertions;
  final List<MapLayer> mapLayers;
  final List<MapLayerCitation> mapLayerCitations;
  final List<NodeGeometry> nodeGeometries;

  /// The paths of the files the dataset was parsed from, the manifest first.
  final List<String> files;

  /// Where each row is written: by section, then by the row's key.
  final Map<String, Map<String, DatasetLocation>> locations;

  /// Where [row] is written, if this dataset has it.
  DatasetLocation? locate(DatasetRowRef row) =>
      locations[row.section]?[row.key];
}

typedef _FromJson<D> = D Function(
  Map<String, dynamic> json, {
  ValueSerializer? serializer,
});

/// A row as written, before conversion: its columns and where it is.
typedef _RawRow = ({Map<String, dynamic> row, DatasetLocation at});

class _Parser {
  _Parser(this.files) {
    if (files.isEmpty) throw DatasetFormatException('no files to parse');
  }

  final List<DatasetFile> files;

  static const _serializer = ValueSerializer.defaults(
    serializeDateTimeValuesAsString: true,
  );

  /// Each section's rows, in file order, then in order within each file.
  final _rows = <String, List<_RawRow>>{};

  CurriculumDataset parse() {
    final manifestFile = files.first;
    final manifest = _loadYaml(manifestFile);
    final unknown = [
      for (final key in manifest.keys)
        if (!_manifestKeys.contains(key) && !datasetSections.containsKey(key))
          '$key',
    ];
    if (unknown.isNotEmpty) {
      throw DatasetFormatException(
        '${manifestFile.path}: unknown sections: ${unknown.join(', ')}',
      );
    }

    final version = _text(manifest, manifestFile, 'dataset_version');
    if (!_semanticVersion.hasMatch(version)) {
      throw DatasetFormatException(
        '${manifestFile.path}: dataset_version "$version" is not '
        'major.minor.patch',
      );
    }
    final publishedAt = _text(manifest, manifestFile, 'published_at');
    if (!_utcMilliseconds.hasMatch(publishedAt)) {
      throw DatasetFormatException(
        '${manifestFile.path}: published_at "$publishedAt" is not a UTC '
        'instant with milliseconds',
      );
    }

    final includes = _includes(manifestFile.path, manifest);
    final folder = _folderOf(manifestFile.path);
    final geography = _geography(manifestFile.path, manifest);
    final expectedFiles = [
      for (final include in includes)
        folder.isEmpty ? include : '$folder/$include',
      ?geography,
    ];
    for (var i = 0; i < expectedFiles.length || i < files.length - 1; i++) {
      final expected = i < expectedFiles.length ? expectedFiles[i] : null;
      final given = i + 1 < files.length ? files[i + 1].path : null;
      if (expected != given) {
        throw DatasetFormatException(
          expected == null
              ? '$given is not included by ${manifestFile.path}'
              : '${manifestFile.path} includes $expected, which was not '
                    'loaded',
        );
      }
    }

    _collect(manifestFile, manifest);
    for (final file in files.skip(1)) {
      final document = _loadYaml(file);
      if (file.path == geography) {
        _collectGeography(file, document);
        continue;
      }
      final misplaced = [
        for (final key in document.keys)
          if (_manifestKeys.contains(key)) '$key',
      ];
      if (misplaced.isNotEmpty) {
        throw DatasetFormatException(
          '${file.path}: only the manifest sets ${misplaced.join(', ')}',
        );
      }
      final unknown = [
        for (final key in document.keys)
          if (!datasetSections.containsKey(key)) '$key',
      ];
      if (unknown.isNotEmpty) {
        throw DatasetFormatException(
          '${file.path}: unknown sections: ${unknown.join(', ')}',
        );
      }
      _collect(file, document);
    }

    final absent = [
      for (final section in datasetSections.keys)
        if (!_rows.containsKey(section)) section,
    ];
    if (absent.isNotEmpty) {
      throw DatasetFormatException(
        'sections in no file: ${absent.join(', ')} '
        '(write "section: []" when a section is empty)',
      );
    }
    final locations = _locate();

    return CurriculumDataset(
      version: version,
      publishedAt: DateTime.parse(publishedAt),
      checksum: _checksum([
        ...includes,
        if (geography != null) '${manifest['geography']}',
      ]),
      files: [for (final file in files) file.path],
      locations: locations,
      curriculumDomains: _convert(
        'curriculum_domains',
        CurriculumDomain.fromJson,
      ),
      tastingGrids: _convert('tasting_grids', TastingGrid.fromJson),
      certifications: _convert('certifications', Certification.fromJson),
      nodeTypes: _convert('node_types', NodeType.fromJson),
      relationTypes: _convert('relation_types', RelationType.fromJson),
      relationTypeSignatures: _convert(
        'relation_type_signatures',
        RelationTypeSignature.fromJson,
      ),
      knowledgeNodes: _convert('knowledge_nodes', KnowledgeNode.fromJson),
      quantityValues: _convert('quantity_values', QuantityValue.fromJson),
      nodeAlternativeNames: _convert(
        'node_alternative_names',
        NodeAlternativeName.fromJson,
      ),
      knowledgeRelations: _convert(
        'knowledge_relations',
        KnowledgeRelation.fromJson,
      ),
      knowledgeItems: _convert('knowledge_items', KnowledgeItem.fromJson),
      knowledgeItemPrerequisites: _convert(
        'knowledge_item_prerequisites',
        KnowledgeItemPrerequisite.fromJson,
      ),
      certificationKnowledgeMappings: _convert(
        'certification_knowledge_mappings',
        CertificationKnowledgeMapping.fromJson,
      ),
      sourceCitations: _convert('source_citations', SourceCitation.fromJson),
      knowledgeItemCitations: _convert(
        'knowledge_item_citations',
        KnowledgeItemCitation.fromJson,
      ),
      questionTemplates: _convert(
        'question_templates',
        QuestionTemplate.fromJson,
      ),
      tastingGridAttributes: _convert(
        'tasting_grid_attributes',
        TastingGridAttribute.fromJson,
      ),
      tastingGridValues: _convert(
        'tasting_grid_values',
        TastingGridValue.fromJson,
      ),
      relationSetAssertions: _convert(
        'relation_set_assertions',
        RelationSetAssertion.fromJson,
      ),
      mapLayers: _convert('map_layers', MapLayer.fromJson),
      mapLayerCitations: _convert(
        'map_layer_citations',
        MapLayerCitation.fromJson,
      ),
      nodeGeometries: _convert('node_geometries', NodeGeometry.fromJson),
    );
  }

  static String _text(YamlMap document, DatasetFile file, String key) {
    final value = document[key];
    if (value is! String || value.isEmpty) {
      throw DatasetFormatException(
        '${file.path}: "$key" must be a quoted string',
      );
    }
    return value;
  }

  /// Checks and completes the rows of each section in [document], adding
  /// them to [_rows] with their location.
  void _collect(DatasetFile file, YamlMap document) {
    for (final MapEntry(:key, :value) in document.nodes.entries) {
      final table = '${(key as YamlNode).value}';
      final section = datasetSections[table];
      if (section == null) continue;
      if (value is! YamlList) {
        throw DatasetFormatException(
          '${_at(file, value)}: section "$table" must be a list '
          '(use [] when empty)',
        );
      }
      final rows = _rows.putIfAbsent(table, () => []);
      for (final entry in value.nodes) {
        rows.add((
          row: _check(table, section, entry, _at(file, entry)),
          at: _at(file, entry),
        ));
      }
    }
  }

  /// The geography manifest's map layers and node geometries.
  ///
  /// A layer names its sources in `source_citation_ids`, in the order its
  /// attribution names them; they become `map_layer_citations` rows (GEO-21,
  /// GEO-22). `asset_bytes` and `attribution` are the pipeline's own records,
  /// which `npm run check` verifies: the size is the asset's, and the
  /// attribution is composed from the citations, so neither is stored.
  void _collectGeography(DatasetFile file, YamlMap document) {
    const sections = {'map_layers', 'node_geometries'};
    final unknown = [
      for (final key in document.keys)
        if (!sections.contains(key)) '$key',
    ];
    if (unknown.isNotEmpty) {
      throw DatasetFormatException(
        '${file.path}: unknown sections: ${unknown.join(', ')}',
      );
    }
    for (final MapEntry(:key, :value) in document.nodes.entries) {
      final table = '${(key as YamlNode).value}';
      if (value is! YamlList) {
        throw DatasetFormatException(
          '${_at(file, value)}: section "$table" must be a list',
        );
      }
      for (final entry in value.nodes) {
        final at = _at(file, entry);
        final row = _mapping(table, entry, at);
        if (table == 'map_layers') {
          row.remove('asset_bytes');
          row.remove('attribution');
          final sources = row.remove('source_citation_ids');
          if (sources is! YamlList ||
              sources.isEmpty ||
              sources.any((s) => s is! String)) {
            throw DatasetFormatException(
              '$at: map_layers (${row['id']}): source_citation_ids must list '
              'the sources of the layer',
            );
          }
          for (final (i, source) in sources.indexed) {
            _rows.putIfAbsent('map_layer_citations', () => []).add((
              row: _checkRow(
                'map_layer_citations',
                datasetSections['map_layer_citations']!,
                {
                  'map_layer_id': row['id'],
                  'source_citation_id': source,
                  'position': i + 1,
                },
                at,
              ),
              at: at,
            ));
          }
        }
        _rows.putIfAbsent(table, () => []).add((
          row: _checkRow(table, datasetSections[table]!, row, at),
          at: at,
        ));
      }
    }
  }

  static DatasetLocation _at(DatasetFile file, YamlNode node) =>
      DatasetLocation(file.path, node.span.start.line + 1);

  /// The row [entry] with its defaults and computed columns filled in.
  Map<String, dynamic> _check(
    String table,
    DatasetSection section,
    YamlNode entry,
    DatasetLocation at,
  ) => _checkRow(table, section, _mapping(table, entry, at), at);

  static Map<String, dynamic> _mapping(
    String table,
    YamlNode entry,
    DatasetLocation at,
  ) {
    if (entry is! YamlMap) {
      throw DatasetFormatException('$at: a row of $table must be a mapping');
    }
    return <String, dynamic>{
      for (final MapEntry(:key, :value) in entry.entries) '$key': value,
    };
  }

  /// [row] with its defaults and computed columns filled in.
  Map<String, dynamic> _checkRow(
    String table,
    DatasetSection section,
    Map<String, dynamic> row,
    DatasetLocation at,
  ) {
    final id = row['id'];
    final where = '$at: $table${id == null ? '' : ' ($id)'}';

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
    for (final column in section.json) {
      final value = row[column];
      if (value == null) continue;
      if (value is! YamlMap) {
        throw DatasetFormatException('$where: $column must be a mapping');
      }
      row[column] = jsonEncode(_plain(value));
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
    return row;
  }

  /// Every row's location by key. A key written twice, in one file or in two,
  /// is reported with both places.
  Map<String, Map<String, DatasetLocation>> _locate() {
    final locations = <String, Map<String, DatasetLocation>>{};
    final twice = <String>[];
    for (final MapEntry(key: table, value: rows) in _rows.entries) {
      final section = datasetSections[table]!;
      final byKey = locations[table] = {};
      for (final (:row, :at) in rows) {
        final key = section.keyOf(row);
        final first = byKey[key];
        if (first == null) {
          byKey[key] = at;
        } else {
          twice.add('$table "$key" is written twice, at $first and $at');
        }
      }
    }
    if (twice.isNotEmpty) throw DatasetFormatException(twice.join('\n'));
    return locations;
  }

  List<D> _convert<D>(String table, _FromJson<D> fromJson) => [
    for (final (:row, :at) in _rows[table]!)
      _fromJson(table, row, at, fromJson),
  ];

  static D _fromJson<D>(
    String table,
    Map<String, dynamic> row,
    DatasetLocation at,
    _FromJson<D> fromJson,
  ) {
    try {
      return fromJson(row, serializer: _serializer);
    } on TypeError catch (error) {
      final id = row['id'];
      throw DatasetFormatException(
        '$at: $table${id == null ? '' : ' ($id)'}: a value has the wrong '
        'type: $error',
      );
    }
  }

  /// The digest of the manifest's text, then of each included file's path,
  /// as the manifest writes it, and text, each set off by a zero byte.
  String _checksum(List<String> includes) {
    final bytes = BytesBuilder(copy: false)..add(utf8.encode(files.first.text));
    for (var i = 0; i < includes.length; i++) {
      bytes
        ..addByte(0)
        ..add(utf8.encode(includes[i]))
        ..addByte(0)
        ..add(utf8.encode(files[i + 1].text));
    }
    return 'sha256:${sha256.convert(bytes.takeBytes())}';
  }

  /// [value] without its YAML wrappers, as `jsonEncode` takes it.
  static Object? _plain(Object? value) => switch (value) {
    YamlMap() => {
      for (final MapEntry(:key, :value) in value.entries) '$key': _plain(value),
    },
    YamlList() => [for (final element in value) _plain(element)],
    _ => value,
  };

  static bool _isIsoDate(Object value) {
    if (value is! String || !_isoDate.hasMatch(value)) return false;
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    return parsed != null && parsed.toIso8601String().startsWith(value);
  }
}

YamlMap _loadYaml(DatasetFile file) {
  final Object? document;
  try {
    document = loadYaml(file.text, sourceUrl: Uri.file(file.path));
  } on YamlException catch (error) {
    final line = error.span?.start.line;
    throw DatasetFormatException(
      '${file.path}${line == null ? '' : ':${line + 1}'}: not valid YAML: '
      '${error.message}',
    );
  }
  if (document is! YamlMap) {
    throw DatasetFormatException(
      '${file.path}: the top level must be a mapping',
    );
  }
  return document;
}

/// The manifest's `includes`: paths relative to its folder, each a `.yaml`
/// file inside that folder, listed once.
List<String> _includes(String path, YamlMap manifest) {
  final value = manifest['includes'];
  if (value == null) return const [];
  if (value is! YamlList) {
    throw DatasetFormatException('$path: includes must be a list of paths');
  }
  final includes = <String>[];
  for (final include in value) {
    final valid =
        include is String &&
        include.endsWith('.yaml') &&
        !include.startsWith('/') &&
        !include.contains(r'\') &&
        !include.split('/').any((part) => part.isEmpty || part.startsWith('.'));
    if (!valid) {
      throw DatasetFormatException(
        '$path: "$include" is not the relative path of a .yaml file in the '
        "manifest's folder",
      );
    }
    if (includes.contains(include)) {
      throw DatasetFormatException('$path: $include is included twice');
    }
    includes.add(include);
  }
  return includes;
}

/// The manifest's `geography`: the relative path of a `.yaml` file, which
/// may lead out of the manifest's folder with `..`, resolved against it.
String? _geography(String path, YamlMap manifest) {
  final value = manifest['geography'];
  if (value == null) return null;
  final folder = _folderOf(path);
  final parts = [
    for (final part in folder.split('/'))
      if (part.isNotEmpty) part,
  ];
  var valid =
      value is String &&
      value.endsWith('.yaml') &&
      !value.startsWith('/') &&
      !value.contains(r'\');
  if (valid) {
    for (final part in value.split('/')) {
      if (part == '..' && parts.isNotEmpty) {
        parts.removeLast();
      } else if (part.isEmpty || part.startsWith('.')) {
        valid = false;
        break;
      } else {
        parts.add(part);
      }
    }
  }
  if (!valid) {
    throw DatasetFormatException(
      '$path: geography "$value" is not the relative path of a .yaml file',
    );
  }
  // A folder from the root, such as /tmp/x on Linux, stays one.
  return '${folder.startsWith('/') ? '/' : ''}${parts.join('/')}';
}

String _slashes(String path) => path.replaceAll(r'\', '/');

String _folderOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}
