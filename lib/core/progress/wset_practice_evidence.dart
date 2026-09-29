import 'dart:convert';

import '../database/app_database.dart';
import '../rehearsal/rehearsal.dart';
import '../tasting/tasting_practice.dart';
import '../tasting_guidance/guided_tasting.dart';
import '../tasting_pair/tasting_pair.dart';

/// Participation requirements for this app's original practice activities.
/// They neither grant fact-memory credit nor infer an official examination pass.
class WsetPracticeRequirements {
  const WsetPracticeRequirements({
    this.rehearsal = false,
    this.writtenReview = false,
    this.calibrationCases = 0,
    this.physicalWines = 0,
    this.pairedTasting = false,
  });
  final bool rehearsal;
  final bool writtenReview;
  final int calibrationCases;
  final int physicalWines;
  final bool pairedTasting;
  bool get isEmpty =>
      !rehearsal &&
      !writtenReview &&
      calibrationCases == 0 &&
      physicalWines == 0 &&
      !pairedTasting;
  factory WsetPracticeRequirements.fromJson(Map<String, dynamic> row) =>
      WsetPracticeRequirements(
        rehearsal: row['rehearsal'] as bool,
        writtenReview: row['writtenReview'] as bool,
        calibrationCases: row['calibrationCases'] as int,
        physicalWines: row['physicalWines'] as int,
        pairedTasting: row['pairedTasting'] as bool,
      );
  void validate() {
    if (calibrationCases < 0 ||
        physicalWines < 0 ||
        calibrationCases > 100 ||
        physicalWines > 100) {
      throw const FormatException('Invalid app practice requirements');
    }
  }
}

class WsetPracticeEvidence {
  const WsetPracticeEvidence({
    this.rehearsals = 0,
    this.writtenReviews = 0,
    this.calibrationCases = 0,
    this.physicalWines = 0,
    this.pairedTastings = 0,
    this.unreadableRecords = 0,
  });
  final int rehearsals;
  final int writtenReviews;
  final int calibrationCases;
  final int physicalWines;
  final int pairedTastings;
  final int unreadableRecords;
  bool satisfies(WsetPracticeRequirements requirements) =>
      (!requirements.rehearsal || rehearsals > 0) &&
      (!requirements.writtenReview || writtenReviews > 0) &&
      calibrationCases >= requirements.calibrationCases &&
      physicalWines >= requirements.physicalWines &&
      (!requirements.pairedTasting || pairedTastings > 0);
}

