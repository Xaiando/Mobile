import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'question_feedback.dart';

final questionFeedbackProvider = Provider<QuestionFeedback>(
  (ref) => QuestionFeedback(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Every flag the learner raised, the newest first.
final flagsProvider = StreamProvider<List<QuestionFlag>>(
  (ref) => ref.watch(questionFeedbackProvider).watchAll(),
);
