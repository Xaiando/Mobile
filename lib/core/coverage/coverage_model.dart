import '../database/app_database.dart';
import '../study/study_planner.dart';
import 'coverage_formats.dart';

/// The one self-graded format built today: an item served nothing else is
/// flashcard-only (audit COV-2).
const _flashcard = 'flashcard';

/// A coverage metric: how many of the items of a track, a domain or an area
/// have some property (question-system §8, audit COV-1).
enum CoverageMetric {
  items('items', 'Items'),
  core('core', 'Core'),
  testable('testable', 'Testable'),
  flashcardOnly('flashcard_only', 'Flashcard-only', higherIsBetter: false),
  usefulPractice('useful_practice', 'Useful practice'),
  recall('recall', 'Recall'),
  recognition('recognition', 'Recognition'),
  spatial('spatial', 'Spatial'),
  structured('structured', 'Structured'),
  reasoning('reasoning', 'Reasoning'),
  coreFlashcardOnly(
    'core_flashcard_only',
    'Core flashcard-only',
    higherIsBetter: false,
    ofCore: true,
  ),
  coreUsefulPractice(
    'core_useful_practice',
    'Core with useful practice',
    ofCore: true,
  ),
  coreReasoning('core_reasoning', 'Core with reasoning', ofCore: true);

  const CoverageMetric(
    this.key,
    this.label, {
    this.higherIsBetter = true,
    this.ofCore = false,
  });

  /// The metric's name in the policy, the baseline and JSON reports.
  final String key;
  final String label;

  /// Whether more is better. The ratchet keeps these from falling (COV-3).
  final bool higherIsBetter;

  /// Counts core items only.
  final bool ofCore;

  /// The metric a share of this one is taken of: the core items for a core
  /// metric, all items otherwise.
  CoverageMetric get base => ofCore ? core : items;

  /// The metric counting the items that are served a format of [family].
  static CoverageMetric of(FormatFamily family) => switch (family) {
    FormatFamily.recall => recall,
    FormatFamily.recognition => recognition,
    FormatFamily.spatial => spatial,
    FormatFamily.structured => structured,
    FormatFamily.reasoning => reasoning,
  };

  /// The metric named [key], if there is one.
  static CoverageMetric? byKey(String key) => _byKey[key];

  static final _byKey = {for (final metric in values) metric.key: metric};
}

/// The metrics of one group of items: a track, a domain or an area.
final class CoverageCounts {
  final _values = {for (final metric in CoverageMetric.values) metric: 0};

  int operator [](CoverageMetric metric) => _values[metric]!;

  /// Counts [item] in every metric it satisfies.
  void count(ItemCoverage item) {
    void add(CoverageMetric metric, bool applies) {
      if (applies) _values[metric] = _values[metric]! + 1;
    }

    add(CoverageMetric.items, true);
    add(CoverageMetric.core, item.isCore);
    add(CoverageMetric.testable, item.isTestable);
    add(CoverageMetric.flashcardOnly, item.isFlashcardOnly);
    add(CoverageMetric.usefulPractice, item.hasUsefulPractice);
    for (final family in item.families) {
      add(CoverageMetric.of(family), true);
    }
    add(CoverageMetric.coreFlashcardOnly, item.isCore && item.isFlashcardOnly);
    add(
      CoverageMetric.coreUsefulPractice,
      item.isCore && item.hasUsefulPractice,
    );
    add(
      CoverageMetric.coreReasoning,
      item.isCore && item.families.contains(FormatFamily.reasoning),
    );
  }

  Map<CoverageMetric, int> toMap() => Map.unmodifiable(_values);
}

/// Where an item is counted (question-system §8): the country of its
/// subject, or its region in a country the policy splits by region. An item
/// whose subject is not a place is counted under the subject's node type.
final class CoverageArea {
  const CoverageArea(this.id, this.name);

  /// The area of a place that should be located, but is in no country.
  static const unplaced = CoverageArea('unplaced', 'Not located');

  /// The area of items whose subject is a node of [nodeType], not a place.
  factory CoverageArea.ofType(String nodeType, String label) =>
      CoverageArea('type:$nodeType', label);

  /// A place's node ID, `type:<node type>`, or `unplaced`.
  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is CoverageArea && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}

/// How one item of a track can be practised.
final class ItemCoverage {
  const ItemCoverage({
    required this.item,
    required this.mapping,
    required this.area,
    required this.generated,
    required this.served,
    required this.expected,
    required this.missing,
    this.subjectType = '',
    this.objectType = '',
    this.places = const {},
  });

  final KnowledgeItem item;

  /// The track's effective mapping of the item (CM-3).
  final EffectiveMapping mapping;
  final CoverageArea area;

  /// The node types of the item's subject and object.
  final String subjectType;
  final String objectType;

  /// The item's subject and every place that contains it.
  final Set<String> places;

  /// One format per question ingestion generated for the item.
  final List<QuestionFormat> generated;

  /// The formats the track serves for the item, easiest first (CM-6, A-10).
  /// Empty only when the item has no question at all.
  final List<QuestionFormat> served;

