import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../time/utc_clock.dart';

/// The learner's certification profile: the single `user_profiles` row
/// (spec §N, audit CM-9).
class LearnerProfiles {
  LearnerProfiles(this.db, {Clock? clock}) : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  SimpleSelectStatement<UserProfiles, UserProfile> get _row =>
      db.select(db.userProfiles)..where((p) => p.id.equals(1));

  /// The profile, or null until the learner picks a track.
  Future<UserProfile?> current() => _row.getSingleOrNull();

  /// The profile as it changes; switching track updates every screen.
  Stream<UserProfile?> watch() => _row.watchSingleOrNull();

  /// The tracks a learner can pick in V0.1: WSET Level 3 and CMS Certified
  /// (spec §N, audit CM-1).
  Future<List<Certification>> selectableTracks() =>
      (db.select(db.certifications)
            ..where((c) => c.isSelectable.equals(true))
            ..orderBy([
              (c) => OrderingTerm(expression: c.organization),
              (c) => OrderingTerm(expression: c.level),
            ]))
          .get();

  /// Makes [certificationId] the active track, creating the profile on first
  /// use.
  ///
  /// Memory state belongs to items, not tracks, so switching neither resets
  /// nor forks it (FS-12).
  Future<UserProfile> selectTrack(String certificationId) => db.transaction(
    () async {
      final track = await (db.select(
        db.certifications,
      )..where((c) => c.id.equals(certificationId))).getSingleOrNull();
      if (track == null || !track.isSelectable) {
        throw ArgumentError.value(
          certificationId,
          'certificationId',
          'is not a selectable track',
        );
      }
      final now = utcNow(_clock);
      final existing = await current();
      if (existing == null) {
        await db
            .into(db.userProfiles)
            .insert(
              UserProfilesCompanion.insert(
                id: const Value(1),
                activeCertificationId: certificationId,
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (db.update(db.userProfiles)..where((p) => p.id.equals(1))).write(
          UserProfilesCompanion(
            activeCertificationId: Value(certificationId),
            // The schema requires updated_at >= created_at, even if the
            // device clock was set back.
            updatedAt: Value(
              now.isBefore(existing.createdAt) ? existing.createdAt : now,
            ),
          ),
        );
      }
      return (await current())!;
    },
  );
}
