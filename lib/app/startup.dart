import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/curriculum/curriculum_providers.dart';
import '../core/database/database_providers.dart';
import '../core/database/storage_durability.dart';
import '../core/study/scheduler_config.dart';
import '../core/time/utc_clock.dart';

/// Opens the database (running migrations), brings the bundled curriculum
/// into it (spec §O, Phase 1), seeds the FSRS scheduler configuration
/// (audit FS-8), and reports how durable the storage is.
///
/// Drift connects lazily, so this is also what triggers the web storage choice.
final appStartupProvider = FutureProvider<StorageDurability>((ref) async {
  final database = ref.watch(appDatabaseProvider);
  await database.ensureOpen();
  final source = await ref.watch(curriculumSourceProvider)();
  await ref.watch(curriculumIngesterProvider).ensureCurrent(source);
  await ensureSchedulerConfig(database, clock: ref.watch(clockProvider));
  return ref.watch(storageReportProvider).durability;
});
