import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';

void main() {
  test('folds case and removes diacritics beyond ASCII', () {
    expect(normalizeName('Châteauneuf-du-Pape'), 'chateauneuf du pape');
    expect(normalizeName('CÔTE-RÔTIE'), 'cote rotie');
    expect(normalizeName('Rhône'), normalizeName('RHONE'));
    expect(normalizeName('Mourvèdre'), 'mourvedre');
  });

  test('handles ligatures and decomposed accents', () {
    expect(normalizeName('Œil de Perdrix'), 'oeil de perdrix');
    expect(normalizeName('Ro\u0302ne'), 'rone');
  });

  test('folds punctuation and spacing into single spaces', () {
    expect(normalizeName("Côte d'Or"), 'cote d or');
    expect(normalizeName('  Pouilly–Fumé  '), 'pouilly fume');
    expect(
      normalizeName('Crozes-Hermitage'),
      normalizeName('Crozes Hermitage'),
    );
  });

  test('drops a trailing appellation category', () {
    expect(normalizeName('Barolo DOCG'), 'barolo');
    expect(normalizeName('Chablis AOC'), normalizeName('Chablis'));
    expect(normalizeName('Rioja DOCa'), 'rioja');
    expect(normalizeName('DOC'), 'doc', reason: 'a lone word is kept');
  });

  test('produces what the schema accepts: no upper case', () {
    for (final name in ['ÉLÉGANT', 'Łódź', 'Straße', 'Ångström']) {
      expect(normalizeName(name), isNot(matches(RegExp('[A-Z]'))));
    }
  });
}
