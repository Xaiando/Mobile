import 'dart:convert';

import 'diploma_written.dart';

/// Reviewed writing participation, never a mark or unit result.
class DiplomaWrittenEvidence {
  const DiplomaWrittenEvidence({
    this.d1Reviewed = 0,
    this.d2Reviewed = 0,
    this.unreadableCount = 0,
  });

  final int d1Reviewed;
  final int d2Reviewed;
  final int unreadableCount;
  int forUnit(String unitId) => switch (unitId) {
    'D1' => d1Reviewed,
    'D2' => d2Reviewed,
    _ => 0,
  };
}

class DiplomaWrittenEvidenceReader {
  static DiplomaWrittenEvidence read(
    Map<String, String> settings, {
    required DateTime now,
  }) {
    var d1 = 0, d2 = 0, unreadable = 0;
    for (final entry in settings.entries) {
      if (!entry.key.startsWith(DiplomaWrittenRepository.attemptPrefix)) {
        continue;
      }
      try {
        final attempt = DiplomaWrittenAttempt.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (DiplomaWrittenRepository.keyFor(attempt.id) != entry.key) {
          throw const FormatException('Written-practice key mismatch.');
        }
        attempt.validateAt(now);
        if (attempt.isReviewed) {
          if (attempt.unitId == 'D1') d1++;
          if (attempt.unitId == 'D2') d2++;
        }
      } catch (_) {
        unreadable++;
      }
    }
    return DiplomaWrittenEvidence(
      d1Reviewed: d1,
      d2Reviewed: d2,
      unreadableCount: unreadable,
    );
  }
}
