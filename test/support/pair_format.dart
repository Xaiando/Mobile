import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/flashcard/flashcard_format.dart';
import 'package:sommelier/core/questions/formats/mcq/mcq_format.dart';
import 'package:sommelier/features/practice/format_views.dart';
import 'package:sommelier/features/practice/formats/flashcard_view.dart';
import 'package:sommelier/features/practice/formats/mcq_view.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import 'curriculum_fixture.dart';
import 'study_fixture.dart';

/// A test-only composite format (backlog F3): two items of one relation
/// type, shown as their statements; the learner says which they knew. It
/// proves the runtime end to end: pooled generation, a co-item preferring
/// due items, grading per item and one exercise ID.
class PairFormat extends ExerciseFormat {
  const PairFormat();

  static const formatId = 'test_pair';

  @override
  String get id => formatId;

  @override
  String get label => 'Pair';

  @override
  FormatFamily get family => FormatFamily.structured;

  @override
  bool get isObjective => true;

  @override
  FormatGeneration get generation => FormatGeneration.pooled;

  @override
  int requiredDepth(String direction) => 1;

  /// Easiest of all, so a new item's session presents it.
  @override
  int difficultyRank(String direction) => -1;

  /// One pool per template: every item in force of its relation type.
  @override
  Future<int> generatePools(
    PoolContext context,
    QuestionTemplate template,
  ) async {
    final items = [
      for (final item in context.items)
        if (item.relationType == template.relationType) item,
    ];
    if (items.length < 2) return 0;
    final db = context.db;
    final pool = await db
        .into(db.exercisePools)
        .insert(
          ExercisePoolsCompanion.insert(
            questionTemplateId: template.id,
            promptText: template.promptTemplate,
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
    return 1;
  }

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final rows = await context.db
        .customSelect(
          '''
      SELECT i.knowledge_item_id AS id, p.prompt_text, k.assertion_text,
             s.due
      FROM exercise_pools p
      JOIN exercise_pool_items mine ON mine.exercise_pool_id = p.id
        AND mine.knowledge_item_id = ?1
      JOIN exercise_pool_items i ON i.exercise_pool_id = p.id
      JOIN knowledge_items k ON k.id = i.knowledge_item_id
      LEFT JOIN review_states s ON s.knowledge_item_id = i.knowledge_item_id
      WHERE p.question_template_id = ?2
      ORDER BY i.knowledge_item_id''',
          variables: [Variable(itemId), Variable(questionTemplateId)],
        )
        .get();
    final statements = {
      for (final row in rows)
        row.read<String>('id'): row.read<String>('assertion_text'),
    };
    final others = [
      for (final row in rows)
        if (row.read<String>('id') != itemId) row,
    ];
    final due = [
      for (final row in others)
        if (row.readNullable<DateTime>('due') case final at?
            when !at.isAfter(context.now))
          row,
    ];
    final candidates = due.isNotEmpty ? due : others;
    final co = candidates[Random(seed).nextInt(candidates.length)].read<String>(
      'id',
    );
    return PairExercise(
      primaryItemId: itemId,
      coItemId: co,
      questionTemplateId: questionTemplateId,
      prompt: rows.first.read<String>('prompt_text'),
      seed: seed,
      statements: {itemId: statements[itemId]!, co: statements[co]!},
    );
  }

  /// [answer] is the set of item IDs the learner knew: Good for those,
  /// Again for the rest.
  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (answer is! Set<String>) {
      throw ArgumentError.value(answer, 'answer', 'is not a set of items');
    }
    return [
      for (final id in exercise.itemIds)
        ItemGrade(
          id,
          answer.contains(id) ? fsrs.Rating.good : fsrs.Rating.again,
          payload: {'known': answer.contains(id)},
        ),
    ];
  }
}

class PairExercise implements Exercise {
  const PairExercise({
    required this.primaryItemId,
    required this.coItemId,
    required this.questionTemplateId,
    required this.prompt,
    required this.seed,
    required this.statements,
  });

  @override
  final String primaryItemId;
  final String coItemId;
  @override
  final String questionTemplateId;
  @override
  final String prompt;
  @override
  final int seed;

  /// Each item's statement, the primary first.
  final Map<String, String> statements;

  @override
  String get formatId => PairFormat.formatId;

  @override
  List<String> get itemIds => [primaryItemId, coItemId];
}

/// The app's formats and the pair format.
final pairFormats = FormatRegistry(const [
  FlashcardFormat(),
  McqFormat(),
  PairFormat(),
]);

/// The bundled release with a pair template for every relation type that
/// has a forward template.
Map<String, dynamic> datasetWithPairs() {
  final data = copyOf(bundledDatasetMap());
  final relationTypes = {
    for (final template in rowsOf(data, 'question_templates'))
      if (template['direction'] == 'forward') template['relation_type'],
  };
  for (final type in relationTypes) {
    rowsOf(data, 'question_templates').add({
      'id': 'qt_${(type as String).toLowerCase()}_fwd_test_pair',
      'relation_type': type,
      'direction': 'forward',
      'mode': PairFormat.formatId,
      'prompt_template': 'Which of these did you know?',
    });
  }
  return data;
}

/// The practice view of the pair format: a checkbox per statement.
class PairView extends ConsumerStatefulWidget {
  const PairView(this.turn, {super.key});

  final SessionTurn turn;

  @override
  ConsumerState<PairView> createState() => _PairViewState();
}

class _PairViewState extends ConsumerState<PairView> {
  final _known = <String>{};

  @override
  Widget build(BuildContext context) {
    final exercise = widget.turn.exercise as PairExercise;
    final controller = ref.read(studySessionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: id, value: statement)
            in exercise.statements.entries)
          CheckboxListTile(
            value: _known.contains(id),
            title: Text(statement),
            onChanged: widget.turn.isAnswered
                ? null
                : (on) =>
                      setState(() => on! ? _known.add(id) : _known.remove(id)),
          ),
        if (widget.turn.isAnswered)
          FilledButton(
            onPressed: controller.next,
            child: const Text('Continue'),
          )
        else
          FilledButton(
            onPressed: () => controller.submit({..._known}),
            child: const Text('Check'),
          ),
      ],
    );
  }
}

/// The app's views and the pair format's.
final pairViews = <String, FormatView>{
  'mcq': FormatView(icon: Icons.list, builder: McqView.new),
  'flashcard': FormatView(
    icon: Icons.style_outlined,
    builder: FlashcardView.new,
  ),
  PairFormat.formatId: FormatView(
    icon: Icons.join_inner,
    builder: PairView.new,
  ),
};
