import '../curriculum/name_normalizer.dart';
import 'journal_matcher.dart';

/// A field in the journal editor that a label scan can suggest.
enum LabelField { producer, cuvee, appellation, grapes, vintage, abv }

/// Conservative suggestions from text recognized on a wine label. A proposal
/// is never a bottle identity and must be accepted in the journal editor.
class LabelProposal {
  const LabelProposal({
    required this.rawText,
    required this.producer,
    required this.cuvee,
    required this.appellation,
    required this.grapes,
    required this.vintage,
    required this.isNonVintage,
    required this.abvPercent,
    required this.warnings,
  });

  final String rawText;
  final String? producer;
  final String? cuvee;
  final String? appellation;
  final String? grapes;
  final int? vintage;
  final bool isNonVintage;
  final double? abvPercent;
  final List<String> warnings;

  static final _year = RegExp(r'\b(?:18\d{2}|19\d{2}|20\d{2}|2100)\b');
  static final _nonVintage = RegExp(
    r'\b(?:NV|non[\s-]?vintage|sans\s+ann[ée]e)\b',
    caseSensitive: false,
  );
  static final _producerLabel = RegExp(
    r'^(?:producer|winery|estate)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
  );
  static final _producerPrefix = RegExp(
    r'^(?:ch[âa]teau|domaine|maison|weingut|bodega|tenuta|cantina|fattoria|vi[ñn]a)\s+.+$',
    caseSensitive: false,
  );
  static final _cuveeLabel = RegExp(
    r'^cuv[ée]e\s*(?::|\-|\s)\s*(.+)$',
    caseSensitive: false,
  );
  static final _placeLabel = RegExp(
    r'^(?:appellation|region|région)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
  );
  static final _frenchAppellation = RegExp(
    r'^appellation\s+(.+?)\s+(?:d.origine\s+)?(?:contr[ôo]l[ée]e|prot[ée]g[ée]e)$',
    caseSensitive: false,
  );
  static final _legalPlaceSuffix = RegExp(
    r'^(.+?)\s+(?:AOC|AOP|AVA|DOCG|DOCa|DOC|DOP|DO|IGP|IGT|PDO|PGI)$',
    caseSensitive: false,
  );
  static final _grapeLabel = RegExp(
    r'^(?:grapes?|variet(?:y|ies)|c[ée]pages?|uve)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
  );
  static final _hundredPercentGrape = RegExp(r'^100\s*%\s+(.+)$');
  static final _grapeSeparators = RegExp(
    r'\s*(?:[,;/&+]|\b(?:and|et|und|e|y)\b)\s*',
    caseSensitive: false,
  );
  static final _footer = RegExp(
    r'(?:\b(?:contains|sulphites|sulfites|imported|bottled|mis en bouteille|alcohol|alc|vol|product of|produit de|warning|www|https?)\b|\d\s*(?:ml|cl)\b)',
    caseSensitive: false,
  );

  /// [matcher] supplies exact, locally bundled place and grape names for
  /// otherwise unlabelled lines. It is optional, so manual transcription and
  /// explicit label wording still work before the curriculum has loaded.
  /// Neither OCR text nor matcher results are persisted here.
  static LabelProposal fromRecognizedText(
    String text, {
    JournalMatcher? matcher,
  }) {
    final raw = text.trim();
    final warnings = <String>[];
    if (raw.isEmpty) warnings.add('no_text');

    final nonVintage = _nonVintage.hasMatch(raw);
    final years = _year
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

    // A three-digit blend declaration such as "100% Pinot Noir" is not an
    // alcohol percentage. A labelled grape blend line is not ABV either.
    final percents = <double>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (_grapeLabel.hasMatch(trimmed) ||
          _hundredPercentGrape.hasMatch(trimmed)) {
        continue;
      }
      for (final match in RegExp(
        r'(?:^|[^\d])(\d{1,2}(?:[.,]\d{1,2})?)\s*%',
      ).allMatches(line)) {
        percents.add(double.parse(match.group(1)!.replaceAll(',', '.')));
      }
    }
    if (percents.length > 1) warnings.add('multiple_percent_tokens');
    final percent = percents.length == 1 ? percents.single : null;
    final abv = percent != null && percent > 0 && percent <= 30
        ? percent
        : null;
    if (percent != null && abv == null) warnings.add('percent_not_offered');

