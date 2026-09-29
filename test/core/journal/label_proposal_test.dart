import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/journal_matcher.dart';
import 'package:sommelier/core/journal/label_proposal.dart';

KnowledgeNode _node(String id, String type, String name) => KnowledgeNode(
  id: id,
  nodeType: type,
  name: name,
  nameNorm: normalizeName(name),
);

JournalMatcher _matcher(List<KnowledgeNode> nodes) => JournalMatcher([
  for (final node in nodes) (norm: node.nameNorm, node: node),
]);

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
      if (expected.containsKey('producer')) {
        expect(proposal.producer, expected['producer']);
      }
      if (expected.containsKey('cuvee')) {
        expect(proposal.cuvee, expected['cuvee']);
      }
      if (expected.containsKey('appellation')) {
        expect(proposal.appellation, expected['appellation']);
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

  test(
    'offers distinct full-label fields without treating text as identity',
    () {
      final matcher = _matcher([
        _node('chablis', 'appellation', 'Chablis'),
        _node('chardonnay', 'grape', 'Chardonnay'),
      ]);
      final proposal = LabelProposal.fromRecognizedText(
        'Domaine des Roches\nCuvée Les Pierres\nChablis AOC\n'
        '100% Chardonnay\n2020\n13,5% vol',
        matcher: matcher,
      );
      expect(proposal.producer, 'Domaine des Roches');
      expect(proposal.cuvee, 'Les Pierres');
      expect(proposal.appellation, 'Chablis');
      expect(proposal.grapes, 'Chardonnay');
      expect(proposal.vintage, 2020);
      expect(proposal.abvPercent, 13.5);
      expect(proposal.warnings, isEmpty);
    },
  );

  test('recognizes only complete curriculum names on separate lines', () {
    final matcher = _matcher([
      _node('napa', 'region', 'Napa Valley'),
      _node('pinot', 'grape', 'Pinot Noir'),
      _node('chard', 'grape', 'Chardonnay'),
    ]);
    final proposal = LabelProposal.fromRecognizedText(
      'Producer: Example Estate\nNapa Valley\nPinot Noir & Chardonnay',
      matcher: matcher,
    );
    expect(proposal.producer, 'Example Estate');
    expect(proposal.appellation, 'Napa Valley');
    expect(proposal.grapes, 'Pinot Noir, Chardonnay');
    final fragment = LabelProposal.fromRecognizedText(
      'Napa Valley Cellars\nPinot Noir Reserve',
      matcher: matcher,
    );
    expect(fragment.appellation, isNull);
    expect(fragment.grapes, isNull);
  });

  test('withholds disputed names rather than choosing a label line', () {
    final proposal = LabelProposal.fromRecognizedText(
      'Producer: First Estate\nProducer: Second Estate\n'
      'Region: Barolo\nRegion: Chianti\n'
      'Grapes: Nebbiolo\nGrapes: Sangiovese',
    );
    expect(proposal.producer, isNull);
    expect(proposal.appellation, isNull);
    expect(proposal.grapes, isNull);
    expect(
      proposal.warnings,
      containsAll([
        'multiple_producer_candidates',
        'multiple_appellation_candidates',
        'multiple_grapes_candidates',
      ]),
    );
  });

  test('same-name curriculum ambiguity does not invent a place', () {
    final matcher = _matcher([
      _node('chablis_aoc', 'appellation', 'Chablis'),
      _node('chablis_area', 'informal_area', 'Chablis'),
    ]);
    final proposal = LabelProposal.fromRecognizedText(
      'Chablis',
      matcher: matcher,
    );
    expect(proposal.appellation, isNull);
    expect(proposal.warnings, contains('ambiguous_catalog_name'));
  });

  test('a recognized alias keeps the words printed on the label', () {
    final burgundy = _node('burgundy', 'region', 'Burgundy');
    final matcher = JournalMatcher([
      (norm: normalizeName('Bourgogne'), node: burgundy),
    ]);
    final proposal = LabelProposal.fromRecognizedText(
      'Bourgogne',
      matcher: matcher,
    );
    expect(proposal.appellation, 'Bourgogne');
  });

  test('legal and alcohol footer lines never become bottle names', () {
    final proposal = LabelProposal.fromRecognizedText(
      'Bottled by Example Winery\n'
      'Contains sulfites\n'
      'CHATEAU EXAMPLE 2016 2018 13.5%',
    );
    expect(proposal.producer, isNull);
    expect(proposal.cuvee, isNull);
    expect(proposal.appellation, isNull);
    expect(proposal.grapes, isNull);
  });

  test('a producer-looking name with an AOC suffix is not a place guess', () {
    final proposal = LabelProposal.fromRecognizedText('Château des Roches AOC');
    expect(proposal.appellation, isNull);
    expect(proposal.producer, isNull);
  });

  test('a country-of-origin line does not obscure a named appellation', () {
    final proposal = LabelProposal.fromRecognizedText(
      'Origin: Italy\nBarolo DOCG',
    );
    expect(proposal.appellation, 'Barolo');
  });
}
