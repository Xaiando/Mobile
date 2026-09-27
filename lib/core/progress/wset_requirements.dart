import '../questions/format_registry.dart';

/// App-owned teaching requirements. Exact evidence prevents a regional pin
/// from being mistaken for lessons explaining how a wine is made or tastes.
class WsetRequirement {
  const WsetRequirement({
    required this.id,
    required this.title,
    required this.reviewed,
    required this.dimensions,
  });

  final String id;
  final String title;

  /// An internal scope/source review, not qualified expert verification.
  final bool reviewed;
  final List<WsetEvidenceDimension> dimensions;

  Set<String> get itemIds => {
    for (final dimension in dimensions) ...dimension.itemIds,
  };

  factory WsetRequirement.fromJson(Map<String, dynamic> row) => WsetRequirement(
    id: row['id'] as String,
    title: row['title'] as String,
    reviewed: row['reviewed'] as bool,
    dimensions: List.unmodifiable([
      for (final dimension in row['dimensions'] as List<dynamic>)
        WsetEvidenceDimension.fromJson(dimension as Map<String, dynamic>),
    ]),
  );

  void validate() {
    if (!RegExp(r'^[a-z][a-z0-9_]+$').hasMatch(id) ||
        title.trim().isEmpty ||
        dimensions.isEmpty ||
        dimensions.map((dimension) => dimension.kind).toSet().length !=
            dimensions.length) {
      throw FormatException('Invalid teaching requirement: $id');
    }
    for (final dimension in dimensions) {
      dimension.validate();
    }
  }
}

class WsetEvidenceDimension {
  const WsetEvidenceDimension({
    required this.kind,
    required this.itemIds,
    required this.formats,
  });

  final String kind;
  final List<String> itemIds;

  /// At least one of these modes must actually be served for each linked fact.
  /// This is availability evidence; shared FSRS still records fact mastery.
  final List<String> formats;

  static const kinds = {
    'location',
    'grapes',
    'environment',
    'production',
    'style',
    'labels',
    'quality_price',
    'vine',
    'winery',
    'service',
    'food',
    'responsible',
    'description',
    'quality_assessment',
    'ageing',
  };
  static Iterable<String> get modes => appFormats.ids;

  factory WsetEvidenceDimension.fromJson(Map<String, dynamic> row) =>
      WsetEvidenceDimension(
        kind: row['kind'] as String,
        itemIds: List<String>.unmodifiable(
          List<String>.from(row['itemIds'] as List<dynamic>),
        ),
        formats: List<String>.unmodifiable(
          List<String>.from(row['formats'] as List<dynamic>),
        ),
      );

  void validate() {
    if (!kinds.contains(kind) ||
        itemIds.isEmpty ||
        formats.isEmpty ||
        itemIds.toSet().length != itemIds.length ||
        formats.toSet().length != formats.length ||
        !formats.every(modes.contains) ||
        (kind != 'location' &&
            kind != 'grapes' &&
            formats.any((mode) => mode.startsWith('map_'))) ||
        itemIds.any((id) => !RegExp(r'^ki_[a-z0-9_]+$').hasMatch(id))) {
      throw FormatException('Invalid requirement evidence: $kind');
    }
  }
}
