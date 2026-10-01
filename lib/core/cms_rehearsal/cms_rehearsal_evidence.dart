import 'dart:convert';

import 'cms_rehearsal.dart';

/// Completed, explicitly reviewed app participation; never skill or exam marks.
class CmsRehearsalEvidence {
  const CmsRehearsalEvidence({
    this.theoryReviewed = 0,
    this.tastingReviewed = 0,
    this.serviceReviewed = 0,
    this.unreadableCount = 0,
  });
  final int theoryReviewed, tastingReviewed, serviceReviewed, unreadableCount;
  int forSection(CmsRehearsalSection section) => switch (section) {
    CmsRehearsalSection.theory => theoryReviewed,
    CmsRehearsalSection.tasting => tastingReviewed,
    CmsRehearsalSection.service => serviceReviewed,
  };
}

class CmsRehearsalEvidenceReader {
  static CmsRehearsalEvidence read(
    Map<String, String> settings, {
    required DateTime now,
  }) {
    var theory = 0, tasting = 0, service = 0, unreadable = 0;
    for (final entry in settings.entries) {
      if (!entry.key.startsWith(CmsRehearsalRepository.attemptPrefix)) continue;
      try {
        final attempt = CmsRehearsalAttempt.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (CmsRehearsalRepository.keyFor(attempt.id) != entry.key) {
          throw const FormatException('CMS evidence key mismatch.');
        }
        attempt.validateAt(now);
        if (attempt.isReviewed) {
          switch (attempt.section) {
            case CmsRehearsalSection.theory:
              theory++;
            case CmsRehearsalSection.tasting:
              tasting++;
            case CmsRehearsalSection.service:
              service++;
          }
        }
      } catch (_) {
        unreadable++;
      }
    }
    return CmsRehearsalEvidence(
      theoryReviewed: theory,
      tastingReviewed: tasting,
      serviceReviewed: service,
      unreadableCount: unreadable,
    );
  }
}
