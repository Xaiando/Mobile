import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/name_normalizer.dart';
import '../../../database/app_database.dart';
import '../../../time/utc_clock.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// An original question naming the particular assertion it recalls. The
/// response phrases are authored evidence, not automatic prose assessment.
final class TypedItemCue {
  const TypedItemCue({required this.prompt, required this.acceptedAnswers});
  final String prompt;
  final List<String> acceptedAnswers;
}

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
    this.partialRivals,
    this.canonicalAnswer,
  }) : super(options: const []);

  /// Original point identity for a scoped cue. Displayed feedback instead
  /// supplies a responsive authored phrase; the assertion remains explanation.
  final String? canonicalAnswer;

  /// Authored responsive phrases for a scoped point cue; otherwise every
  /// name that answers the question, as a [TypedFormat.core], with the
  /// name of the node it names: each correct node in any validity period,
  /// except physical berry metadata and dated rankings, which use current
  /// relations so a retired erroneous value cannot remain a correct answer,
  /// and its alternative names (synonyms, former names, spellings; QF-8).
  final Map<String, String> accepted;

  /// The names of every other node, and their alternative names, as cores:
  /// typing one is a wrong answer, never a slip or a part of the answer.
  final Set<String> rivals;

  /// Names that could answer the relation, used to decide whether an
  /// incomplete answer is ambiguous. Exact known wrong names are still
  /// rejected through [rivals], including names from other node types.
  /// Older/manual presentations fall back to [rivals].
  final Set<String>? partialRivals;

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
  static final _cueCache = Expando<Map<String, TypedItemCue>>('typed cues');
  static final _cuedItemCache = Expando<Set<String>>(
    'generator typed cue items',
  );

  /// Absent cues retain existing legal alternatives and legacy presentations.
  /// A cue opts into finite authored-response grading for its primary point.
  /// Canonical titles and aliases count only when explicitly responsive and
  /// included by the writer; a broad title need not answer a narrow cue.
  static Map<String, TypedItemCue>? itemCuesOf(QuestionTemplate template) {
    if (template.parameters == null) return null;
    if (_cueCache[template] case final cached?) return cached;
    final parameters = jsonDecode(template.parameters!);
    if (parameters is! Map<String, dynamic>) {
      throw const FormatException('typed parameters must be an object');
    }
    if (!parameters.containsKey('item_cues')) return null;
    final entries = parameters['item_cues'];
    if (entries is! Map<String, dynamic> || entries.isEmpty) {
      throw const FormatException('item_cues must be a nonempty item mapping');
    }
    if (template.relationType != 'PRINCIPLE_EXPLANATION' ||
        template.direction != 'forward') {
      throw const FormatException(
        'item_cues need forward PRINCIPLE_EXPLANATION',
      );
    }
    final cues = <String, TypedItemCue>{};
    for (final entry in entries.entries) {
      final value = entry.value;
      if (!RegExp(r'^ki_[a-z0-9_]+$').hasMatch(entry.key) ||
          value is! Map<String, dynamic> ||
          value['prompt'] is! String ||
          (value['prompt'] as String).trim().isEmpty ||
          value['acceptedAnswers'] is! List ||
          (value['acceptedAnswers'] as List).isEmpty) {
        throw FormatException('Invalid typed item cue: ${entry.key}');
      }
      final rawAnswers = value['acceptedAnswers'] as List;
      if (rawAnswers.any(
        (answer) => answer is! String || answer.trim().isEmpty,
      )) {
        throw FormatException('Invalid typed cue answers: ${entry.key}');
      }
      final answers = rawAnswers.cast<String>();
      final normalized = answers.map(normalizeName).toSet();
      if (normalized.contains('') || normalized.length != answers.length) {
        throw FormatException(
          'Duplicate or empty typed cue answers: ${entry.key}',
        );
      }
      cues[entry.key] = TypedItemCue(
        prompt: value['prompt'] as String,
        acceptedAnswers: List.unmodifiable(answers),
      );
    }
    final result = Map<String, TypedItemCue>.unmodifiable(cues);
    _cueCache[template] = result;
    return result;
  }

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    try {
      itemCuesOf(template);
      return const [];
    } on FormatException catch (error) {
      return [error.message];
    }
  }

  @override
  Future<bool> isEligible(
    GeneratorContext context,
    KnowledgeItem item,
    QuestionTemplate template,
  ) async {
    final cues = itemCuesOf(template);
    if (cues != null) return cues.containsKey(item.id);
    if (item.relationType != 'PRINCIPLE_EXPLANATION') return true;
    // Once a particular point has an authored cue, do not leave its broad
    // sibling-accepting typed question beside the corrected question.
    var cuedItems = _cuedItemCache[context];
    if (cuedItems == null) {
      final templates =
          await (context.db.select(context.db.questionTemplates)..where(
                (row) =>
                    row.mode.equals(id) &
                    row.relationType.equals(item.relationType),
              ))
              .get();
      cuedItems = {for (final row in templates) ...?itemCuesOf(row)?.keys};
      _cuedItemCache[context] = cuedItems;
    }
    return !cuedItems.contains(item.id);
  }

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
    final template = await (db.select(
      db.questionTemplates,
    )..where((row) => row.id.equals(questionTemplateId))).getSingle();
    final cues = itemCuesOf(template);
    final cue = cues?[itemId];
    if (cues != null && cue == null) {
      throw ArgumentError('No typed item cue for $itemId');
    }
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

    // Retain legal alternatives across periods (QF-8). Corrected physical
    // descriptions and dated ranks must not accept retired erroneous values.
    final forward = question.direction == 'forward';
    final (from, to, given) = forward
        ? ('subject_id', 'object_id', item.subjectId)
        : ('object_id', 'subject_id', item.objectId);
    final currentDescription = const {
      'HAS_BERRY_COLOUR',
      'TOP_PLANTED_GRAPE',
    }.contains(item.relationType);
    final on = isoDate(context.now.toLocal());
    final answers = await db
        .customSelect(
          '''
      SELECT n.id, n.name, n.name_norm FROM knowledge_relations r
      JOIN knowledge_nodes n ON n.id = r.$to
      WHERE r.$from = ?1 AND r.relation_type = ?2
      ${currentDescription ? 'AND r.valid_from <= ?3 AND (r.valid_until IS NULL OR r.valid_until > ?3)' : ''}
      ${cue != null ? 'AND n.id = ?${currentDescription ? 4 : 3}' : ''}''',
          variables: [
            Variable(given),
            Variable(item.relationType),
            if (currentDescription) Variable(on),
            if (cue != null) Variable(answerNode.id),
          ],
          readsFrom: {db.knowledgeRelations, db.knowledgeNodes},
        )
        .get();
    final names = {
      for (final row in answers)
        row.read<String>('id'): row.read<String>('name'),
    };
    final accepted = <String, String>{
      if (cue == null)
        for (final row in answers)
          coreOf(row.read<String>('name_norm')): row.read<String>('name'),
    };
    if (cue != null) {
      for (final answer in cue.acceptedAnswers) {
        accepted[coreOf(normalizeName(answer))] = answer;
      }
    }
    final answerTypes = {
      answerNode.nodeType,
      for (final signature in await (db.select(
        db.relationTypeSignatures,
      )..where((s) => s.relationType.equals(item.relationType))).get())
        forward ? signature.objectNodeType : signature.subjectNodeType,
    };
    final nodes = await db.select(db.knowledgeNodes).get();
    final nodeTypes = {for (final node in nodes) node.id: node.nodeType};
    final rivals = <String>{};
    final partialRivals = <String>{};
    for (final node in nodes) {
      if (cue != null || !names.containsKey(node.id)) {
        final name = coreOf(node.nameNorm);
        rivals.add(name);
        if (answerTypes.contains(node.nodeType)) partialRivals.add(name);
      }
    }
    for (final alternative in await db.select(db.nodeAlternativeNames).get()) {
      final name = coreOf(alternative.nameNorm);
      if (cue == null && names[alternative.knowledgeNodeId] != null) {
        final answer = names[alternative.knowledgeNodeId]!;
        accepted[name] = answer;
      } else {
        rivals.add(name);
        if (answerTypes.contains(nodeTypes[alternative.knowledgeNodeId])) {
          partialRivals.add(name);
        }
      }
    }
    rivals.removeAll(accepted.keys);
    partialRivals.removeAll(accepted.keys);
    return TypedQuestion(
      knowledgeItemId: question.knowledgeItemId,
      questionTemplateId: question.questionTemplateId,
      direction: question.direction,
      mode: question.mode,
      prompt: cue?.prompt ?? question.prompt,
      answer: cue == null
          ? question.answer
          : QuestionOption(answerNode.id, cue.acceptedAnswers.first),
      canonicalAnswer: cue == null ? null : question.answer.name,
      explanation: question.explanation,
      seed: seed,
      accepted: accepted,
      rivals: rivals,
      partialRivals: partialRivals,
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
    // no competing name of a type that can answer this relation. Lesson
    // sentences may mention the same word without naming another answer.
    if (text.replaceAll(' ', '').length >= 5 &&
        !(question.partialRivals ?? question.rivals).any(
          (rival) => _isPart(text, rival),
        )) {
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
