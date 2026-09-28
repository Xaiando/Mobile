import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/journal/label_proposal.dart';

void main() {
  final corpus = jsonDecode(
    File('docs/research/cellar-scan/synthetic_labels.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  for (final row in corpus['cases'] as List<dynamic>) {
    final fixture = row as Map<String, dynamic>;
    final expected = fixture['expect'] as Map<String, dynamic>;
    test('synthetic label ${fixture['id']} offers only safe fields', () {
      final proposal = LabelProposal.fromRecognizedText(
        fixture['raw_text'] as String,
      );
      if (expected.containsKey('vintage')) {
        expect(proposal.vintage, expected['vintage']);
      }
      if (expected.containsKey('non_vintage')) {
        expect(proposal.isNonVintage, expected['non_vintage']);
      }
      if (expected.containsKey('abv')) {
        expect(proposal.abvPercent, expected['abv']);
      }
      if (expected.containsKey('warnings')) {
        expect(proposal.warnings, expected['warnings']);
      }
    });
  }

  test('non-vintage phrase wins over a printed year', () {
    final proposal = LabelProposal.fromRecognizedText('Sans année 2018 12,5%');
    expect(proposal.isNonVintage, isTrue);
    expect(proposal.vintage, isNull);
    expect(proposal.abvPercent, 12.5);
    expect(proposal.warnings, contains('nv_and_year'));
  });

  test('two plausible alcohol percentages need human choice', () {
    final proposal = LabelProposal.fromRecognizedText('13% 14%');
    expect(proposal.abvPercent, isNull);
    expect(proposal.warnings, contains('multiple_percent_tokens'));
  });
}