  /// The built formats the policy expects for the item's relation type.
  final Set<String> expected;

  /// The expected formats that produced no question of the item, and why.
  final Map<String, String> missing;

  String get id => item.id;
  bool get isCore => mapping.importance == 'core';

  /// The IDs of the formats served, whatever their direction.
  Set<String> get servedFormats => {for (final format in served) format.mode};

  Set<FormatFamily> get families => {
    for (final id in servedFormats)
      if (builtFormats[id] case final format?) format.family,
  };

  /// The track serves at least one format for the item.
  bool get isTestable => served.isNotEmpty;

  /// The self-graded flashcard is the only format served (COV-2).
  bool get isFlashcardOnly =>
      servedFormats.length == 1 && servedFormats.single == _flashcard;

  bool get hasObjectiveFormat =>
      servedFormats.any((id) => builtFormats[id]?.isObjective ?? false);

  /// At least one objective format and at least two families (COV-2).
  bool get hasUsefulPractice => hasObjectiveFormat && families.length >= 2;
}

/// The kinds of gap the checker reports. The ratchet fails on a blocking
/// gap unless the baseline lists it as known (backlog F1).
enum GapKind {
  /// The track maps the item, but the item has no question.
  untestable('untestable', 'no question', isBlocking: true),

  /// An item whose only served format is the flashcard (COV-3). It blocks
  /// whatever the item's importance, so every flashcard-only item is known,
  /// with its reason and the task that closes it.
  flashcardOnly('flashcard_only', 'flashcard-only', isBlocking: true),

  /// A testable core item without useful practice (COV-2).
  noUsefulPractice('no_useful_practice', 'core item without useful practice'),

  /// A format the policy expects for the relation type produced no question
  /// of the item.
  missingFormat('missing_format', 'expected format missing');

  const GapKind(this.key, this.label, {this.isBlocking = false});

  /// The gap's name in the baseline and JSON reports.
  final String key;
  final String label;
  final bool isBlocking;

  static GapKind? byKey(String key) => _byKey[key];

  static final _byKey = {for (final kind in values) kind.key: kind};
}

/// One gap of one item.
final class CoverageGap {
  const CoverageGap(this.kind, this.item, this.detail, {this.format});

  final GapKind kind;
  final ItemCoverage item;

  /// Why the gap exists, in a few words.
  final String detail;

  /// The format a [GapKind.missingFormat] gap is about.
  final String? format;

  String get itemId => item.id;

  @override
  String toString() =>
      '$itemId: ${kind.label}${format == null ? '' : ' ($format)'}: $detail';
}

/// A policy threshold (question-system §8): at least or at most a count, or
/// a share of the metric's base.
final class Threshold {
  const Threshold(
    this.metric, {
    required this.isMinimum,
    required this.value,
    this.isPercent = false,
  });

  final CoverageMetric metric;
  final bool isMinimum;
  final num value;

  /// [value] is a percentage of the metric's base, not a count.
  final bool isPercent;

  /// Whether [count] items, of [base], meet the threshold. Null for a share
  /// of no items.
  bool? admits(int count, int base) {
    if (isPercent && base == 0) return null;
    final measured = isPercent ? count * 100 / base : count;
    return isMinimum ? measured >= value : measured <= value;
  }

  @override
  String toString() =>
      '${isMinimum ? 'at least' : 'at most'} $value${isPercent ? '%' : ''}';
}

/// A threshold measured on a track, or on one of its domains.
final class ThresholdResult {
  const ThresholdResult({
    required this.threshold,
    required this.value,
    required this.base,
    this.domainId,
  });

  /// The domain measured, or null for the whole track.
  final String? domainId;
  final Threshold threshold;
  final int value;

  /// The count of the metric's base: the items, or the core items.
  final int base;

  /// Null when a share is asked of no items.
  bool? get passes => threshold.admits(value, base);
}

/// The metrics of one curriculum domain on a track, whole and by area.
final class DomainCoverage {
  DomainCoverage(this.id, this.name);

  final String id;
  final String name;
  final counts = CoverageCounts();

  /// The domain's areas, in name order once the checker is done.
  final areas = <CoverageArea, CoverageCounts>{};
}

/// The coverage of one track: its items, its metrics, its gaps and the
/// policy thresholds measured on it.
final class TrackCoverage {
  const TrackCoverage({
    required this.trackId,
    required this.trackName,
    required this.on,
    required this.items,
    required this.counts,
    required this.domains,
    required this.gaps,
    required this.thresholds,
  });

  final String trackId;
  final String trackName;

  /// The date the curriculum was measured on, `YYYY-MM-DD`.
  final String on;

  /// The track's items in force on [on], in ID order.
  final List<ItemCoverage> items;
  final CoverageCounts counts;

  /// The domains with items, in the curriculum's domain order.
  final List<DomainCoverage> domains;
  final List<CoverageGap> gaps;
  final List<ThresholdResult> thresholds;

  Iterable<CoverageGap> get blockingGaps =>
      gaps.where((gap) => gap.kind.isBlocking);
}
