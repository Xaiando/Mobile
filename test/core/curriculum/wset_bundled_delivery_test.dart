import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  test('bundled study content installs and calibration starts on every lower level', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final clock = Clock.fixed(DateTime.utc(2026, 9, 27, 20));
    final dataset = bundledDataset();
    final ingester = CurriculumIngester(
      db,
      clock: clock,
      assets: (path) async => File(path).readAsBytesSync(),
    );
    await ingester.ensureCurrent(dataset);
    final guidance = GuidedTastingRepository(
      db,
      clock: clock,
      bank: GuidedTastingBank.fromJson(
        File('assets/study/guided_tasting.json').readAsStringSync(),
      ),
    );
    for (var level = 1; level <= 3; level++) {
      await LearnerProfiles(db, clock: clock).selectTrack('WSET_L$level');
      final calibration = guidance.bank.cases.firstWhere(
        (c) => c.level == level,
      );
      final record = await guidance.start(level, caseId: calibration.id);
      expect(record.calibration!.id, calibration.id);
      await guidance.leaveCurrent();
    }
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final snapshot = await WsetProgressRepository(
      db,
      scope: scope,
      clock: clock,
    ).snapshot();
    final checker = CoverageChecker(
      db,
      CoveragePolicy.parse(
        File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
      ),
    );
    for (final level in snapshot.levels) {
      final audit = await checker.check(
        level.scope.certificationId,
        on: isoDate(clock.now().toUtc()),
      );
      expect(
        level.corePracticeCoverage!.core,
        audit.counts[CoverageMetric.core],
        reason:
            '${level.scope.certificationId} core denominator must match the release audit',
      );
      expect(
        level.corePracticeCoverage!.useful,
        audit.counts[CoverageMetric.coreUsefulPractice],
        reason:
            '${level.scope.certificationId} useful core practice must match the release audit',
      );
    }
    for (final level in snapshot.levels.take(3)) {
      expect(level.requiredCounts, isNotNull);
      expect(level.requiredCounts!.mapped, greaterThan(0));
      expect(
        level.requiredCounts!.unavailable,
        0,
        reason:
            'Every declared required lesson must actually serve a mapped format: ${level.scope.certificationId}. '
            '${level.requirements.where((row) => row.counts.unavailable > 0).map((row) => '${row.requirement.id}: ${row.requirement.itemIds}').join('; ')}',
      );
      expect(
        level.appLevelComplete,
        isFalse,
        reason: 'A fresh learner still needs mastery and practice evidence.',
      );
    }
  });
}
