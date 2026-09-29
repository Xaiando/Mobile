import 'dart:convert';

import 'diploma_research.dart';

/// A saved D6 draft is participation only; it cannot mark a unit complete.
class DiplomaResearchEvidenceReader {
  static bool hasSavedDraft(
    Map<String, String> settings, {
    required DateTime now,
  }) {
    final raw = settings[DiplomaResearchRepository.settingKey];
    if (raw == null || raw.length > maxDiplomaResearchSnapshotCharacters) {
      return false;
    }
    try {
      final workspace = DiplomaResearchWorkspace.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      workspace.validateAt(now);
      return workspace.hasSavedWork;
    } catch (_) {
      return false;
    }
  }
}
