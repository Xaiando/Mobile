import 'dart:math';

import 'package:clock/clock.dart';

import '../database/app_database.dart';
import '../time/utc_clock.dart';
import '../curriculum/knowledge_graph.dart';
import '../study/study_planner.dart';
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
    String? certificationId,
  }) async {
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    Set<String>? allowedItems;
    if (template.mode == 'short_answer') {
      final profile = await db.select(db.userProfiles).getSingleOrNull();
      final track = certificationId ?? profile?.activeCertificationId;
      if (track != null) {
        // Use actual delivery rather than mapping depth alone: this also
        // respects currentness, template membership and the planner fallback.
        final cards = await StudyPlanner(
          db,
          formats: formats,
          clock: _clock,
        ).cards(track);
        allowedItems = {
          for (final card in cards)
            if (card.formats.any(
              (format) => format.questionTemplateId == template.id,
            ))
              card.itemId,
        };
        if (!allowedItems.contains(itemId)) {
          throw ArgumentError(
            'This track does not serve short_answer for $itemId',
          );
        }
      }
    } else if (template.mode == 'reasoning' || template.mode == 'map_pair') {
      final profile = await db.select(db.userProfiles).getSingleOrNull();
      final track = certificationId ?? profile?.activeCertificationId;
      if (track != null) {
        final mapping = await StudyPlanner(db).effectiveMappings(track);
        final format = formats.require(template.mode);
        if ((mapping[itemId]?.minimumDepth ?? 0) <
            format.requiredDepth(template.direction)) {
          throw ArgumentError(
            'This track does not serve ${template.mode} for $itemId',
          );
        }
        final current = await KnowledgeGraph(db, clock: _clock).currentItems();
        allowedItems = {
          for (final item in current)
            if (mapping.containsKey(item.id)) item.id,
        };
      }
    }
    return formats
        .require(template.mode)
        .present(
          PresentationContext(
            db,
            now: utcNow(_clock),
            allowedItemIds: allowedItems,
          ),
          itemId: itemId,
          questionTemplateId: questionTemplateId,
          seed: seed,
        );
  }

  /// The grades [answer] earns in [exercise], by its format.
  List<ItemGrade> grade(Exercise exercise, Object answer) =>
      formats.require(exercise.formatId).grade(exercise, answer);
}
