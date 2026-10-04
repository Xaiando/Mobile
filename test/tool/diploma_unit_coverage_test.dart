import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

import '../../tool/curriculum/diploma_unit_coverage.dart';

void main() {
  final dataset = CurriculumDataset.loadSync(
    curriculumAssetPath,
    (path) => File(path).readAsStringSync(),
  );
  final itemId = dataset.certificationKnowledgeMappings
      .firstWhere(
        (mapping) =>
            mapping.certificationId == 'WSET_L4' &&
            dataset.knowledgeItemCitations.any(
              (citation) => citation.knowledgeItemId == mapping.knowledgeItemId,
            ),
      )
      .knowledgeItemId;
  List<Map<String, dynamic>> documents() => [
    {
      'schemaVersion': 1,
      'rows': [
        for (final (unit, outcomes) in [
          ('D1', ['1.1', '1.2', '1.3']),
          ('D2', ['2.1', '2.2', '2.3']),
          ('D3', ['3.1', '3.2']),
          ('D4', ['4.1', '4.2']),
          ('D5', ['5.1', '5.2']),
          ('D6', ['6.1']),
        ])
          {
            'id': '${unit.toLowerCase()}.sample',
            'unit': unit,
            'subject': 'Sample editorial scope',
            'outcomes': outcomes,
            'itemIds': [itemId],
            'templateIds': <String>[],
            'featureRefs': [
              {'path': 'assets/study/sample.json', 'id': 'sample'},
            ],
            'status': 'partial',
            'gap': 'Human review and further applications remain.',
            'reviewRequired': true,
          },
      ],
    },
  ];
  Map<String, Object?> audit(List<Map<String, dynamic>> rows) =>
      auditDiplomaMatrix(
        dataset,
        rows,
        read: (_) => '{"units":[{"unitId":"sample"}]}',
      );
  Map<String, dynamic> first(List<Map<String, dynamic>> rows) =>
      (rows.first['rows'] as List).first as Map<String, dynamic>;

  test('valid references remain explicitly incomplete and unverified', () {
    final report = audit(documents());
    expect(report['errors'], isEmpty);
    expect(report['referencesValid'], true);
    expect(report['curriculumComplete'], false);
    expect((report['rows'] as List).first['verifiedItemCount'], 0);
    expect((report['units'] as Map).keys, ['D1', 'D2', 'D3', 'D4', 'D5', 'D6']);
  });
  test('an unresolved item or template cannot silently count as coverage', () {
    final rows = documents();
    first(rows)['itemIds'] = ['ki_missing'];
    first(rows)['templateIds'] = ['qt_missing'];
    final report = audit(rows);
    expect(report['referencesValid'], false);
    expect((report['errors'] as List).join(' '), contains('missing item'));
    expect((report['errors'] as List).join(' '), contains('missing template'));
  });
  test('wrong-unit outcomes and absent outcomes fail the audit', () {
    final rows = documents();
    first(rows)['outcomes'] = ['6.1'];
    final report = audit(rows);
    expect(report['referencesValid'], false);
    expect((report['errors'] as List).join(' '), contains('does not belong'));
    expect(
      (report['errors'] as List).join(' '),
      contains('Outcome 1.1 is absent'),
    );
  });
  test('duplicate scope IDs and completion claims are rejected', () {
    final rows = documents();
    final all = rows.first['rows'] as List;
    all[1]['id'] = all[0]['id'];
    first(rows)['status'] = 'complete';
    first(rows)['reviewRequired'] = false;
    final report = audit(rows);
    expect(report['referencesValid'], false);
    expect((report['errors'] as List).join(' '), contains('duplicate'));
    expect((report['errors'] as List).join(' '), contains('completion'));
  });
  test('feature anchors require a real ID in a safe relative path', () {
    for (final path in [
      '../private.json',
      '/absolute.json',
      r'C:\private.json',
    ]) {
      final rows = documents();
      first(rows)['featureRefs'] = [
        {'path': path, 'id': 'sample'},
      ];
      expect(audit(rows)['referencesValid'], false);
    }
    final rows = documents();
    first(rows)['featureRefs'] = [
      {'path': 'assets/study/sample.json', 'id': 'absent'},
    ];
    expect((audit(rows)['errors'] as List).join(' '), contains('is absent'));
  });
  test(
    'missing content can be recorded without pretending it is represented',
    () {
      final rows = documents();
      first(rows)['itemIds'] = <String>[];
      first(rows)['featureRefs'] = <Map<String, String>>[];
      first(rows)['status'] = 'missing';
      expect(audit(rows)['referencesValid'], true);
      first(rows)['status'] = 'partial';
      expect(audit(rows)['referencesValid'], false);
    },
  );
  test(
    'Diploma inherits lower WSET mappings but excludes CMS-only anchors',
    () {
      final inheritedTracks = {'WSET_L1', 'WSET_L2', 'WSET_L3', 'WSET_L4'};
      final inheritedIds = {
        for (final mapping in dataset.certificationKnowledgeMappings)
          if (inheritedTracks.contains(mapping.certificationId))
            mapping.knowledgeItemId,
      };
      for (final inheritedId in [
        'ki_vit_current_shoots',
        'ki_wset_found_acidity',
      ]) {
        final rows = documents();
        first(rows)['itemIds'] = [inheritedId];
        expect(audit(rows)['referencesValid'], true, reason: inheritedId);
      }
      final cmsOnly = dataset.certificationKnowledgeMappings
          .firstWhere(
            (mapping) =>
                mapping.certificationId.startsWith('CMS') &&
                !inheritedIds.contains(mapping.knowledgeItemId),
          )
          .knowledgeItemId;
      final rows = documents();
      first(rows)['itemIds'] = [cmsOnly];
      expect(
        (audit(rows)['errors'] as List).join(' '),
        contains('no effective Diploma mapping'),
      );
    },
  );
  test('D6 assessment references remain separate from its outcome', () {
    final rows = documents();
    final d6 = (rows.first['rows'] as List).last;
    d6['assessmentCriteria'] = ['6.1.1', '6.1.2', '6.1.3'];
    expect(audit(rows)['referencesValid'], true);
    d6['assessmentCriteria'] = ['4.1.1'];
    expect(audit(rows)['referencesValid'], false);
  });

  test(
    'actual unit matrix references resolve against the included release',
    () {
      final report = auditDiplomaMatrix(dataset, [
        for (final path in diplomaMatrixPaths)
          Map<String, dynamic>.from(
            jsonDecode(File(path).readAsStringSync()) as Map,
          ),
      ], read: (path) => File(path).readAsStringSync());
      expect(report['errors'], isEmpty);
      expect(report['curriculumComplete'], false);
    },
  );
}
