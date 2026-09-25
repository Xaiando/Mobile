import 'dart:math';

import 'package:clock/clock.dart';

import '../database/app_database.dart';
import '../time/utc_clock.dart';
import 'exercise.dart';
import 'exercise_format.dart';
import 'format_registry.dart';

/// Presents any template's exercise through its format (question-system §9).
class ExercisePresenter {
  ExercisePresenter(this.db, {FormatRegistry? formats, Clock? clock})
    : formats = formats ?? appFormats,
      _clock = clock ?? const Clock();

  final AppDatabase db;
  final FormatRegistry formats;
  final Clock _clock;

  /// A new presentation seed. Seeds stay below 2^31, so they round-trip
  /// exactly on the web as well.
  static int newSeed([Random? random]) => (random ?? Random()).nextInt(1 << 31);

  /// Presents [itemId] with [questionTemplateId] and [seed].
  Future<Exercise> present(
    String itemId,
    String questionTemplateId, {
    required int seed,
  }) async {
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    return formats
        .require(template.mode)
        .present(
          PresentationContext(db, now: utcNow(_clock)),
          itemId: itemId,
          questionTemplateId: questionTemplateId,
          seed: seed,
        );
  }

  /// The grades [answer] earns in [exercise], by its format.
  List<ItemGrade> grade(Exercise exercise, Object answer) =>
      formats.require(exercise.formatId).grade(exercise, answer);
}
