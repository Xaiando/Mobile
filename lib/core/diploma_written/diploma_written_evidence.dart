import 'dart:convert';

import 'diploma_written.dart';

/// Reviewed writing participation, never a mark or unit result.
class DiplomaWrittenEvidence {
  const DiplomaWrittenEvidence({
    this.d1Reviewed = 0,
    this.d2Reviewed = 0,
    this.d4Reviewed = 0,
    this.d5Reviewed = 0,
    this.unreadableCount = 0,
  });

  final int d1Reviewed;
  final int d2Reviewed;
  final int d4Reviewed;
  final int d5Reviewed;
  final int unreadableCount;
  int forUnit(String unitId) => switch (unitId) {
    'D1' => d1Reviewed,
    'D2' => d2Reviewed,
    'D4' => d4Reviewed,
    'D5' => d5Reviewed,
    _ => 0,
  };
}

class DiplomaWrittenEvidenceReader {
  static DiplomaWrittenEvidence read(
    Map<String, String> settings, {
    required DateTime now,
  }) {
    var d1 = 0, d2 = 0, d4 = 0, d5 = 0, unreadable = 0;
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
          if (attempt.unitId == 'D4') d4++;
          if (attempt.unitId == 'D5') d5++;
        }
      } catch (_) {
        unreadable++;
      }
    }
    return DiplomaWrittenEvidence(
      d1Reviewed: d1,
      d2Reviewed: d2,
      d4Reviewed: d4,
      d5Reviewed: d5,
      unreadableCount: unreadable,
    );
  }
}
