import '../journal/label_proposal.dart';

/// What the online reader says is printed on a label. Every value is a
/// suggestion that the learner confirms in the journal editor: it is never a
/// bottle identity and is never saved by itself.
///
/// The model's answer is untrusted text. [fromToolInput] keeps only short,
/// plain strings and numbers in range, and drops everything else, so a label
/// that carries instructions or an odd value cannot put them into the journal.
class LabelAiResult {
  const LabelAiResult({
    this.producer,
    this.cuvee,
    this.appellation,
    this.grapes,
    this.vintage,
    this.isNonVintage = false,
    this.abvPercent,
    this.country,
    this.textSeen = '',
  });

  final String? producer;
  final String? cuvee;
  final String? appellation;
  final String? grapes;
  final int? vintage;
  final bool isNonVintage;
  final double? abvPercent;
  final String? country;

  /// The label's text as the model transcribed it, one line per label line.
  final String textSeen;

  /// True when the reader found nothing the journal can use.
  bool get isEmpty =>
      producer == null &&
      cuvee == null &&
      appellation == null &&
      grapes == null &&
      vintage == null &&
      !isNonVintage &&
      abvPercent == null;

  static const _noAnswers = {
    'null',
    'none',
    'n/a',
    'na',
    'unknown',
    'not visible',
    'not shown',
    'not printed',
    'unreadable',
    '-',
  };

  /// A plain, short, single-line string, or null.
  static String? cleanText(Object? value, {int max = 80}) {
    if (value is! String) return null;
    final text = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F  ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty || text.length > max) return null;
    if (_noAnswers.contains(text.toLowerCase())) return null;
    return text;
  }

  static int? _vintage(Object? value) {
    final number = switch (value) {
      int() => value,
      double() => value == value.roundToDouble() ? value.round() : null,
      String() => int.tryParse(value.trim()),
      _ => null,
    };
    if (number == null || number < 1800 || number > 2100) return null;
    return number;
  }

  static double? _abv(Object? value) {
    final number = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value.replaceAll('%', '').trim()),
      _ => null,
    };
    if (number == null || number <= 0 || number > 30) return null;
    return (number * 10).round() / 10;
  }

  static String? _grapes(Object? value) {
    final parts = switch (value) {
      String() => value.split(RegExp(r'\s*(?:,|;|/|&)\s*')),
      List() => value,
      _ => const <Object?>[],
    };
    final grapes = <String>[];
    for (final part in parts) {
      final grape = cleanText(part, max: 40);
      if (grape != null && !grapes.contains(grape)) grapes.add(grape);
    }
    if (grapes.isEmpty || grapes.length > 6) return null;
    return grapes.join(', ');
  }

  /// Reads the `input` object of the model's `record_label` tool call.
  static LabelAiResult? fromToolInput(Object? input) {
    if (input is! Map) return null;
    final nonVintage = input['non_vintage'] == true;
    final vintage = nonVintage ? null : _vintage(input['vintage']);
    final lines = switch (input['text_seen']) {
      final String text =>
        text
            .split(RegExp(r'\r?\n'))
            .map((line) => cleanText(line, max: 120))
            .whereType<String>()
            .take(40)
            .join('\n'),
      _ => '',
    };
    return LabelAiResult(
      producer: cleanText(input['producer']),
      cuvee: cleanText(input['cuvee']),
      appellation: cleanText(input['appellation']),
      grapes: _grapes(input['grapes']),
      vintage: vintage,
      isNonVintage: nonVintage,
      abvPercent: _abv(input['abv_percent']),
      country: cleanText(input['country'], max: 40),
      textSeen: lines,
    );
  }

  /// The reader's answer in the form the journal editor offers as clues.
  LabelProposal toProposal() => LabelProposal(
    rawText: textSeen,
    producer: producer,
    cuvee: cuvee,
    appellation: appellation,
    grapes: grapes,
    vintage: vintage,
    isNonVintage: isNonVintage,
    abvPercent: abvPercent,
    warnings: const ['online_ai'],
  );
}

/// The clues of [primary], with [fallback]'s for what [primary] lacks.
LabelProposal mergeProposals(LabelProposal primary, LabelProposal fallback) =>
    LabelProposal(
      rawText: primary.rawText.isNotEmpty ? primary.rawText : fallback.rawText,
      producer: primary.producer ?? fallback.producer,
      cuvee: primary.cuvee ?? fallback.cuvee,
      appellation: primary.appellation ?? fallback.appellation,
      grapes: primary.grapes ?? fallback.grapes,
      vintage: primary.vintage ?? fallback.vintage,
      isNonVintage: primary.isNonVintage || fallback.isNonVintage,
      abvPercent: primary.abvPercent ?? fallback.abvPercent,
      warnings: {...primary.warnings, ...fallback.warnings}.toList(),
    );
