import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../database/app_database.dart';
import '../time/utc_clock.dart';

/// Scheduler configuration version 1 (architecture audit FS-8): the FSRS-6
/// default weights, the spec's 90 % desired retention, and the package's
/// default steps, maximum interval and fuzzing (validation S-5).
SchedulerConfigsCompanion schedulerConfigV1(DateTime createdAt) =>
    SchedulerConfigsCompanion.insert(
      version: const Value(1),
      weights: jsonEncode(fsrs.defaultParameters),
      desiredRetention: 0.9,
      learningStepsSeconds: '[60, 600]',
      relearningStepsSeconds: '[600]',
      maximumIntervalDays: 36500,
      enableFuzzing: true,
      createdAt: createdAt,
    );

/// Makes sure configuration version 1 exists and returns the newest
/// configuration, which schedules every new review.
///
/// Startup calls this on first launch; the review service calls it again,
/// so a review never depends on startup order.
Future<SchedulerConfig> ensureSchedulerConfig(
  AppDatabase db, {
  Clock? clock,
}) async {
  final latest = await latestSchedulerConfig(db);
  if (latest != null) return latest;
  await db.into(db.schedulerConfigs).insert(schedulerConfigV1(utcNow(clock)));
  return (await latestSchedulerConfig(db))!;
}

/// The newest configuration, or null before the first launch seeded one.
Future<SchedulerConfig?> latestSchedulerConfig(AppDatabase db) =>
    (db.select(db.schedulerConfigs)
          ..orderBy([(c) => OrderingTerm.desc(c.version)])
          ..limit(1))
        .getSingleOrNull();

/// Builds the package's scheduler from a stored configuration.
///
/// Fuzzing draws from the package's own random generator. Tests pass their
/// own factory to the review service instead (FS-10).
fsrs.Scheduler schedulerFor(SchedulerConfig config) => fsrs.Scheduler(
  parameters: [
    for (final weight in jsonDecode(config.weights) as List)
      (weight as num).toDouble(),
  ],
  desiredRetention: config.desiredRetention,
  learningSteps: _steps(config.learningStepsSeconds),
  relearningSteps: _steps(config.relearningStepsSeconds),
  maximumInterval: config.maximumIntervalDays,
  enableFuzzing: config.enableFuzzing,
);

List<Duration> _steps(String secondsJson) => [
  for (final seconds in jsonDecode(secondsJson) as List)
    Duration(seconds: (seconds as num).toInt()),
];
