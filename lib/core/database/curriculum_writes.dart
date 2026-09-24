import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../time/utc_clock.dart';
import 'app_database.dart';

/// The only way to write curriculum tables.
extension CurriculumWrites on AppDatabase {
  /// Runs [body] in a transaction in which curriculum tables accept writes.
  ///
  /// Every curriculum table rejects writes unless a `curriculum_ingestions`
  /// row exists (see schema.drift). This inserts that row, runs [body], and
  /// removes the row before the transaction commits, so a failure rolls back
  /// to the locked state. A nested call reuses the lock of the outer one.
  Future<T> writeCurriculum<T>(Future<T> Function() body, {Clock? clock}) {
    return transaction(() async {
      final alreadyUnlocked =
          await (select(curriculumIngestions)..limit(1)).getSingleOrNull() !=
          null;
      if (alreadyUnlocked) return body();

      await into(curriculumIngestions).insert(
        CurriculumIngestionsCompanion.insert(
          id: const Value(1),
          startedAt: utcNow(clock),
        ),
      );
      final result = await body();
      await delete(curriculumIngestions).go();
      return result;
    });
  }
}
