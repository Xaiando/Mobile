import 'dart:math';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'exercise.dart';
import 'question_generator.dart';

/// One answer option: a node, shown by its name.
class QuestionOption {
  const QuestionOption(this.nodeId, this.name);

  final String nodeId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is QuestionOption && other.nodeId == nodeId;

  @override
  int get hashCode => nodeId.hashCode;

  @override
  String toString() => name;
}

/// A single-item question as shown to the learner: a flashcard or an MCQ.
class PresentedQuestion implements Exercise {
  const PresentedQuestion({
    required this.knowledgeItemId,
    required this.questionTemplateId,
    required this.direction,
    required this.mode,
    required this.prompt,
    required this.answer,
    required this.options,
    required this.explanation,
    required this.seed,
  });

  final String knowledgeItemId;
  @override
  final String questionTemplateId;

  /// `forward` or `reverse`.
  final String direction;

  /// `mcq` or `flashcard`.
  final String mode;
  @override
  final String prompt;
  final QuestionOption answer;

  /// Four options in display order for an MCQ; empty for a flashcard.
  final List<QuestionOption> options;

  /// The item's assertion, shown after answering.
  final String explanation;

  /// The seed that fixed the options and their order (QG-7). A review event
  /// logs it, together with the options shown.
  @override
  final int seed;

  @override
  String get formatId => mode;

  @override
  String get primaryItemId => knowledgeItemId;

  @override
  List<String> get itemIds => [knowledgeItemId];

  bool get isMultipleChoice => mode == 'mcq';

  /// The answer's position in [options], or -1 for a flashcard.
  int get correctIndex => options.indexOf(answer);
}

/// Turns stored questions into presentations (spec §H, audit QG-7).
///
/// A fresh seed per presentation draws [distractorsPerQuestion] wrong
/// answers from the question's pool, nearest scope first, and shuffles the
/// four options. The same seed always gives the same presentation.
class QuestionPresenter {
  QuestionPresenter(this.db);

  final AppDatabase db;

  /// A new presentation seed. Seeds stay below 2^31, so they round-trip
  /// exactly on the web as well.
  static int newSeed([Random? random]) => (random ?? Random()).nextInt(1 << 31);

  /// The questions generated for [knowledgeItemId].
  Future<List<Question>> questionsFor(String knowledgeItemId) =>
      (db.select(db.questions)
            ..where((q) => q.knowledgeItemId.equals(knowledgeItemId))
            ..orderBy([(q) => OrderingTerm(expression: q.questionTemplateId)]))
          .get();

  /// Presents one question with [seed].
  Future<PresentedQuestion> present(
    String knowledgeItemId,
    String questionTemplateId, {
    required int seed,
  }) async {
    final row = await db
        .customSelect(
          '''
      SELECT q.prompt_text, t.direction, t.mode, i.assertion_text,
             CASE t.direction WHEN 'forward' THEN i.object_id
                              ELSE i.subject_id END AS answer_id
      FROM questions q
      JOIN question_templates t ON t.id = q.question_template_id
      JOIN knowledge_items i ON i.id = q.knowledge_item_id
      WHERE q.knowledge_item_id = ?1 AND q.question_template_id = ?2''',
          variables: [Variable(knowledgeItemId), Variable(questionTemplateId)],
          readsFrom: {db.questions, db.questionTemplates, db.knowledgeItems},
        )
        .getSingle();
    final answerId = row.read<String>('answer_id');
    final answerNode = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.equals(answerId))).getSingle();
    final answer = QuestionOption(answerNode.id, answerNode.name);
    final mode = row.read<String>('mode');

    var options = const <QuestionOption>[];
    if (mode == 'mcq') {
      final random = Random(seed);
      final pool = await db
          .customSelect(
            '''
        SELECT d.knowledge_node_id, d.scope_rank, n.name
        FROM question_distractors d
        JOIN knowledge_nodes n ON n.id = d.knowledge_node_id
        WHERE d.knowledge_item_id = ?1 AND d.question_template_id = ?2
        ORDER BY d.scope_rank, d.knowledge_node_id''',
            variables: [
              Variable(knowledgeItemId),
              Variable(questionTemplateId),
            ],
            readsFrom: {db.questionDistractors, db.knowledgeNodes},
          )
          .get();
      final byRank = <int, List<QuestionOption>>{};
      for (final candidate in pool) {
        byRank
            .putIfAbsent(candidate.read<int>('scope_rank'), () => [])
            .add(
              QuestionOption(
                candidate.read<String>('knowledge_node_id'),
                candidate.read<String>('name'),
              ),
            );
      }
      // Nearest scope first; the seed varies the choice within a scope.
      final chosen = <QuestionOption>[];
      for (final rank in byRank.keys.toList()..sort()) {
        chosen.addAll(byRank[rank]!..shuffle(random));
      }
      if (chosen.length < distractorsPerQuestion) {
        throw StateError(
          '$knowledgeItemId × $questionTemplateId has only '
          '${chosen.length} distractors',
        );
      }
      options = [answer, ...chosen.take(distractorsPerQuestion)]
        ..shuffle(random);
    }

    return PresentedQuestion(
      knowledgeItemId: knowledgeItemId,
      questionTemplateId: questionTemplateId,
      direction: row.read<String>('direction'),
      mode: mode,
      prompt: row.read<String>('prompt_text'),
      answer: answer,
      options: options,
      explanation: row.read<String>('assertion_text'),
      seed: seed,
    );
  }
}
