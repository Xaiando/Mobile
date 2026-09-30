/// Conservative suggestions from text recognized on a wine label. A proposal
/// is never a bottle identity and must be accepted in the journal editor.
class LabelProposal {
  const LabelProposal({
    required this.rawText,
    required this.vintage,
    required this.isNonVintage,
    required this.abvPercent,
    required this.warnings,
  });

  final String rawText;
  final int? vintage;
  final bool isNonVintage;
  final double? abvPercent;
  final List<String> warnings;

  /// Names, appellations, barcodes and LWINs cannot be identified by this
  /// parser. The learner enters those fields themselves.
  static LabelProposal fromRecognizedText(String text) {
    final raw = text.trim();
    final warnings = <String>[];
    if (raw.isEmpty) warnings.add('no_text');

    final nonVintage = RegExp(
      r'\b(?:NV|non[\s-]?vintage|sans\s+ann[ée]e)\b',
      caseSensitive: false,
    ).hasMatch(raw);

    // Capture the whole numeric candidate before checking its wine-ABV range.
    // A two-digit search can turn an unsupported 100.5% into a false 5% clue.
    final percentMatches = RegExp(
      r'(?:[+\-\u2212±]\s*)?\d+(?:\s*[.,/+\-\u2212±–—]\s*\d+)*\s*%',
    ).allMatches(raw).toList();

    final years = RegExp(r'\b(?:18\d{2}|19\d{2}|20\d{2}|2100)\b')
        .allMatches(raw)
        .where((match) {
          // A percent is an alcohol candidate, never a vintage.
          return !percentMatches.any(
            (percent) =>
                match.start >= percent.start && match.end <= percent.end,
          );
        })
        .map((match) => int.parse(match.group(0)!))
        .toList();
    if (years.length > 1) warnings.add('multiple_year_tokens');
    if (nonVintage && years.isNotEmpty) warnings.add('nv_and_year');
    final vintage = nonVintage || years.length != 1 ? null : years.single;

    final percents = [
      for (final match in percentMatches) _percentageValue(raw, match),
    ];
    if (percents.length > 1) warnings.add('multiple_percent_tokens');
    final percent = percents.length == 1 ? percents.single : null;
    final abv = percent != null && percent > 0 && percent <= 30
        ? percent
        : null;
    if (percents.length == 1 && abv == null) {
      warnings.add('percent_not_offered');
    }

    return LabelProposal(
      rawText: raw,
      vintage: vintage,
      isNonVintage: nonVintage,
      abvPercent: abv,
      warnings: List.unmodifiable(warnings),
    );
  }

  static double? _percentageValue(String raw, RegExpMatch match) {
    final before = raw.substring(0, match.start);
    // Preserve the previous word boundary. Do not recover a numeric suffix
    // embedded in a word, malformed decimal, exponent or split numeric range.
    if ((before.isNotEmpty &&
            RegExp(r'\w').hasMatch(before.substring(before.length - 1))) ||
        RegExp(r'\d[\d.,/+\-\u2212±–—\s]*[.,/+\-\u2212±–—]\s*$')
            .hasMatch(before) ||
        RegExp(r'\d\s+(?:to|à|a)\s*$', caseSensitive: false).hasMatch(before)) {
      return null;
    }
    final number = match.group(0)!.replaceAll('%', '').trim();
    // Require one unsigned value with the existing one/two decimal-place
    // precision. Signed values, ranges and malformed groups are not clues.
    if (!RegExp(r'^\d{1,2}(?:[.,]\d{1,2})?$').hasMatch(number)) {
      return null;
    }
    return double.parse(number.replaceAll(',', '.'));
  }
}
