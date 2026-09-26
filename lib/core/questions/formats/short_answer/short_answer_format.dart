import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../database/app_database.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';

/// One key point of a short answer: an item, named by its kind and answer,
/// with its statement.
final class KeyPoint {
  const KeyPoint({
    required this.itemId,
    required this.title,
    required this.statement,
  });

  final String itemId;

  /// The kind of point and its answer: "Soil: Kimmeridgian marl".
  final String title;

  /// The item's assertion text.
  final String statement;

  @override
  String toString() => title;
}

/// A short written answer (spec §T): a prompt about one subject, answered in
/// the learner's own words, then checked against its key points, each an
/// item.
final class ShortAnswerExercise implements Exercise {
  const ShortAnswerExercise({
    required this.primaryItemId,
    required this.questionTemplateId,
    required this.prompt,
    required this.seed,
    required this.keyPoints,
  });

  @override
  final String primaryItemId;

  @override
  final String questionTemplateId;

  @override
  final String prompt;

  @override
  final int seed;

  /// The points to check, in the template's order; the primary item's is
  /// one of them.
  final List<KeyPoint> keyPoints;

  @override
  String get formatId => ShortAnswerFormat.formatId;

  @override
  List<String> get itemIds => [
    primaryItemId,
    for (final point in keyPoints)
      if (point.itemId != primaryItemId) point.itemId,
  ];
}

/// What the learner answered: the text written, and the items of the key
/// points it covered.
final class ShortAnswerResponse {
  const ShortAnswerResponse(this.text, this.covered);

  final String text;
  final Set<String> covered;
}

/// Short written answers (backlog Q1, spec §T, QF-14). A template names the
/// relation types whose items are key points, each with a label, in its
/// `parameters`:
///
/// ```yaml
/// parameters:
///   key_points: { HAS_SOIL: Soil, HAS_CLIMATE: Climate }
/// ```
///
/// Ingestion writes one pool per subject with at least two key points. An
/// exercise checks the planned item and up to three more the learner has
/// studied; the learner ticks the points the answer covered: ticked is
/// Good, not ticked Again (question-system §4). The text is kept, never
/// machine-graded.
class ShortAnswerFormat extends ExerciseFormat {
  const ShortAnswerFormat();

  static const formatId = 'short_answer';

  /// The most key points one exercise checks, the planned item's included.
  static const maxKeyPoints = 4;

  @override
  String get id => formatId;

  @override
  String get label => 'Short answer';

  @override
  FormatFamily get family => FormatFamily.recall;

  /// Checked by the learner, against key points the app shows.
  @override
  bool get isObjective => false;

  @override
  FormatGeneration get generation => FormatGeneration.pooled;

  /// Free recall of facts, like the flashcard (QF-6, QF-14).
  @override
  int requiredDepth(String direction) => 2;

  /// The most demanding recall: after the flashcard and typed recall.
  @override
  int difficultyRank(String direction) => 8;