/// Reads persisted snapshots without creating activities or modifying FSRS.
/// A malformed historical record cannot suppress other recoverable evidence.
class WsetPracticeEvidenceReader {
  WsetPracticeEvidenceReader(this.db);
  final AppDatabase db;
  Future<WsetPracticeEvidence> read(
    int level,
    Map<String, String> settings, {
    required DateTime now,
    required Set<String> currentItems,
    required Set<String> mappedItems,
  }) async {
    var rehearsals = 0, writtenReviews = 0, paired = 0, unreadable = 0;
    final cases = <String>{}, physical = <String>{};
    bool available(Iterable<String> ids) => ids.every(
      (id) => currentItems.contains(id) && mappedItems.contains(id),
    );
    for (final entry in settings.entries) {
      Object snapshot;
      try {
        if (entry.key.startsWith(RehearsalRepository.attemptPrefix)) {
          final attempt = RehearsalAttempt.fromJson(
            jsonDecode(entry.value) as Map<String, dynamic>,
          );
          if (entry.key !=
              '${RehearsalRepository.attemptPrefix}${attempt.id.replaceAll('-', '_')}') {
            throw const FormatException('Practice key does not match snapshot');
          }
          snapshot = attempt;
        } else if (entry.key.startsWith(GuidedTastingRepository.recordPrefix)) {
          final record = GuidedTastingRecord.fromJson(
            jsonDecode(entry.value) as Map<String, dynamic>,
          );
          if (entry.key !=
              '${GuidedTastingRepository.recordPrefix}${record.sessionId.replaceAll('-', '_')}') {
            throw const FormatException('Tasting key does not match snapshot');
          }
          snapshot = record;
        } else if (entry.key.startsWith(TastingPairRepository.attemptPrefix)) {
          final attempt = TastingPairAttempt.fromJson(
            jsonDecode(entry.value) as Map<String, dynamic>,
          );
          if (entry.key !=
              '${TastingPairRepository.attemptPrefix}${attempt.id.replaceAll('-', '_')}') {
            throw const FormatException(
              'Paired tasting key does not match snapshot',
            );
          }
          snapshot = attempt;
        } else {
          continue;
        }
      } catch (error) {
        // Recover only failures in the saved snapshot. Database queries below
        // must propagate, including StateError from an unavailable connection.
        if (error is FormatException ||
            error is TypeError ||
            error is StateError ||
            error is ArgumentError) {
          unreadable++;
          continue;
        }
        rethrow;
      }
      if (snapshot case RehearsalAttempt attempt) {
        if (attempt.level != level ||
            !attempt.isFinished ||
            attempt.abandoned ||
            attempt.completedAt!.isAfter(now)) {
          continue;
        }
        if (!available(attempt.mcqs.expand((q) => q.itemIds))) continue;
        if (attempt.mcqs.every((q) => attempt.answers.containsKey(q.id))) {
          rehearsals++;
        }
        if (level == 3 &&
            attempt.written.every(
              (q) =>
                  (attempt.prose[q.id] ?? '').trim().isNotEmpty &&
                  attempt.selfAssessment.containsKey(q.id),
            ) &&
            available(
              attempt.written.expand(
                (q) => q.criteria.expand((c) => c.itemIds),
              ),
            )) {
          writtenReviews++;
        }
      } else if (snapshot case GuidedTastingRecord record) {
        if (record.level.level != level ||
            !record.isFinished ||
            record.completedAt!.isAfter(now)) {
          continue;
        }
        final session = await (db.select(
          db.tastingSessions,
        )..where((s) => s.id.equals(record.sessionId))).getSingleOrNull();
        if (session == null ||
            session.tastingGridId != record.level.gridId ||
            session.completedAt != record.completedAt ||
            record.completedAt!.isBefore(session.startedAt)) {
          continue;
        }
        final practice = TastingPractice(db);
        final observations = await practice.answers(record.sessionId);
        if (observations.length != record.completedObservations.length ||
            !observations.entries.every(
              (e) =>
                  record.completedObservations[e.key]?.length ==
                      e.value.length &&
                  e.value.every(
                    (v) => record.completedObservations[e.key]!.contains(v),
                  ),
            )) {
          continue;
        }
        final grid = await practice.layout(record.level.gridId);
        if (grid.attributes.any(
          (a) => a.attribute.isRequired && (observations[a.key] ?? {}).isEmpty,
        )) {
          continue;
        }
        if (record.calibration case final calibration?) {
          try {
            validateCalibrationVocabulary(calibration, grid);
          } on FormatException {
            // Only this saved reference is malformed. Grid reads above remain
            // outside recovery so a database failure cannot erase evidence.
            unreadable++;
            continue;
          }
          if (available(calibration.itemIds)) cases.add(calibration.id);
        } else {
          physical.add(record.sessionId);
        }
      } else if (snapshot case TastingPairAttempt attempt) {
        if (level == 3 &&
            attempt.isFinished &&
            !attempt.abandoned &&
            !attempt.completedAt!.isAfter(now) &&
            attempt.hasWhiteAndRedWines) {
          paired++;
        }
      }
    }
    return WsetPracticeEvidence(
      rehearsals: rehearsals,
      writtenReviews: writtenReviews,
      calibrationCases: cases.length,
      physicalWines: physical.length,
      pairedTastings: paired,
      unreadableRecords: unreadable,
    );
  }
}
