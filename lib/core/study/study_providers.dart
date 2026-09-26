import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../questions/question_providers.dart';
import '../time/time_providers.dart';
import 'learner_profile.dart';
import 'review_service.dart';
import 'study_planner.dart';

final learnerProfilesProvider = Provider<LearnerProfiles>(
  (ref) => LearnerProfiles(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final reviewServiceProvider = Provider<ReviewService>(
  (ref) => ReviewService(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final studyPlannerProvider = Provider<StudyPlanner>(
  (ref) => StudyPlanner(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    formats: ref.watch(formatRegistryProvider),
  ),
);
