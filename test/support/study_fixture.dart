import 'package:clock/clock.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/scheduler_config.dart';

import 'curriculum_fixture.dart';

/// A clock that tests move by hand.
class TestClock {
  TestClock(this.now);

  DateTime now;

  late final clock = Clock(() => now);

  void advance(Duration duration) => now = now.add(duration);
}

/// The stored configuration without fuzzing, so intervals are reproducible
/// (audit FS-10).
fsrs.Scheduler unfuzzedScheduler(SchedulerConfig config) =>
    schedulerFor(config.copyWith(enableFuzzing: false));

/// The bundled dataset as plain maps and lists, merged into the shape of a
/// dataset in one file, for tests that change it.
Map<String, dynamic> bundledDatasetMap() => flattenDataset(curriculumAssetPath);