    final producers = <String>[];
    final cuvees = <String>[];
    final places = <String>[];
    final grapes = <String>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final clean = _clean(line);
      if (clean.isEmpty) continue;
      final explicitProducer = _producerLabel.firstMatch(clean)?.group(1);
      if (explicitProducer != null) {
        _addSafe(producers, explicitProducer);
        continue;
      }
      final explicitCuvee = _cuveeLabel.firstMatch(clean)?.group(1);
      if (explicitCuvee != null) {
        _addSafe(cuvees, explicitCuvee);
        continue;
      }
      final explicitPlace =
          _placeLabel.firstMatch(clean)?.group(1) ??
          _frenchAppellation.firstMatch(clean)?.group(1) ??
          _legalPlaceSuffix.firstMatch(clean)?.group(1);
      if (explicitPlace != null) {
        // A producer name followed by a legal suffix is not itself proof
        // that the producer name is the place of origin.
        if (!_producerPrefix.hasMatch(_clean(explicitPlace))) {
          _addSafe(places, explicitPlace);
        }
        continue;
      }
      final explicitGrapes =
          _grapeLabel.firstMatch(clean)?.group(1) ??
          _hundredPercentGrape.firstMatch(clean)?.group(1);
      if (explicitGrapes != null) {
        _addSafe(grapes, explicitGrapes, grapeList: true);
        continue;
      }

      if (!_isSafeName(clean) || _footer.hasMatch(clean)) continue;
      if (_producerPrefix.hasMatch(clean) && clean.split(' ').length <= 7) {
        producers.add(clean);
        continue;
      }
      if (matcher == null) continue;
      final placeNodes = matcher.exactLabelNames(
        clean,
        nodeTypes: const {
          'region',
          'subregion',
          'appellation',
          'informal_area',
        },
      );
      final wholeLineGrapes = matcher.exactLabelNames(
        clean,
        nodeTypes: const {'grape'},
      );
      if (placeNodes.length > 1 ||
          wholeLineGrapes.length > 1 ||
          (placeNodes.isNotEmpty && wholeLineGrapes.isNotEmpty)) {
        if (!warnings.contains('ambiguous_catalog_name')) {
          warnings.add('ambiguous_catalog_name');
        }
        continue;
      }
      if (placeNodes.length == 1) {
        // Keep the spelling actually printed on the bottle; the matcher is
        // evidence for the place type, not a transcription replacement.
        places.add(clean);
        continue;
      }
      final parts = clean.split(_grapeSeparators);
      if (parts.isEmpty || parts.length > 4) continue;
      final matchedGrapes = <String>[];
      for (final part in parts) {
        final grapeNodes = matcher.exactLabelNames(
          part,
          nodeTypes: const {'grape'},
        );
        if (grapeNodes.length != 1) {
          if (grapeNodes.length > 1 &&
              !warnings.contains('ambiguous_catalog_name')) {
            warnings.add('ambiguous_catalog_name');
          }
          break;
        }
        matchedGrapes.add(part.trim());
      }
      if (matchedGrapes.length == parts.length) {
        grapes.add(matchedGrapes.join(', '));
      }
    }

    String? unique(List<String> values, String field) {
      final byName = {for (final value in values) normalizeName(value): value};
      if (byName.length > 1) warnings.add('multiple_${field}_candidates');
      return byName.length == 1 ? byName.values.single : null;
    }

    return LabelProposal(
      rawText: raw,
      producer: unique(producers, 'producer'),
      cuvee: unique(cuvees, 'cuvee'),
      appellation: unique(places, 'appellation'),
      grapes: unique(grapes, 'grapes'),
      vintage: vintage,
      isNonVintage: nonVintage,
      abvPercent: abv,
      warnings: List.unmodifiable(warnings),
    );
  }

  static String _clean(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isSafeName(String value) =>
      value.length >= 3 &&
      value.length <= 70 &&
      RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(value) &&
      !RegExp(r'\d|%|@').hasMatch(value) &&
      !_nonVintage.hasMatch(value);

  static void _addSafe(
    List<String> values,
    String raw, {
    bool grapeList = false,
  }) {
    final value = _clean(raw);
    if (!_isSafeName(value) || _footer.hasMatch(value)) return;
    if (grapeList) {
      final parts = value.split(_grapeSeparators);
      if (parts.isEmpty ||
          parts.length > 4 ||
          parts.any((part) => part.trim().length < 3)) {
        return;
      }
    }
    values.add(value);
  }
}
