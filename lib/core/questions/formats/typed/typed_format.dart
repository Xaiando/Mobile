import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/name_normalizer.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// A typed-recall question: a flashcard's prompt, answered by typing, with
/// the names that count as right.
final class TypedQuestion extends PresentedQuestion {
  const TypedQuestion({
    required super.knowledgeItemId,
    required super.questionTemplateId,
    required super.direction,
    required super.mode,
    required super.prompt,
    required super.answer,
    required super.explanation,
    required super.seed,
    required this.accepted,
    required this.rivals,
    required this.typeWords,
  }) : super(options: const []);

  /// Every name that answers the question, as a [TypedFormat.core], with the
  /// name of the node it names: each correct node in any validity period,
  /// and its alternative names (synonyms, former names, spellings; QF-8).
  final Map<String, String> accepted;

  /// The names of every other node, and their alternative names, as cores:
  /// typing one is a wrong answer, never a slip or a part of the answer.
  final Set<String> rivals;

  /// The words of the answer's node type ("climate", "grape variety"), in
  /// the singular and the plural, which an answer may add or leave out.
  final Set<String> typeWords;
}

/// How a typed answer was graded (QF-4, QF-13).
enum TypedOutcome {
  /// An accepted name, after normalizing case, accents, spacing and the
  /// answer type's words.
  exact,

  /// One edit away from an accepted name: Hard.
  near,

  /// Part of an accepted name that names nothing else, such as "frost"
  /// for "Spring frost": Hard.
  partial,

  /// Anything else: Again.
  wrong,
}

/// Typed recall (backlog Q1): the learner types the answer, and the app
/// grades it (QF-4, QF-13). An accepted name is Good; a slip of one letter,
/// or part of the name that names nothing else, is Hard; anything else,
/// Again. It turns self-graded recall into an objective format.
class TypedFormat extends ExerciseFormat {
  const TypedFormat();

  static const _articles = {'the', 'a', 'an'};

  @override
  String get id => 'typed';

  @override
  String get label => 'Type the answer';

  @override
  FormatFamily get family => FormatFamily.recall;

  @override
  bool get isObjective => true;

  /// Forward recall from depth 2, reverse from 3 (QF-6).
  @override
  int requiredDepth(String direction) => direction == 'reverse' ? 3 : 2;

  /// After the formats that show the answer, so a new item starts with one
  /// of them (FS-15).
  @override
  int difficultyRank(String direction) => direction == 'reverse' ? 7 : 6;

  /// The words of a node type's [label], in the singular and the plural.
  static Set<String> typeWordsOf(String label) => {
    for (final word in normalizeName(label).split(' '))
      if (word.isNotEmpty) ...[
        word,
        word.endsWith('y')
            ? '${word.substring(0, word.length - 1)}ies'
            : '${word}s',
      ],
  };

  /// A normalized name without a leading article and without the answer
  /// type's words at its end, unless nothing else would remain: "the
  /// oceanic climate" and "Oceanic" are both "oceanic".
  static String core(String norm, Set<String> typeWords) {
    final words = norm.split(' ').where((w) => w.isNotEmpty).toList();
    while (words.length > 1 && _articles.contains(words.first)) {
      words.removeAt(0);
    }
    while (words.length > 1 && typeWords.contains(words.last)) {
      words.removeLast();
    }
    return words.join(' ');
  }

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final db = context.db;
    final question = await QuestionPresenter(db)
        .present(itemId, questionTemplateId, seed: seed);
    final item = await (db.select(
      db.knowledgeItems,
    )..where((i) => i.id.equals(itemId))).getSingle();
    final answerNode = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.equals(question.answer.nodeId))).getSingle();
    final type = await (db.select(
      db.nodeTypes,
    )..where((t) => t.id.equals(answerNode.nodeType))).getSingle();
    final typeWords = typeWordsOf(type.label);
    String coreOf(String norm) => core(norm, typeWords);

    // Every node the relation gives as an answer, in any period (QF-8).
    final forward = question.direction == 'forward';
    final (from, to, given) = forward
        ? ('subject_id', 'object_id', item.subjectId)
        : ('object_id', 'subject_id', item.objectId);
    final answers = await db
        .customSelect(
          '''
      SELECT n.id, n.name, n.name_norm FROM knowledge_relations r
      JOIN knowledge_nodes n ON n.id = r.$to
      WHERE r.$from = ?1 AND r.relation_type = ?2''',
          variables: [Variable(given), Variable(item.relationType)],
          readsFrom: {db.knowledgeRelations, db.knowledgeNodes},
        )
        .get();
    final names = {
      for (final row in answers)
        row.read<String>('id'): row.read<String>('name'),
    };
    final accepted = <String, String>{
      for (final row in answers)
        coreOf(row.read<String>('name_norm')): row.read<String>('name'),
    };
    final rivals = <String>{};
    for (final node in await db.select(db.knowledgeNodes).get()) {
      if (!names.containsKey(node.id)) rivals.add(coreOf(node.nameNorm));
    }
    for (final alternative in await db.select(db.nodeAlternativeNames).get()) {
      final name = coreOf(alternative.nameNorm);
      if (names[alternative.knowledgeNodeId] case final answer?) {
        accepted[name] = answer;
      } else {
        rivals.add(name);
      }
    }
    rivals.removeAll(accepted.keys);
    return TypedQuestion(
      knowledgeItemId: question.knowledgeItemId,
      questionTemplateId: question.questionTemplateId,
      direction: question.direction,
      mode: question.mode,
      prompt: question.prompt,
      answer: question.answer,
      explanation: question.explanation,
      seed: seed,
      accepted: accepted,
      rivals: rivals,
      typeWords: typeWords,
    );
  }

  /// Whether [part]'s words are a run of [whole]'s words.
  static bool _isPart(String part, String whole) =>
      ' $whole '.contains(' $part ');

  /// How [typed] answers [question], and the accepted name it came to.
  static (TypedOutcome, String?) outcome(TypedQuestion question, String typed) {
    final text = core(normalizeName(typed), question.typeWords);
    if (text.isEmpty) return (TypedOutcome.wrong, null);
    if (question.accepted[text] case final name?) {
      return (TypedOutcome.exact, name);
    }
    if (question.rivals.contains(text)) return (TypedOutcome.wrong, null);
    // A slip of one letter, but not in a name so short that one letter
    // makes another word.
    for (final MapEntry(key: norm, value: name) in question.accepted.entries) {
      if (norm.length >= 4 && editDistance(text, norm, limit: 1) <= 1) {
        return (TypedOutcome.near, name);
      }
    }
    // Whole words of the name, long enough to mean something, and part of
    // no other name.
    if (text.replaceAll(' ', '').length >= 5 &&
        !question.rivals.any((rival) => _isPart(text, rival))) {
      for (final MapEntry(key: norm, value: name)
          in question.accepted.entries) {
        if (_isPart(text, norm)) return (TypedOutcome.partial, name);
      }
    }
    return (TypedOutcome.wrong, null);
  }

  /// [answer] is the text the learner typed.
  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    final question = exercise as TypedQuestion;
    if (answer is! String) {
      throw ArgumentError.value(answer, 'answer', 'is not typed text');
    }
    final (result, matched) = outcome(question, answer);
    return [
      ItemGrade(
        question.knowledgeItemId,
        switch (result) {
          TypedOutcome.exact => fsrs.Rating.good,
          TypedOutcome.near || TypedOutcome.partial => fsrs.Rating.hard,
          TypedOutcome.wrong => fsrs.Rating.again,
        },
        payload: {'typed': answer, 'matched': matched, 'outcome': result.name},
      ),
    ];
  }
}