  /// Each key point's label, by relation type, in the template's order; null
  /// when the parameters do not name them.
  static Map<String, String>? keyPointsOf(QuestionTemplate template) {
    final text = template.parameters;
    if (text == null) return null;
    final points = (jsonDecode(text) as Map<String, Object?>)['key_points'];
    if (points is! Map<String, Object?>) return null;
    if (points.values.any((label) => label is! String)) return null;
    return points.cast<String, String>();
  }

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    final points = keyPointsOf(template);
    if (points == null) {
      return [
        'its parameters need key_points: a mapping from each relation type '
            'to the label of its key points',
      ];
    }
    return [
      if (!points.containsKey(template.relationType))
        'key_points leaves out its own relation type, '
            '${template.relationType}',
      for (final MapEntry(key: type, value: label) in points.entries) ...[
        if (!relationTypes.contains(type))
          'key_points names $type, which is no relation type',
        if (label.trim().isEmpty) 'key_points gives $type no label',
      ],
      if (template.promptTemplate
          .replaceAll('{subject.name}', '')
          .contains('{'))
        'a short-answer prompt names only {subject.name}',
    ];
  }

  /// One pool per subject with at least two key points in force.
  @override
  Future<int> generatePools(
    GeneratorContext context,
    QuestionTemplate template,
  ) async {
    final points = keyPointsOf(template)!;
    final bySubject = <String, List<KnowledgeItem>>{};
    for (final item in context.items) {
      if (points.containsKey(item.relationType)) {
        bySubject.putIfAbsent(item.subjectId, () => []).add(item);
      }
    }
    bySubject.removeWhere((_, items) => items.length < 2);
    if (bySubject.isEmpty) return 0;
    final db = context.db;
    final names = {
      for (final node in await (db.select(
        db.knowledgeNodes,
      )..where((n) => n.id.isIn(bySubject.keys))).get())
        node.id: node.name,
    };
    for (final MapEntry(key: subject, value: items) in bySubject.entries) {
      final pool = await db
          .into(db.exercisePools)
          .insert(
            ExercisePoolsCompanion.insert(
              questionTemplateId: template.id,
              scopeNodeId: Value(subject),
              promptText: template.promptTemplate.replaceAll(
                '{subject.name}',
                names[subject]!,
              ),
            ),
          );
      await db.batch(
        (b) => b.insertAll(db.exercisePoolItems, [
          for (final item in items)
            ExercisePoolItemsCompanion.insert(
              exercisePoolId: pool,
              knowledgeItemId: item.id,
            ),
        ]),
      );
    }
    return bySubject.length;
  }

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final db = context.db;
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    final labels = keyPointsOf(template)!;
    final rows = await db
        .customSelect(
          '''
      SELECT p.id AS pool, p.prompt_text, i.knowledge_item_id AS item,
             k.relation_type, k.assertion_text, n.name AS answer,
             s.due, s.knowledge_item_id IS NOT NULL AS studied
      FROM exercise_pools p
      JOIN exercise_pool_items mine ON mine.exercise_pool_id = p.id
        AND mine.knowledge_item_id = ?1
      JOIN exercise_pool_items i ON i.exercise_pool_id = p.id
      JOIN knowledge_items k ON k.id = i.knowledge_item_id
      JOIN knowledge_nodes n ON n.id = k.object_id
      LEFT JOIN review_states s ON s.knowledge_item_id = i.knowledge_item_id
      WHERE p.question_template_id = ?2
      ORDER BY p.id, i.knowledge_item_id''',
          variables: [Variable(itemId), Variable(questionTemplateId)],
          readsFrom: {
            db.exercisePools,
            db.exercisePoolItems,
            db.knowledgeItems,
            db.knowledgeNodes,
            db.reviewStates,
          },
        )
        .get();
    if (rows.isEmpty) {
      throw StateError('$itemId is in no pool of $questionTemplateId');
    }
    final pool = rows.first.read<int>('pool');
    final points = [
      for (final row in rows)
        if (row.read<int>('pool') == pool) row,
    ];

    // The planned item, and up to three others the learner has studied, due
    // ones first, each group in the seed's order. A new item joins only when
    // none has been studied, so that two points are checked: a short answer
    // does not introduce items past the session's budget (A-2).
    final random = Random(seed);
    int group(QueryRow row) {
      if (row.readNullable<DateTime>('due') case final due?
          when !due.isAfter(context.now)) {
        return 0;
      }
      return row.read<bool>('studied') ? 1 : 2;
    }

    List<QueryRow> othersIn(int g) => [
      for (final row in points)
        if (row.read<String>('item') != itemId && group(row) == g) row,
    ]..shuffle(random);
    final studied = [...othersIn(0), ...othersIn(1)];
    final chosen = [
      points.firstWhere((row) => row.read<String>('item') == itemId),
      ...studied.isNotEmpty
          ? studied.take(maxKeyPoints - 1)
          : othersIn(2).take(1),
    ];
    final order = labels.keys.toList();
    KeyPoint pointOf(QueryRow row) => KeyPoint(
      itemId: row.read<String>('item'),
      title:
          '${labels[row.read<String>('relation_type')]}: '
          '${row.read<String>('answer')}',
      statement: row.read<String>('assertion_text'),
    );
    int rank(QueryRow row) => order.indexOf(row.read<String>('relation_type'));
    chosen.sort((a, b) {
      final byKind = rank(a).compareTo(rank(b));
      return byKind != 0
          ? byKind
          : a.read<String>('answer').compareTo(b.read<String>('answer'));
    });
    return ShortAnswerExercise(
      primaryItemId: itemId,
      questionTemplateId: questionTemplateId,
      prompt: points.first.read<String>('prompt_text'),
      seed: seed,
      keyPoints: [for (final row in chosen) pointOf(row)],
    );
  }

  /// [answer] is a [ShortAnswerResponse]. The text goes into the planned
  /// item's payload; every item records whether it was covered.
  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (answer is! ShortAnswerResponse) {
      throw ArgumentError.value(answer, 'answer', 'is not a short answer');
    }
    final items = exercise.itemIds;
    if (answer.covered.any((id) => !items.contains(id))) {
      throw ArgumentError.value(
        answer.covered,
        'answer',
        'covers a point the exercise does not check',
      );
    }
    return [
      for (final id in items)
        ItemGrade(
          id,
          answer.covered.contains(id) ? fsrs.Rating.good : fsrs.Rating.again,
          payload: {
            if (id == exercise.primaryItemId) 'text': answer.text,
            'covered': answer.covered.contains(id),
          },
        ),
    ];
  }
}
