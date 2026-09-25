import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

/// Why a learner flagged a question.
enum FlagReason {
  wrong('The answer is wrong'),
  unclear('The question is unclear'),
  outdated('It is out of date'),
  other('Something else');

  const FlagReason(this.label);

  final String label;
}

/// Questions the learner flagged (backlog R1). Flags stay on the device and
/// travel in the data export, so curators hear of problems without
/// telemetry.
class QuestionFeedback {
  QuestionFeedback(this.db, {Clock? clock, this.random})
    : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  /// Makes flag IDs reproducible in tests; secure by default.
  final Random? random;

  /// Flags the question of [itemId] asked with [templateId], for [reason].
  Future<QuestionFlag> flag({
    required String itemId,
    String? templateId,
    required FlagReason reason,
    String? note,
  }) async {
    final id = newUuid(random);
    final trimmed = note?.trim();
    await db
        .into(db.questionFlags)
        .insert(
          QuestionFlagsCompanion.insert(
            id: id,
            knowledgeItemId: itemId,
            questionTemplateId: Value(templateId),
            reason: reason.name,
            note: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
            createdAt: utcNow(_clock),
          ),
        );
    return (db.select(
      db.questionFlags,
    )..where((f) => f.id.equals(id))).getSingle();
  }

  /// Every flag, the newest first.
  Stream<List<QuestionFlag>> watchAll() => (db.select(
    db.questionFlags,
  )..orderBy([(f) => OrderingTerm.desc(f.createdAt)])).watch();

  Future<void> delete(String id) =>
      (db.delete(db.questionFlags)..where((f) => f.id.equals(id))).go();
}
