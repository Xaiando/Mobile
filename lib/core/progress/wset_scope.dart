import 'dart:convert';

/// App-owned coverage notes, separate from authored curriculum and exam results.
class WsetScope {
  const WsetScope(this.levels);

  final List<WsetLevelScope> levels;

  factory WsetScope.fromJson(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported WSET progress scope');
    }
    final levels = [
      for (final row in json['levels'] as List<dynamic>)
        WsetLevelScope.fromJson(row as Map<String, dynamic>),
    ];
    final scope = WsetScope(List.unmodifiable(levels));
    scope.validate();
    return scope;
  }

  void validate() {
    if (levels.length != 4 ||
        levels.map((level) => level.certificationId).toSet().length != 4 ||
        !levels.every(
          (level) => const {
            'WSET_L1',
            'WSET_L2',
            'WSET_L3',
            'WSET_L4',
          }.contains(level.certificationId),
        )) {
      throw const FormatException(
        'Progress scope must contain WSET Levels 1–4',
      );
    }
    for (final level in levels) {
      if (level.curriculumComplete &&
          (level.gaps.isNotEmpty ||
              level.units.any((unit) => unit.gap.isNotEmpty))) {
        throw FormatException(
          'Complete coverage cannot retain gaps: ${level.certificationId}',
        );
      }
      final ids = level.units.map((unit) => unit.id).toSet();
      if (ids.length != level.units.length ||
          !ids.every(const {'D1', 'D2', 'D3', 'D4', 'D5', 'D6'}.contains)) {
        throw FormatException(
          'Invalid or duplicate unit IDs: ${level.certificationId}',
        );
      }
      if (level.units.isNotEmpty &&
          (level.certificationId != 'WSET_L4' || ids.length != 6)) {
        throw const FormatException('Diploma topic groups must contain D1–D6');
      }
      final assignedItems = <String>{};
      for (final unit in level.units) {
        for (final id in unit.itemIds) {
          if (!id.startsWith('ki_') || id.trim() != id || id.length <= 3) {
            throw FormatException('Invalid progress topic item: $id');
          }
          if (!assignedItems.add(id)) {
            throw FormatException('Duplicate progress topic item: $id');
          }
        }
      }
    }
  }
}

class WsetLevelScope {
  const WsetLevelScope({
    required this.certificationId,
    required this.title,
    required this.curriculumComplete,
    required this.gaps,
    required this.sourceUrl,
    this.units = const [],
  });

  final String certificationId;
  final String title;
  final bool curriculumComplete;
  final List<String> gaps;
  final String sourceUrl;
  final List<WsetUnitScope> units;

  factory WsetLevelScope.fromJson(Map<String, dynamic> row) => WsetLevelScope(
    certificationId: row['certificationId'] as String,
    title: row['title'] as String,
    curriculumComplete: row['curriculumComplete'] as bool,
    gaps: List<String>.from(row['gaps'] as List<dynamic>),
    sourceUrl: row['sourceUrl'] as String,
    units: [
      for (final unit in row['units'] as List<dynamic>? ?? const [])
        WsetUnitScope.fromJson(unit as Map<String, dynamic>),
    ],
  );
}

/// Editorial topic groups. Matching facts support a unit; they do not cover it.
class WsetUnitScope {
  const WsetUnitScope({
    required this.id,
    required this.title,
    required this.gap,
    this.domains = const [],
    this.regionRoots = const [],
    this.geographyRoots = const [],
    this.itemIds = const [],
  });

  final String id;
  final String title;
  final String gap;
  final List<String> domains;
  final List<String> regionRoots;

  /// Context for mixed-style wine regions: only location facts are grouped.
  final List<String> geographyRoots;

  /// Explicit editorial assignment takes precedence over region and domain.
  /// Production and commerce lessons can support D4/D5 without being places.
  final List<String> itemIds;

  factory WsetUnitScope.fromJson(Map<String, dynamic> row) => WsetUnitScope(
    id: row['id'] as String,
    title: row['title'] as String,
    gap: row['gap'] as String,
    domains: List<String>.from(row['domains'] as List<dynamic>? ?? const []),
    regionRoots: List<String>.from(
      row['regionRoots'] as List<dynamic>? ?? const [],
    ),
    geographyRoots: List<String>.from(
      row['geographyRoots'] as List<dynamic>? ?? const [],
    ),
    itemIds: _parseItemIds(row),
  );

  static List<String> _parseItemIds(Map<String, dynamic> row) {
    if (!row.containsKey('itemIds')) return const [];
    final value = row['itemIds'];
    if (value is! List || value.any((id) => id is! String)) {
      throw const FormatException('Progress topic itemIds must be strings');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }
}
