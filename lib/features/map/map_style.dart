import 'package:flutter/material.dart';

/// Colours and line widths of the map (geography §8).
///
/// Right, wrong and the focus highlight come from the Okabe–Ito palette,
/// which stays distinct under colour-vision deficiency, and are also marked
/// by icon (GEO-13).
@immutable
final class MapStyle {
  const MapStyle({
    required this.water,
    required this.land,
    required this.border,
    required this.river,
    required this.candidateFill,
    required this.candidateOutline,
    required this.parentOutline,
    required this.contextFill,
    required this.contextOutline,
    required this.marker,
    required this.focus,
    required this.correct,
    required this.incorrect,
    required this.label,
    required this.labelHalo,
    this.borderWidth = 1,
    this.outlineWidth = 1.2,
    this.parentWidth = 2.5,
    this.highlightWidth = 3,
    this.riverWidth = 1.6,
    this.labelSize = 12,
  });

  /// The style for [context]'s theme brightness.
  factory MapStyle.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = MapStyle(
    water: Color(0xFFDCE8F0),
    land: Color(0xFFF6F3EC),
    border: Color(0xFF8C857B),
    river: Color(0xFF4F86B8),
    candidateFill: Color(0xFFFFFFFF),
    candidateOutline: Color(0xFF3F3A34),
    parentOutline: Color(0xFF5E564D),
    contextFill: Color(0xFFEEEAE2),
    contextOutline: Color(0xFFC6BFB4),
    marker: Color(0xFF3F3A34),
    focus: Color(0xFF0072B2),
    correct: Color(0xFF009E73),
    incorrect: Color(0xFFD55E00),
    label: Color(0xFF26221E),
    labelHalo: Color(0xE6FFFFFF),
  );

  static const dark = MapStyle(
    water: Color(0xFF15212A),
    land: Color(0xFF24211E),
    border: Color(0xFF7D766C),
    river: Color(0xFF6FA3D1),
    candidateFill: Color(0xFF2F2B27),
    candidateOutline: Color(0xFFE3DDD3),
    parentOutline: Color(0xFFBDB4A7),
    contextFill: Color(0xFF292623),
    contextOutline: Color(0xFF4F4943),
    marker: Color(0xFFE3DDD3),
    focus: Color(0xFF56B4E9),
    correct: Color(0xFF2BB589),
    incorrect: Color(0xFFE8752A),
    label: Color(0xFFF2EEE8),
    labelHalo: Color(0xCC000000),
  );

  /// Beyond the land: seas and lakes, and the space around the data.
  final Color water;

  /// Base-map areas, such as countries.
  final Color land;
  final Color border;
  final Color river;

  final Color candidateFill;
  final Color candidateOutline;
  final Color parentOutline;

  /// Features shown only as context: dimmed (geography §5).
  final Color contextFill;
  final Color contextOutline;

  final Color marker;
  final Color focus;
  final Color correct;
  final Color incorrect;
  final Color label;
  final Color labelHalo;

  /// Line widths, in logical pixels.
  final double borderWidth;
  final double outlineWidth;
  final double parentWidth;
  final double highlightWidth;
  final double riverWidth;

  final double labelSize;

  List<Object> get _fields => [
    water,
    land,
    border,
    river,
    candidateFill,
    candidateOutline,
    parentOutline,
    contextFill,
    contextOutline,
    marker,
    focus,
    correct,
    incorrect,
    label,
    labelHalo,
    borderWidth,
    outlineWidth,
    parentWidth,
    highlightWidth,
    riverWidth,
    labelSize,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MapStyle) return false;
    final mine = _fields, theirs = other._fields;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);
}
