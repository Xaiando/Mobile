import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'formats/flashcard_view.dart';
import 'formats/map_identify_view.dart';
import 'formats/map_locate_view.dart';
import 'formats/mcq_view.dart';
import 'study_session_controller.dart';

/// A format's practice view, with the icon of its badge.
class FormatView {
  const FormatView({
    required this.icon,
    required this.builder,
    this.expands = false,
  });

  final IconData icon;

  /// The answer area below the prompt: the options, the reveal, the grades.
  final Widget Function(SessionTurn turn) builder;

  /// Whether the view fills the height left below the prompt instead of
  /// scrolling with it, as a map does.
  final bool expands;
}

/// The practice view of each format, by format ID (question-system §9). A
/// new format adds one line here, and its format one line in `appFormats`.
/// Tests override it to add a format's view.
final formatViewsProvider = Provider<Map<String, FormatView>>(
  (ref) => {
    'mcq': FormatView(icon: Icons.list, builder: McqView.new),
    'flashcard': FormatView(
      icon: Icons.style_outlined,
      builder: FlashcardView.new,
    ),
    'map_locate': FormatView(
      icon: Icons.ads_click,
      builder: MapLocateView.new,
      expands: true,
    ),
    'map_identify': FormatView(
      icon: Icons.map_outlined,
      builder: MapIdentifyView.new,
      expands: true,
    ),
  },
);
