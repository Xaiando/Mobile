import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../study/study_providers.dart';
import '../time/time_providers.dart';
import 'wset_progress.dart';
import 'wset_scope.dart';

final wsetScopeProvider = FutureProvider<WsetScope>(
  (ref) async => WsetScope.fromJson(
    await rootBundle.loadString('assets/progress/wset_scope.json'),
  ),
);

final wsetProgressRepositoryProvider =
    Provider.family<WsetProgressRepository, WsetScope>(
      (ref, scope) => WsetProgressRepository(
        ref.watch(appDatabaseProvider),
        scope: scope,
        planner: ref.watch(studyPlannerProvider),
        clock: ref.watch(clockProvider),
      ),
    );
