import 'dart:convert';
import 'dart:io';

import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:yaml/yaml.dart';

const marketAreaPath = 'assets/curriculum/areas/diploma_market_systems.yaml';
const marketTemplatePath =
    'assets/curriculum/templates/diploma_market_systems.yaml';
const marketScopePath = 'assets/curriculum/track_scope.yaml';
const marketIncludes = [
  'areas/diploma_market_systems.yaml',
  'templates/diploma_market_systems.yaml',
];

Map<String, dynamic> _mapping(String text) =>
    jsonDecode(jsonEncode(loadYaml(text))) as Map<String, dynamic>;

CurriculumDataset _release(Map<String, dynamic> manifest) =>
    CurriculumDataset.loadSync(
      curriculumAssetPath,
      (path) => path == curriculumAssetPath
          ? jsonEncode(manifest)
          : File(path).readAsStringSync(),
    );

/// Exact source files of the observed 0.24.69 predecessor, including the
/// original manifest and geography metadata. Never synthesized from a newer
/// release. This fixture contains curriculum text only, no learner data.
CurriculumDataset marketPredecessor() {
  final bytes = File('test/fixtures/d2_market_0_24_69.json.gz')
      .readAsBytesSync();
  final snapshot = (jsonDecode(utf8.decode(gzip.decode(bytes))) as Map)
      .cast<String, String>();
  return CurriculumDataset.loadSync(
    curriculumAssetPath,
    (path) => snapshot[path]!,
  );
}

/// Structure comparison only: current source files without this module.
/// This is not an installable predecessor or historical release fixture.
CurriculumDataset marketStructuralBaseline() {
  final manifest = _mapping(File(curriculumAssetPath).readAsStringSync());
  manifest['includes'] = (manifest['includes'] as List)
      .cast<String>()
      .where((path) => !marketIncludes.contains(path))
      .toList();
  return _release(manifest);
}

/// Local integration preview only. Does not write the canonical manifest or
/// reserve a release number. If already registered, tests use the real bundle.
/// The integrating agent must choose and test the final release metadata.
CurriculumDataset marketCandidate({
  String version = '0.24.71',
  String publishedAt = '2026-10-02T22:15:36.000Z',
  String? manifestText,
}) {
  final source = manifestText ?? File(curriculumAssetPath).readAsStringSync();
  final manifest = _mapping(source);
  final includes = (manifest['includes'] as List).cast<String>();
  if (marketIncludes.every(includes.contains)) {
    return CurriculumDataset.loadSync(
      curriculumAssetPath,
      (path) =>
          path == curriculumAssetPath ? source : File(path).readAsStringSync(),
    );
  }
  manifest
    ..['dataset_version'] = version
    ..['published_at'] = publishedAt
    ..['includes'] = {...marketIncludes, ...includes}.toList();
  return _release(manifest);
}

/// A preview of the scope registration, leaving canonical scope unchanged.
String marketCandidateScope() {
  final scope = _mapping(File(marketScopePath).readAsStringSync());
  final tracks = scope['tracks'] as Map<String, dynamic>;
  final l4 = tracks['WSET_L4'] as Map<String, dynamic>;
  final objectives = (l4['objectives'] as List).cast<Map<String, dynamic>>();
  final routes = objectives.singleWhere(
    (row) => row['id'] == 'wset_l4.business.routes',
  );
  final covers = routes['covers'] as Map<String, dynamic>;
  final within = (covers['within'] as List).cast<String>();
  final area = _mapping(File(marketAreaPath).readAsStringSync());
  final items = (area['knowledge_items'] as List).cast<Map<String, dynamic>>();
  covers['within'] = {
    ...within,
    ...items.map((row) => row['subject_id'] as String),
  }.toList();
  return jsonEncode(scope);
}

void main() {
  final canonical = CurriculumDataset.loadSync(
    curriculumAssetPath,
    (path) => File(path).readAsStringSync(),
  );
  final candidate = marketCandidate();
  final validation = validateDataset(candidate);
  final report = {
    'previewOnly': candidate.checksum != canonical.checksum,
    'canonicalManifestUnchanged': true,
    'canonicalVersion': canonical.version,
    'candidateVersion': candidate.version,
    'checksum': candidate.checksum,
    'marketItems': candidate.knowledgeItems
        .where((row) => row.id.startsWith('ki_d2market_'))
        .length,
    'errors': validation.errors.map((issue) => issue.toString()).toList(),
    'factualVerification': false,
    'curriculumComplete': false,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  if (validation.errors.isNotEmpty) exitCode = 1;
}
