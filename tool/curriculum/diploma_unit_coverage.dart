import 'dart:convert';
import 'dart:io';

import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

const diplomaMatrixPaths = [
  'docs/research/diploma-unit-coverage-d1-d2.json',
  'docs/research/diploma-unit-coverage-d3.json',
  'docs/research/diploma-unit-coverage-d4-d6.json',
];

/// Checks editorial anchors. Passing means references resolve; it does not
/// establish factual accuracy, question generation, or Diploma sufficiency.
Map<String, Object?> auditDiplomaMatrix(
  CurriculumDataset dataset,
  List<Map<String, dynamic>> documents, {
  required String Function(String path) read,
}) {
  final errors = <String>[];
  final ids = <String>{};
  final rows = <Map<String, Object?>>[];
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final templates = {
    for (final template in dataset.questionTemplates) template.id,
  };
  final sources = {for (final source in dataset.sourceCitations) source.id};
  final citedItems = {
    for (final citation in dataset.knowledgeItemCitations)
      if (sources.contains(citation.sourceCitationId)) citation.knowledgeItemId,
  };
  final tracks = {'WSET_L4'};
  final certifications = {
    for (final track in dataset.certifications) track.id: track,
  };
  var included = certifications['WSET_L4']?.includesCertificationId;
  while (included != null && tracks.add(included)) {
    included = certifications[included]?.includesCertificationId;
  }
  final mappings = {
    for (final mapping in dataset.certificationKnowledgeMappings)
      if (tracks.contains(mapping.certificationId)) mapping.knowledgeItemId,
  };
  const outcomes = {
    'D1': {'1.1', '1.2', '1.3'},
    'D2': {'2.1', '2.2', '2.3'},
    'D3': {'3.1', '3.2'},
    'D4': {'4.1', '4.2'},
    'D5': {'5.1', '5.2'},
    'D6': {'6.1'},
  };
  final seenOutcomes = <String>{};
  for (final document in documents) {
    if (document['schemaVersion'] != 1 || document['rows'] is! List) {
      errors.add('Matrix document requires schemaVersion 1 and rows.');
      continue;
    }
    for (final value in document['rows'] as List) {
      if (value is! Map<String, dynamic>) {
        errors.add('Matrix row must be an object.');
        continue;
      }
      final id = value['id'];
      final unit = value['unit'];
      final label = id is String ? id : '(unnamed)';
      if (id is! String || id.isEmpty || !ids.add(id)) {
        errors.add('$label: empty or duplicate row ID.');
      }
      if (!outcomes.containsKey(unit)) errors.add('$label: unknown unit.');
      for (final field in ['subject', 'gap']) {
        if (value[field] is! String ||
            (value[field] as String).trim().isEmpty) {
          errors.add('$label: $field must explain the editorial scope.');
        }
      }
      if (!{'partial', 'needs_review', 'missing'}.contains(value['status']) ||
          value['reviewRequired'] != true) {
        errors.add('$label: unsupported completion or review claim.');
      }
      List<dynamic> list(String field) {
        if (value[field] is! List) {
          errors.add('$label: $field must be a list.');
          return [];
        }
        return value[field] as List;
      }

      final rowOutcomes = list('outcomes');
      if (rowOutcomes.isEmpty) {
        errors.add('$label: needs an outcome reference.');
      }
      for (final outcome in rowOutcomes) {
        if (!(outcomes[unit]?.contains(outcome) ?? false)) {
          errors.add('$label: outcome $outcome does not belong to $unit.');
        } else {
          seenOutcomes.add(outcome as String);
        }
      }
      if (value.containsKey('assessmentCriteria')) {
        final criteria = list('assessmentCriteria');
        for (final criterion in criteria) {
          if (unit != 'D6' ||
              !{'6.1.1', '6.1.2', '6.1.3'}.contains(criterion)) {
            errors.add('$label: unsupported assessment criterion $criterion.');
          }
        }
      }
      final itemIds = list('itemIds');
      final templateIds = list('templateIds');
      final features = list('featureRefs');
      final rowItems = <String>{};
      for (final itemId in itemIds) {
        if (itemId is! String || !items.containsKey(itemId)) {
          errors.add('$label: missing item $itemId.');
          continue;
        }
        rowItems.add(itemId);
        if (!mappings.contains(itemId)) {
          errors.add('$label: $itemId has no effective Diploma mapping.');
        }
        if (!citedItems.contains(itemId)) {
          errors.add('$label: $itemId has no resolving source citation.');
        }
      }
      for (final templateId in templateIds) {
        if (!templates.contains(templateId)) {
          errors.add('$label: missing template $templateId.');
        }
      }
      for (final feature in features) {
        if (feature is! Map ||
            feature['path'] is! String ||
            !_safeRelative(feature['path'] as String)) {
          errors.add('$label: unsafe or malformed feature reference.');
          continue;
        }
        final path = feature['path'] as String;
        try {
          final text = read(path);
          final featureId = feature['id'];
          if (featureId != null &&
              (featureId is! String ||
                  !path.endsWith('.json') ||
                  !_containsId(jsonDecode(text), featureId))) {
            errors.add('$label: feature ID $featureId is absent from $path.');
          }
        } on Object catch (error) {
          errors.add('$label: cannot resolve $path: $error');
        }
      }
      if (itemIds.isEmpty &&
          templateIds.isEmpty &&
          features.isEmpty &&
          value['status'] != 'missing') {
        errors.add('$label: represented row has no anchors.');
      }
      rows.add({
        ...value,
        'anchoredItemCount': rowItems.length,
        'verifiedItemCount': rowItems
            .where((id) => items[id]!.verificationStatus == 'verified')
            .length,
      });
    }
  }
  for (final unit in outcomes.keys) {
    if (!rows.any((row) => row['unit'] == unit)) {
      errors.add('$unit: no editorial rows.');
    }
  }
  for (final outcome in outcomes.values.expand((value) => value)) {
    if (!seenOutcomes.contains(outcome)) {
      errors.add('Outcome $outcome is absent.');
    }
  }
  return {
    'schemaVersion': 1,
    'datasetVersion': dataset.version,
    'datasetChecksum': dataset.checksum,
    'referencesValid': errors.isEmpty,
    'curriculumComplete': false,
    'interpretation':
        'Reference integrity only. Anchors are samples, not a '
        'complete inventory or proof of factual or assessment sufficiency.',
    'errors': errors,
    'units': {
      for (final unit in outcomes.keys)
        unit: {
          'rowCount': rows.where((row) => row['unit'] == unit).length,
          'statuses': {
            for (final status in ['partial', 'needs_review', 'missing'])
              status: rows
                  .where(
                    (row) => row['unit'] == unit && row['status'] == status,
                  )
                  .length,
          },
        },
    },
    'rows': rows,
  };
}

bool _safeRelative(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.contains(r'\') &&
    !path.contains(':') &&
    !path.split('/').any((part) => part == '..' || part.isEmpty);

bool _containsId(Object? value, String id) {
  if (value is Map) {
    if (value['id'] == id || value['unitId'] == id) return true;
    return value.values.any((child) => _containsId(child, id));
  }
  return value is List && value.any((child) => _containsId(child, id));
}

void main(List<String> args) {
  if (args.isNotEmpty) {
    stderr.writeln(
      'Run dart run tool/curriculum/diploma_unit_coverage.dart '
      'from the repository root; JSON is written to stdout.',
    );
    exitCode = 64;
    return;
  }
  try {
    final dataset = CurriculumDataset.loadSync(
      curriculumAssetPath,
      (path) => File(path).readAsStringSync(),
    );
    final report = auditDiplomaMatrix(dataset, [
      for (final path in diplomaMatrixPaths)
        Map<String, dynamic>.from(
          jsonDecode(File(path).readAsStringSync()) as Map,
        ),
    ], read: (path) => File(path).readAsStringSync());
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    if (report['referencesValid'] != true) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Diploma matrix could not be audited: $error');
    exitCode = 1;
  }
}
