import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../time/utc_clock.dart';
import 'app_database.dart';

/// The only way to delete from the review log.
extension UserDataRewrites on AppDatabase {
  /// Runs [body] in a transaction in which the review log accepts deletions,
  /// for the learner's own reset or import (audit DL-7).
  ///
  /// `review_events` and `review_event_options` reject deletions unless a
  /// `user_data_rewrites` row exists (see schema.drift), and reject updates
  /// always. This inserts that row, runs [body], and removes the row before
  /// the transaction commits, so a failure rolls back to the locked state. A
  /// nested call reuses the lock of the outer one.
  Future<T> rewriteUserData<T>(Future<T> Function() body, {Clock? clock}) {
    return transaction(() async {
      final alreadyUnlocked =
          await (select(userDataRewrites)..limit(1)).getSingleOrNull() != null;
      if (alreadyUnlocked) return body();

      await into(userDataRewrites).insert(
        UserDataRewritesCompanion.insert(
          id: const Value(1),
          startedAt: utcNow(clock),
        ),
      );
      final result = await body();
      await delete(userDataRewrites).go();
      return result;
    });
  }
}
