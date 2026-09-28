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

    final years = RegExp(r'\b(?:18\d{2}|19\d{2}|20\d{2}|2100)\b')
        .allMatches(raw)
        .where((match) {
          // A percent is an alcohol candidate, never a vintage.
          final tail = raw.substring(match.end).trimLeft();
          return !tail.startsWith('%');
        })
        .map((match) => int.parse(match.group(0)!))
        .toList();
    if (years.length > 1) warnings.add('multiple_year_tokens');
    if (nonVintage && years.isNotEmpty) warnings.add('nv_and_year');
    final vintage = nonVintage || years.length != 1 ? null : years.single;

    final percents = RegExp(r'\b\d{1,2}(?:[.,]\d{1,2})?\s*%')
        .allMatches(raw)
        .map(
          (match) => double.parse(
            match.group(0)!.replaceAll('%', '').trim().replaceAll(',', '.'),
          ),
        )
        .toList();
    if (percents.length > 1) warnings.add('multiple_percent_tokens');
    final percent = percents.length == 1 ? percents.single : null;
    final abv = percent != null && percent > 0 && percent <= 30
        ? percent
        : null;
    if (percent != null && abv == null) warnings.add('percent_not_offered');

    return LabelProposal(
      rawText: raw,
      vintage: vintage,
      isNonVintage: nonVintage,
      abvPercent: abv,
      warnings: List.unmodifiable(warnings),
    );
  }
}
