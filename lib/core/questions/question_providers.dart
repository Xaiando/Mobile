import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'exercise_presenter.dart';
import 'format_registry.dart';
import 'question_presenter.dart';

/// The formats the app presents (question-system §9). Tests override it to
/// add a format.
final formatRegistryProvider = Provider<FormatRegistry>((ref) => appFormats);

final questionPresenterProvider = Provider<QuestionPresenter>(
  (ref) => QuestionPresenter(ref.watch(appDatabaseProvider)),
);

final exercisePresenterProvider = Provider<ExercisePresenter>(
  (ref) => ExercisePresenter(
    ref.watch(appDatabaseProvider),
    formats: ref.watch(formatRegistryProvider),
    clock: ref.watch(clockProvider),
  ),
);
