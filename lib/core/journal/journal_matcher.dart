import 'dart:math';

import '../curriculum/name_normalizer.dart';
import '../database/app_database.dart';
import 'wine_journal.dart';

/// A knowledge node that a journal entry's text names.
class NodeSuggestion {
  const NodeSuggestion(
    this.node, {
    required this.phrase,
    required this.isExact,
    required this.isAmbiguous,
  });

  final KnowledgeNode node;

  /// The words of the entry that name it, normalized.
  final String phrase;

  /// The phrase is the node's name or one of its alternative names; else it
  /// is a near miss, e.g. a typo.
  final bool isExact;

  /// The phrase names several nodes, so the learner must choose.
  final bool isAmbiguous;

  /// Whether to link it unless the learner says otherwise.
  bool get isLikely => isExact && !isAmbiguous;

  @override
  String toString() => '${node.id} ("$phrase"${isExact ? '' : ', near'})';
}

/// Finds the knowledge nodes a journal entry names (backlog J2): places and
/// grapes, by their names and alternative names (synonyms, former names,
/// abbreviations and spellings), then near misses a letter or two away.
///
/// The learner confirms every link, so the matcher may over-suggest, but
/// it never guesses from a fragment: a longer name wins over a shorter one
/// inside it ("Côte de Beaune" is not also "Beaune").
class JournalMatcher {
  JournalMatcher(Iterable<({String norm, KnowledgeNode node})> names) {
    for (final (:norm, :node) in names) {
      final nodes = _byName.putIfAbsent(norm, () => []);
      if (!nodes.any((n) => n.id == node.id)) nodes.add(node);
    }
    _longest = _byName.keys.fold(
      1,
      (longest, name) => max(longest, name.split(' ').length),
    );
  }

  /// The node types a wine label names.
  static const matchedTypes = {
    'country',
    'region',
    'subregion',
    'appellation',
    'informal_area',
    'site',
    'grape',
  };

  /// Loads every name of the [matchedTypes] nodes in [db].
  static Future<JournalMatcher> load(AppDatabase db) async {
    final nodes = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.nodeType.isIn(matchedTypes))).get();
    final byId = {for (final node in nodes) node.id: node};
    final alternatives = await (db.select(
      db.nodeAlternativeNames,
    )..where((a) => a.knowledgeNodeId.isIn(byId.keys))).get();
    return JournalMatcher([
      for (final node in nodes) (norm: node.nameNorm, node: node),
      for (final alternative in alternatives)
        (norm: alternative.nameNorm, node: byId[alternative.knowledgeNodeId]!),
    ]);
  }

  final _byName = <String, List<KnowledgeNode>>{};
  late final int _longest;

  static final _grapeSeparators = RegExp(r'[,;/&+]|\s(?:and|et|und|e|y)\s');

  /// The nodes [draft] names, exact matches first, each node once.
  List<NodeSuggestion> suggest(JournalDraft draft) {
    final found = <String, NodeSuggestion>{};
    void add(NodeSuggestion suggestion) {
      final existing = found[suggestion.node.id];
      if (existing == null || (!existing.isExact && suggestion.isExact)) {
        found[suggestion.node.id] = suggestion;
      }
    }

    final texts = [
      draft.appellationText,
      draft.producerName,
      draft.cuveeName,
      ...?draft.grapesText?.split(_grapeSeparators),
    ];
    for (final text in texts) {
      if (text == null || text.trim().isEmpty) continue;
      _scan(normalizeName(text).split(' '), add);
    }
    return found.values.toList()..sort((a, b) {
      if (a.isExact != b.isExact) return a.isExact ? -1 : 1;
      return a.node.name.compareTo(b.node.name);
    });
  }

  /// Matches [words] left to right, the longest name first at each word.
  void _scan(List<String> words, void Function(NodeSuggestion) add) {
    var i = 0;
    while (i < words.length) {
      var matched = 0;
      for (var n = min(_longest, words.length - i); n >= 1; n--) {
        final phrase = words.sublist(i, i + n).join(' ');
        final nodes = _byName[phrase];
        if (nodes == null) continue;
        for (final node in nodes) {
          add(
            NodeSuggestion(
              node,
              phrase: phrase,
              isExact: true,
              isAmbiguous: nodes.length > 1,
            ),
          );
        }
        matched = n;
        break;
      }
      if (matched == 0) {
        // Near misses: a word, or two words, one or two letters away.
        for (final n in [2, 1]) {
          if (i + n > words.length) continue;
          final phrase = words.sublist(i, i + n).join(' ');
          final near = _near(phrase);
          if (near.isEmpty) continue;
          for (final node in near) {
            add(
              NodeSuggestion(
                node,
                phrase: phrase,
                isExact: false,
                isAmbiguous: near.length > 1,
              ),
            );
          }
          matched = n;
          break;
        }
      }
      i += max(matched, 1);
    }
  }

  /// Names within one edit of [phrase], or two for long ones; none for
  /// short words, where a letter changes the meaning.
  List<KnowledgeNode> _near(String phrase) {
    if (phrase.length < 5) return const [];
    final allowed = phrase.length >= 9 ? 2 : 1;
    return [
      for (final MapEntry(key: name, value: nodes) in _byName.entries)
        if ((name.length - phrase.length).abs() <= allowed &&
            editDistance(name, phrase, limit: allowed) <= allowed)
          ...nodes,
    ];
  }
}

/// The Levenshtein distance between [a] and [b], or [limit] + 1 as soon as
/// it must exceed [limit].
int editDistance(String a, String b, {int limit = 1 << 30}) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    var best = current[0];
    for (var j = 1; j <= b.length; j++) {
      current[j] = min(
        min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1),
      );
      best = min(best, current[j]);
    }
    if (best > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}
