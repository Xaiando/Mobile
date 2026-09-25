import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/journal/journal_matcher.dart';
import 'package:sommelier/core/journal/wine_journal.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

KnowledgeNode _node(String id, String type, String name) => KnowledgeNode(
  id: id,
  nodeType: type,
  name: name,
  nameNorm: normalizeName(name),
);

/// A matcher over [nodes], each with its own name only.
JournalMatcher _matcher(List<KnowledgeNode> nodes) => JournalMatcher([
  for (final node in nodes) (norm: node.nameNorm, node: node),
]);

List<String> _ids(List<NodeSuggestion> suggestions) => [
  for (final suggestion in suggestions) suggestion.node.id,
];

void main() {
  group('on the bundled curriculum', () {
    late AppDatabase db;
    late JournalMatcher matcher;

    setUpAll(() async {
      db = openTestDatabase();
      await CurriculumIngester(db).ensureCurrent(bundledDataset());
      matcher = await JournalMatcher.load(db);
    });
    tearDownAll(() => db.close());

    test('finds the appellation and grapes a label names', () {
      final found = matcher.suggest(
        const JournalDraft(
          appellationText: 'Barolo DOCG',
          grapesText: 'Nebbiolo',
        ),
      );
      expect(_ids(found), containsAll(['n_geo_barolo', 'n_grape_nebbiolo']));
      expect(found.every((s) => s.isLikely), isTrue);
    });

    test('reads accents, case, and a synonym', () {
      final found = matcher.suggest(
        const JournalDraft(appellationText: 'CHÂTEAUNEUF-DU-PAPE'),
      );
      expect(_ids(found), ['n_geo_chateauneuf_du_pape']);
      expect(
        _ids(matcher.suggest(const JournalDraft(appellationText: 'Bourgogne'))),
        contains('n_geo_burgundy'),
        reason: 'an alternative name of Burgundy',
      );
    });

    test('suggests a near miss, but not as a likely link', () {
      final found = matcher.suggest(
        const JournalDraft(appellationText: 'Barollo'),
      );
      expect(_ids(found), ['n_geo_barolo']);
      expect(found.single.isExact, isFalse);
      expect(found.single.isLikely, isFalse);
    });
  });

  test('prefers the longest name, and splits a list of grapes', () {
    final matcher = _matcher([
      _node('n_geo_cote_de_beaune', 'subregion', 'Côte de Beaune'),
      _node('n_geo_beaune', 'appellation', 'Beaune'),
      _node('n_grape_nebbiolo', 'grape', 'Nebbiolo'),
      _node('n_grape_barbera', 'grape', 'Barbera'),
    ]);
    expect(
      _ids(
        matcher.suggest(const JournalDraft(appellationText: 'Côte de Beaune')),
      ),
      ['n_geo_cote_de_beaune'],
    );
    expect(
      _ids(
        matcher.suggest(const JournalDraft(grapesText: 'Nebbiolo & Barbera')),
      ),
      unorderedEquals(['n_grape_nebbiolo', 'n_grape_barbera']),
    );
  });

  test('marks a name shared by two nodes as ambiguous', () {
    final matcher = _matcher([
      _node('n_geo_chablis', 'appellation', 'Chablis'),
      _node('n_geo_chablis_area', 'informal_area', 'Chablis'),
    ]);
    final found = matcher.suggest(
      const JournalDraft(appellationText: 'Chablis'),
    );
    expect(found, hasLength(2));
    expect(found.every((s) => s.isAmbiguous && !s.isLikely), isTrue);
  });

  test('never guesses from short words', () {
    final matcher = _matcher([_node('n_geo_bandol', 'appellation', 'Bandol')]);
    expect(matcher.suggest(const JournalDraft(producerName: 'Band')), isEmpty);
  });

  test('editDistance counts edits and stops past its limit', () {
    expect(editDistance('barolo', 'barollo'), 1);
    expect(editDistance('nebbiolo', 'nebiolo'), 1);
    expect(editDistance('syrah', 'shiraz'), 3);
    expect(editDistance('syrah', 'shiraz', limit: 1), 2);
  });
}
