import 'dart:math';

import '../questions/exercise_format.dart';
import 'study_planner.dart';

/// The presentation ladder (backlog F4, QF-7, question-system §5): chooses
/// each presentation's format by the item's memory band, among the formats
/// its track serves. It replaces FS-15's random draw.
///
/// - A new item starts with its easiest format preferred while learning,
///   as FS-15 had it.
/// - Later, one presentation in [randomEvery] is a random draw among the
///   served formats, so the ladder does not overfit.
/// - Otherwise the format is drawn among those preferred in the item's
///   band, or the nearest band that has one, the easier band first.
/// - The item's last format is never repeated while another is served.
class FormatLadder {
  const FormatLadder({this.randomEvery = 5});

  /// One presentation in this many is a random draw; zero for none.
  final int randomEvery;

  /// The format to present [card] with, drawn with [random].
  QuestionFormat choose(StudyCard card, Random random) {
    final served = card.formats;
    if (served.length == 1) return served.single;
    final band = MemoryBand.of(card.state);
    if (card.isNew) {
      return _nearest(served, band, (preferred) => preferred.first);
    }
    final last = [
      for (final format in served)
        if (format.questionTemplateId == card.lastTemplateId) format,
    ].firstOrNull;
    final fresh = [
      for (final format in served)
        if (last == null ||
            format.mode != last.mode ||
            format.direction != last.direction)
          format,
    ];
    final candidates = fresh.isEmpty ? served : fresh;
    if (randomEvery > 0 && random.nextInt(randomEvery) == 0) {
      return candidates[random.nextInt(candidates.length)];
    }
    return _nearest(
      candidates,
      band,
      (preferred) => preferred[random.nextInt(preferred.length)],
    );
  }

  /// [pick] among the [formats] preferred in [band], or in the nearest band
  /// that has one, the easier of two equally near. [formats] are easiest
  /// first, so the first preferred is the easiest.
  static QuestionFormat _nearest(
    List<QuestionFormat> formats,
    MemoryBand band,
    QuestionFormat Function(List<QuestionFormat> preferred) pick,
  ) {
    const bands = MemoryBand.values;
    for (var distance = 0; distance < bands.length; distance++) {
      for (final index in {band.index - distance, band.index + distance}) {
        if (index < 0 || index >= bands.length) continue;
        final preferred = [
          for (final format in formats)
            if (format.preferredBands.contains(bands[index])) format,
        ];
        if (preferred.isNotEmpty) return pick(preferred);
      }
    }
    return formats.first;
  }
}
