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

  test('whole percentage tokens reject signed, malformed and range values', () {
    for (final raw in [
      '100.5%',
      '130,5%',
      '-12.5%',
      '+12.5%',
      '−12.5%',
      '±12.5%',
      '13.123%',
      '13..5%',
      '13,5.5%',
      '13 . 5%',
      '12-14%',
      '12 - 14%',
      '12–14%',
      '12 — 14%',
      '12/14%',
      '12 to 14%',
      '1e2%',
    ]) {
      final proposal = LabelProposal.fromRecognizedText(raw);
      expect(proposal.abvPercent, isNull, reason: raw);
      expect(proposal.warnings, contains('percent_not_offered'), reason: raw);
    }
  });

  test('wine alcohol bounds remain greater than zero and at most thirty', () {
    for (final raw in ['0%', '0.00%', '30.01%', '31%', '100%']) {
      final proposal = LabelProposal.fromRecognizedText(raw);
      expect(proposal.abvPercent, isNull, reason: raw);
      expect(proposal.warnings, contains('percent_not_offered'), reason: raw);
    }
    expect(LabelProposal.fromRecognizedText('0.25% alcohol').abvPercent, 0.25);
    expect(LabelProposal.fromRecognizedText('30% alcohol').abvPercent, 30);
  });

  test(
    'valid comma and period values survive ordinary surrounding label text',
    () {
      final labels = {
        'EXAMPLE 2020 Alcohol 13.5% vol.': 13.5,
        'alc.13,5% vol': 13.5,
        'alc.13.5%vol': 13.5,
        'Wine (12%)': 12.0,
        '12.50 % alcohol': 12.5,
        'NV\nABV: 11,25 %': 11.25,
      };
      for (final entry in labels.entries) {
        final proposal = LabelProposal.fromRecognizedText(entry.key);
        expect(proposal.abvPercent, entry.value, reason: entry.key);
        expect(proposal.warnings, isEmpty, reason: entry.key);
      }
      expect(LabelProposal.fromRecognizedText(labels.keys.first).vintage, 2020);
      expect(
        LabelProposal.fromRecognizedText(labels.keys.last).isNonVintage,
        isTrue,
      );
    },
  );

  test('a valid value beside an invalid percentage remains ambiguous', () {
    final proposal = LabelProposal.fromRecognizedText('13.5% 100.5%');
    expect(proposal.abvPercent, isNull);
    expect(proposal.warnings, contains('multiple_percent_tokens'));
  });

  test('year-like digits inside a percentage are never a vintage', () {
    for (final raw in ['2005%', '2018%', '2018.5%', '2018,5%']) {
      final proposal = LabelProposal.fromRecognizedText(raw);
      expect(proposal.vintage, isNull, reason: raw);
      expect(proposal.abvPercent, isNull, reason: raw);
    }
    final ordinary = LabelProposal.fromRecognizedText('BOTTLE 2019 13.5%');
    expect(ordinary.vintage, 2019);
    expect(ordinary.abvPercent, 13.5);
  });
}
