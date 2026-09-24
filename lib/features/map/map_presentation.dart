import '../../core/geography/geo_layer.dart';

/// The four difficulty modes of map questions (geography §4, GEO-8). The
/// presentation ladder chooses among them (question-system §5).
enum MapLabelMode {
  /// Every candidate is outlined and named: recognition.
  labelled,

  /// Candidates are outlined but unnamed; the parent, rivers and coastline
  /// are named.
  outline,

  /// Only the coastline, national borders and major rivers are drawn;
  /// candidates are revealed after the answer.
  minimal,

  /// Blank, zoomed out: minimal mode starting one level up, so the learner
  /// zooms to find the answer.
  blank,
}

/// How a feature is emphasised: the shape a question asks about, or the
/// outcome of an answer. Outcomes are marked by icon as well as colour
/// (GEO-13).
enum MapHighlight { focus, correct, incorrect }

/// A layer drawn by the map.
final class MapLayer {
  const MapLayer(this.geometry) : isBase = false;

  /// A base layer: coastlines, national borders or major rivers. Base layers
  /// are drawn in every mode, even minimal (geography §4).
  const MapLayer.base(this.geometry) : isBase = true;

  final GeoLayer geometry;
  final bool isBase;

  @override
  bool operator ==(Object other) =>
      other is MapLayer &&
      identical(other.geometry, geometry) &&
      other.isBase == isBase;

  @override
  int get hashCode => Object.hash(identityHashCode(geometry), isBase);
}

/// What a feature is to the question on the map.
enum FeatureRole {
  /// A possible answer: the same-type siblings in the frame (geography §5).
  candidate,

  /// The area the frame shows, such as the region around its appellations.
  parent,

  /// A feature of a base layer.
  base,

  /// Anything else, drawn dimmed as context (geography §5).
  context,
}

/// How one feature is drawn.
final class FeatureLook {
  const FeatureLook({
    required this.role,
    required this.drawn,
    required this.named,
    this.highlight,
  });

  final FeatureRole role;

  /// Whether its outline, or its marker, is drawn at all.
  final bool drawn;

  /// Whether its name is written.
  final bool named;

  final MapHighlight? highlight;

  bool get isDimmed => role == FeatureRole.context && highlight == null;
}

/// The rules of the difficulty modes: what each mode draws and names
/// (geography §4).
///
/// | | labelled | outline | minimal, blank |
/// |---|---|---|---|
/// | base layers | drawn, named | drawn, named | drawn |
/// | parent | drawn, named | drawn, named | — |
/// | candidates | drawn, named | drawn | — |
/// | context | dimmed | dimmed | — |
///
/// Highlighted features are always drawn. Revealing the answer shows
/// everything as labelled mode does.
final class MapPresentation {
  const MapPresentation({required this.mode, this.revealed = false});

  final MapLabelMode mode;

  /// Whether the answer has been given, so hidden candidates are revealed.
  final bool revealed;

  /// Whether candidates, the parent and context are drawn: in labelled and
  /// outline modes, and once revealed.
  bool get showsCandidates =>
      revealed || mode == MapLabelMode.labelled || mode == MapLabelMode.outline;

  /// Whether the view starts one level up (the blank mode).
  bool get startsZoomedOut => mode == MapLabelMode.blank;

  FeatureLook look(
    FeatureRole role, {
    bool onBaseLayer = false,
    MapHighlight? highlight,
  }) {
    final shown = showsCandidates;
    final drawn = highlight != null || onBaseLayer || shown;
    final named = switch (role) {
      FeatureRole.base || FeatureRole.parent => shown,
      FeatureRole.candidate => revealed || mode == MapLabelMode.labelled,
      FeatureRole.context => false,
    };
    return FeatureLook(
      role: role,
      drawn: drawn,
      named: drawn && named,
      highlight: highlight,
    );
  }
}
