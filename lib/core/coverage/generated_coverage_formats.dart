import '../curriculum/reasoning_paths.dart';
import '../database/app_database.dart';
import '../questions/formats/reasoning/reasoning_format.dart';
import '../study/study_planner.dart';

typedef _GeneratedRow = ({
  String itemId,
  String templateId,
  String direction,
  String mode,
  int? poolId,
});

/// Generated questions and valid pooled exercises a track can eventually
/// serve, regardless of which prerequisites this learner has studied today.
/// Both the release audit and learner-facing content coverage use this source.
final class GeneratedCoverageFormats {
  const GeneratedCoverageFormats._(
    this._validPools,
    this._poolMembers,
    this._rows,
  );

  final Set<int> _validPools;
  final Map<int, Set<String>> _poolMembers;
  final List<_GeneratedRow> _rows;

  /// Read current generated questions once, then apply each cumulative
  /// track's own mapping to pooled reasoning questions.
  static Future<GeneratedCoverageFormats> read(
    AppDatabase db, {
    required String on,
  }) async {
    final validPools = await ReasoningPaths(db).validPoolIds(on: on);
    final poolMembers = <int, Set<String>>{};
    for (final member in await db.select(db.exercisePoolItems).get()) {
      poolMembers
          .putIfAbsent(member.exercisePoolId, () => {})
          .add(member.knowledgeItemId);
    }
    final queryRows = await db
        .customSelect(
          '''
      SELECT q.knowledge_item_id, q.question_template_id, t.direction, t.mode, NULL AS pool_id
      FROM questions q
      JOIN question_templates t ON t.id = q.question_template_id
      UNION
      SELECT i.knowledge_item_id, p.question_template_id, t.direction, t.mode, p.id AS pool_id
      FROM exercise_pool_items i
      JOIN exercise_pools p ON p.id = i.exercise_pool_id
      JOIN question_templates t ON t.id = p.question_template_id
      WHERE ${ReasoningFormat.scheduledPoolMemberSql()}
      ORDER BY 1, 2''',
          readsFrom: {
            db.questions,
            db.questionTemplates,
            db.exercisePools,
            db.exercisePoolItems,
          },
        )
        .get();
    return GeneratedCoverageFormats._(validPools, poolMembers, [
      for (final row in queryRows)
        (
          itemId: row.read<String>('knowledge_item_id'),
          templateId: row.read<String>('question_template_id'),
          direction: row.read<String>('direction'),
          mode: row.read<String>('mode'),
          poolId: row.readNullable<int>('pool_id'),
        ),
    ]);
  }

  Map<String, List<QuestionFormat>> forMappedItems(Set<String> mappedItems) {
    final validPools = {
      for (final id in _validPools)
        if (_poolMembers[id]?.every(mappedItems.contains) ?? false) id,
    };
    final formats = <String, List<QuestionFormat>>{};
    final seen = <(String, String)>{};
    for (final row in _rows) {
      if (!mappedItems.contains(row.itemId) ||
          (row.mode == ReasoningFormat.formatId &&
              !validPools.contains(row.poolId))) {
        continue;
      }
      if (!seen.add((row.itemId, row.templateId))) continue;
      formats
          .putIfAbsent(row.itemId, () => [])
          .add(
            QuestionFormat(
              questionTemplateId: row.templateId,
              direction: row.direction,
              mode: row.mode,
            ),
          );
    }
    return formats;
  }
}
