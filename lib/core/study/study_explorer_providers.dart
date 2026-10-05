import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'study_explorer.dart';

final studyExplorerProvider = Provider<StudyExplorer>(
  (ref) => StudyExplorer(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final studyTopicsProvider = FutureProvider.autoDispose<List<StudyTopic>>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  return ref.watch(studyExplorerProvider).topics();
});
