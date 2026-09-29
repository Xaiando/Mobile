import 'dart:convert';
import 'dart:math';

import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/name_normalizer.dart';
import '../../../database/app_database.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// One question written for one cited knowledge item. These are literal
/// answer phrases, not knowledge nodes or automatically inferred distractors.
final class AuthoredChoiceCue {
  const AuthoredChoiceCue({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.sourceCitationId,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String sourceCitationId;
}

final class AuthoredChoiceQuestion extends PresentedQuestion {
  const AuthoredChoiceQuestion({
    required super.knowledgeItemId,
    required super.questionTemplateId,
    required super.direction,
    required super.mode,
    required super.prompt,
    required super.answer,
    required super.options,
    required super.explanation,
    required super.seed,
    required this.sourceCitationId,
  });

  final String sourceCitationId;
}

/// Four explicitly authored alternatives for one particular fact. This is
/// separate from `mcq`: the latter selects graph-node distractors and must
/// still respect `mcq_disabled` on ambiguous principle statements.
class AuthoredChoiceFormat extends ExerciseFormat {
  const AuthoredChoiceFormat();

  static const formatId = 'authored_choice';
  static final _cueCache = Expando<Map<String, AuthoredChoiceCue>>(
    'authored choice cues',
  );

  static Map<String, AuthoredChoiceCue> itemChoicesOf(
    QuestionTemplate template,
  ) {
    if (_cueCache[template] case final cached?) return cached;
    if (template.direction != 'forward') {
      throw const FormatException('authored_choice needs a forward template');
    }
    if (template.parameters == null) {
      throw const FormatException('authored_choice needs item_choices');
    }
    final raw = jsonDecode(template.parameters!);
    if (raw is! Map<String, dynamic> ||
        raw.length != 1 ||
        raw['item_choices'] is! Map<String, dynamic>) {
      throw const FormatException('parameters must contain only item_choices');
    }
    final entries = raw['item_choices'] as Map<String, dynamic>;
    if (entries.isEmpty) {
      throw const FormatException('item_choices must name at least one item');
    }
    final cues = <String, AuthoredChoiceCue>{};
    for (final entry in entries.entries) {
      final value = entry.value;
      if (!RegExp(r'^ki_[a-z0-9_]+$').hasMatch(entry.key) ||
          value is! Map<String, dynamic> ||
          value.keys.toSet().difference(const {
            'prompt',
            'options',
            'correctIndex',
            'explanation',
            'sourceCitationId',
          }).isNotEmpty ||
          value['prompt'] is! String ||
          (value['prompt'] as String).trim().isEmpty ||
          value['explanation'] is! String ||
          (value['explanation'] as String).trim().isEmpty ||
          value['sourceCitationId'] is! String ||
          !RegExp(r'^src_[a-z0-9_]+$')
              .hasMatch(value['sourceCitationId'] as String) ||
          value['options'] is! List ||
          (value['options'] as List).length != 4 ||
          value['correctIndex'] is! int ||
          (value['correctIndex'] as int) < 0 ||
          (value['correctIndex'] as int) > 3) {
        throw FormatException('Invalid authored choice for ${entry.key}');
      }
      final options = value['options'] as List;
      if (options.any((option) => option is! String || option.trim().isEmpty)) {
        throw FormatException('Invalid authored options for ${entry.key}');
      }
      final literalOptions = options.cast<String>();
      final distinct = literalOptions.map(normalizeName).toSet();
      if (distinct.length != 4) {
        throw FormatException('Duplicate authored options for ${entry.key}');
      }
      cues[entry.key] = AuthoredChoiceCue(
        prompt: value['prompt'] as String,
        options: List.unmodifiable(literalOptions),
        correctIndex: value['correctIndex'] as int,
        explanation: value['explanation'] as String,
        sourceCitationId: value['sourceCitationId'] as String,
      );
    }
    final result = Map<String, AuthoredChoiceCue>.unmodifiable(cues);
    _cueCache[template] = result;
    return result;
  }

  @override
  String get id => formatId;

  @override
  String get label => 'Authored choice';

  @override
  FormatFamily get family => FormatFamily.recognition;

  @override
  bool get isObjective => true;

  @override
  int requiredDepth(String direction) => 1;

  @override
  int difficultyRank(String direction) => 0;

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    try {
      itemChoicesOf(template);
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
  ) async => itemChoicesOf(template).containsKey(item.id);

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final template = await (context.db.select(
      context.db.questionTemplates,
    )..where((row) => row.id.equals(questionTemplateId))).getSingle();
    final cue = itemChoicesOf(template)[itemId];
    if (cue == null) {
      throw ArgumentError('No authored choice for $itemId');
    }
    // Require an actual generated question so a retired or unmapped cue
    // cannot bypass the normal current-item generation gate.
    final base = await QuestionPresenter(context.db)
        .present(itemId, questionTemplateId, seed: seed);
    // These keys are ephemeral positions, deliberately not knowledge-node
    // IDs. grade() logs the literal choices only in answer_payload.
    String key(int index) => 'literal_${questionTemplateId}_${itemId}_$index';
    final options = [
      for (var i = 0; i < cue.options.length; i++)
        QuestionOption(key(i), cue.options[i]),
    ]..shuffle(Random(seed));
    return AuthoredChoiceQuestion(
      knowledgeItemId: base.knowledgeItemId,
      questionTemplateId: base.questionTemplateId,
      direction: base.direction,
      mode: id,
      prompt: cue.prompt,
      answer: options.singleWhere(
        (option) => option.nodeId == key(cue.correctIndex),
      ),
      options: options,
      explanation: cue.explanation,
      seed: seed,
      sourceCitationId: cue.sourceCitationId,
    );
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (exercise is! AuthoredChoiceQuestion || exercise.mode != id) {
      throw ArgumentError.value(exercise, 'exercise', 'is not authored choice');
    }
    if (answer is! QuestionOption) {
      throw ArgumentError.value(answer, 'answer', 'is not an option shown');
    }
    final selected = exercise.options.indexOf(answer);
    if (selected < 0 || exercise.options[selected].name != answer.name) {
      throw ArgumentError.value(answer, 'answer', 'is not an option shown');
    }
    return [
      ItemGrade(
        exercise.knowledgeItemId,
        answer == exercise.answer ? fsrs.Rating.good : fsrs.Rating.again,
        payload: {
          'format': id,
          'prompt': exercise.prompt,
          'options': [for (final option in exercise.options) option.name],
          'selectedIndex': selected,
          'correctIndex': exercise.correctIndex,
          'explanation': exercise.explanation,
          'sourceCitationId': exercise.sourceCitationId,
        },
      ),
    ];
  }
}
