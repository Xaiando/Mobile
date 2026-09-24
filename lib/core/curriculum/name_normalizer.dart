/// Suffixes that name an appellation's legal category rather than the place.
const _categorySuffixes = {
  'aoc',
  'aop',
  'ava',
  'do',
  'doc',
  'docg',
  'doca',
  'dop',
  'igp',
  'igt',
};

/// Plain ASCII replacements for Latin letters with diacritics, and ligatures.
const _plainForms = {
  'a': 'àáâãäåāăą',
  'ae': 'æ',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņň',
  'o': 'òóôõöøōŏő',
  'oe': 'œ',
  'r': 'ŕŗř',
  's': 'śŝşš',
  'ss': 'ß',
  't': 'ţťŧ',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final _plainLetters = {
  for (final MapEntry(key: plain, value: letters) in _plainForms.entries)
    for (final letter in letters.split('')) letter: plain,
};

/// Combining diacritical marks, as found in decomposed (NFD) text.
final _combiningMarks = RegExp('[̀-ͯ]');

final _separators = RegExp(r'[^a-z0-9]+');

/// The matching key for a node name (`name_norm`, architecture audit §10).
///
/// Lower case, without diacritics, with punctuation folded into single
/// spaces and a trailing category suffix such as AOC or DOCG removed:
/// "Châteauneuf-du-Pape AOC" becomes "chateauneuf du pape". SQLite folds case
/// for ASCII only, so the key is computed here, identically on every platform.
String normalizeName(String name) {
  final plain = name
      .toLowerCase()
      .replaceAll(_combiningMarks, '')
      .split('')
      .map((letter) => _plainLetters[letter] ?? letter)
      .join();
  final words = plain
      .split(_separators)
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length > 1 && _categorySuffixes.contains(words.last)) {
    words.removeLast();
  }
  return words.join(' ');
}
