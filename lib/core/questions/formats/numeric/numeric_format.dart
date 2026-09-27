import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/curriculum_validator.dart'
    show regulatoryRelationTypes;
import '../../../database/app_database.dart';
import '../../../settings/user_settings.dart';
import '../../../time/utc_clock.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';
import 'numeric_answer.dart';
import 'numeric_question.dart';

export 'numeric_answer.dart';
export 'numeric_question.dart';

enum NumericOutcome { exact, near, wrong }

final class _NumericParameters {
  const _NumericParameters(this.exact, this.outer, this.scope);
  final double exact;
  final double outer;
  final Set<String>? scope;
}

/// Objective single-item quantity practice (Q4). No format-specific memory
/// state or tolerance is inferred from a node name or its assertion text.
class NumericFormat extends ExerciseFormat {
  const NumericFormat();

  @override
  String get id => 'numeric';
  @override
  String get label => 'Number or range';
  @override
  FormatFamily get family => FormatFamily.structured;
  @override
  bool get isObjective => true;
  @override
  int requiredDepth(String direction) => 2;
  @override
  int difficultyRank(String direction) => 7;

  static _NumericParameters _parameters(QuestionTemplate template) {
    final decoded = template.parameters == null
        ? <String, dynamic>{}
        : jsonDecode(template.parameters!);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('numeric parameters must be an object');
    }
    final unknown = decoded.keys.where(
      (key) => !const {
        'exact_tolerance',
        'tolerance',
        'scope_node_ids',
      }.contains(key),
    );
    if (unknown.isNotEmpty) {
      throw FormatException(
        'unknown numeric parameters: ${unknown.join(', ')}',
      );
    }
    double width(String key) {
      if (!decoded.containsKey(key)) {
        return 0;
      }
      final value = decoded[key];
      if (value is! num || !value.toDouble().isFinite || value < 0) {
        throw FormatException('$key must be a finite nonnegative number');
      }
      return value.toDouble();
    }

    final exact = width('exact_tolerance');
    final outer = width('tolerance');
    if (outer < exact) {
      throw const FormatException(
        'tolerance is the total outer width and must be >= exact_tolerance',
      );
    }
    if (regulatoryRelationTypes.contains(template.relationType) &&
        (exact != 0 || outer != 0)) {
      throw const FormatException('regulatory numeric tolerances must be zero');
    }
    Set<String>? scope;
    if (decoded.containsKey('scope_node_ids')) {
      final values = decoded['scope_node_ids'];
      if (values is! List ||
          values.isEmpty ||
          values.any(
            (value) =>
                value is! String ||
                value.trim().isEmpty ||
                value.trim() != value,
          )) {
        throw const FormatException(
          'scope_node_ids must be a nonempty list of node IDs',
        );
      }
      scope = values.cast<String>().toSet();
      if (scope.length != values.length) {
        throw const FormatException('scope_node_ids must not repeat an ID');
      }
    }
    return _NumericParameters(exact, outer, scope);
  }

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    final problems = <String>[];
    if (template.mode != id || template.direction != 'forward') {
      problems.add('numeric requires a forward numeric template');
    }
    if (!relationTypes.contains(template.relationType)) {
      problems.add('numeric template references an unknown relation type');
    }
    try {
      _parameters(template);
    } on FormatException catch (error) {
      problems.add(error.message);
    }
    return problems;
  }

  static bool _nodeCurrent(KnowledgeNode node, String on) =>
      (node.validFrom == null || node.validFrom!.compareTo(on) <= 0) &&
      (node.validUntil == null || node.validUntil!.compareTo(on) > 0);

  /// A unique current target is required. Competing current objects cannot be
  /// treated as wrong or silently replaced by whichever item was scheduled.
  static Future<({QuantityValue quantity, _NumericParameters parameters})?>
  _metadata(
    AppDatabase db,
    KnowledgeItem item,
    QuestionTemplate template,
    String on,
  ) async {
    if (template.relationType != item.relationType ||
        item.supersededByItemId != null ||
        (const NumericFormat())
            .templateProblems(template, relationTypes: {item.relationType})
            .isNotEmpty) {
      return null;
    }
    final parameters = _parameters(template);
    if (parameters.scope != null &&
        !parameters.scope!.contains(item.subjectId)) {
      return null;
    }
    final nodes = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.isIn([item.subjectId, item.objectId]))).get();
    final byId = {for (final node in nodes) node.id: node};
    final subject = byId[item.subjectId];
    final object = byId[item.objectId];
    if (subject == null ||
        object == null ||
        object.nodeType != 'quantity' ||
        !_nodeCurrent(subject, on) ||
        !_nodeCurrent(object, on)) {
      return null;
    }
    final quantity = await (db.select(
      db.quantityValues,
    )..where((q) => q.knowledgeNodeId.equals(item.objectId))).getSingleOrNull();
    if (quantity == null ||
        quantity.nodeType != 'quantity' ||
        !quantity.minimum.isFinite ||
        (quantity.maximum != null &&
            (!quantity.maximum!.isFinite ||
                quantity.maximum! < quantity.minimum)) ||
        canonicalUnitOf(quantity.unit).isEmpty) {
      return null;
    }
    final maximum = quantity.maximum ?? quantity.minimum;
    try {
      final lower = numericOffset(quantity.minimum, -parameters.outer);
      final upper = numericOffset(maximum, parameters.outer);
      if (const {'°C', '°F'}.contains(canonicalUnitOf(quantity.unit))) {
        for (final unit in const ['°C', '°F']) {
          numericValueInUnit(lower, fromUnit: quantity.unit, toUnit: unit);
          numericValueInUnit(upper, fromUnit: quantity.unit, toUnit: unit);
        }
      }
    } on ArgumentError {
      return null;
    }
    final targets = await db
        .customSelect(
          '''
      SELECT DISTINCT r.object_id,
        EXISTS (SELECT 1 FROM knowledge_items i
          WHERE i.id = ?4 AND i.subject_id = r.subject_id
            AND i.relation_type = r.relation_type AND i.object_id = r.object_id
            AND i.superseded_by_item_id IS NULL) AS scheduled
      FROM knowledge_relations r
      JOIN knowledge_nodes n ON n.id = r.object_id
      WHERE r.subject_id = ?1 AND r.relation_type = ?2
        AND r.valid_from <= ?3
        AND (r.valid_until IS NULL OR r.valid_until > ?3)
        AND (n.valid_from IS NULL OR n.valid_from <= ?3)
        AND (n.valid_until IS NULL OR n.valid_until > ?3)
      ''',
          variables: [
            Variable(item.subjectId),
            Variable(item.relationType),
            Variable(on),
            Variable(item.id),
          ],
          readsFrom: {
            db.knowledgeItems,
            db.knowledgeRelations,
            db.knowledgeNodes,
          },
        )
        .get();
    if (!targets.any(
          (row) =>
              row.read<int>('scheduled') == 1 &&
              row.read<String>('object_id') == item.objectId,
        ) ||
        targets.map((row) => row.read<String>('object_id')).toSet().length !=
            1) {
      return null;
    }
    return (quantity: quantity, parameters: parameters);
  }

  @override
  Future<bool> isEligible(
    GeneratorContext context,
    KnowledgeItem item,
    QuestionTemplate template,
  ) async => await _metadata(context.db, item, template, context.today) != null;

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final db = context.db;
    final item = await (db.select(
      db.knowledgeItems,
    )..where((i) => i.id.equals(itemId))).getSingleOrNull();
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingleOrNull();
    if (item == null || template == null) {
      throw ArgumentError('Unknown numeric item or template');
    }
    final metadata = await _metadata(
      db,
      item,
      template,
      isoDate(context.now.toLocal()),
    );
    if (metadata == null) {
      throw StateError('The item/template is not a current numeric question');
    }
    final question = await QuestionPresenter(db)
        .present(itemId, questionTemplateId, seed: seed);
    final quantity = metadata.quantity;
    final unit = canonicalUnitOf(quantity.unit);
    final preference = (await LearnerSettings(db).current()).temperatureUnit;
    final displayUnit = const {'°C', '°F'}.contains(unit)
        ? (preference == TemperatureUnit.celsius ? '°C' : '°F')
        : unit;
    final minimum = quantity.minimum;
    final maximum = quantity.maximum ?? minimum;
    final legalMinimum = const {
      'MIN_AGEING',
      'MIN_WOOD_AGEING',
    }.contains(item.relationType);
    final low = numericValueInUnit(
      minimum,
      fromUnit: unit,
      toUnit: displayUnit,
    );
    final high = numericValueInUnit(
      legalMinimum ? minimum : maximum,
      fromUnit: unit,
      toUnit: displayUnit,
    );
    final lowText = formatNumericValue(low);
    final highText = formatNumericValue(high);
    final answerName =
        '${low == high ? lowText : '$lowText–$highText'} $displayUnit';
    return NumericQuestion(
      knowledgeItemId: question.knowledgeItemId,
      questionTemplateId: question.questionTemplateId,
      prompt: question.prompt,
      answer: QuestionOption(question.answer.nodeId, answerName),
      explanation: question.explanation,
      seed: seed,
      relationType: item.relationType,
      canonicalMinimum: minimum,
      canonicalMaximum: maximum,
      canonicalUnit: unit,
      displayUnit: displayUnit,
      exactTolerance: metadata.parameters.exact,
      tolerance: metadata.parameters.outer,
    );
  }

  static bool _validQuestion(NumericQuestion question) {
    if (!question.canonicalMinimum.isFinite ||
        !question.canonicalMaximum.isFinite ||
        question.canonicalMaximum < question.canonicalMinimum ||
        canonicalUnitOf(question.canonicalUnit).isEmpty ||
        canonicalUnitOf(question.displayUnit).isEmpty ||
        question.relationType.isEmpty ||
        !question.exactTolerance.isFinite ||
        !question.tolerance.isFinite ||
        question.exactTolerance < 0 ||
        question.tolerance < question.exactTolerance ||
        (question.isRegulatory &&
            (question.exactTolerance != 0 || question.tolerance != 0))) {
      return false;
    }
    try {
      final lower = numericOffset(
        question.canonicalMinimum,
        -question.tolerance,
      );
      final upper = numericOffset(
        question.canonicalMaximum,
        question.tolerance,
      );
      numericValueInUnit(
        lower,
        fromUnit: question.canonicalUnit,
        toUnit: question.displayUnit,
      );
      numericValueInUnit(
        upper,
        fromUnit: question.canonicalUnit,
        toUnit: question.displayUnit,
      );
      return question.displayMinimum.isFinite &&
          question.displayMaximum.isFinite;
    } on ArgumentError {
      return false;
    }
  }

  static NumericAnswer? _answer(NumericQuestion question, Object answer) {
    if (answer is NumericAnswer) {
      return answer;
    }
    if (answer is String) {
      return NumericAnswer.tryParse(answer, defaultUnit: question.displayUnit);
    }
    throw ArgumentError.value(answer, 'answer', 'is not a numeric answer');
  }

  /// Boundaries are transformed into the submitted supported unit; the input
  /// is never round-tripped to decide a grade. No grading epsilon is applied.
  static NumericOutcome outcome(NumericQuestion question, Object answer) {
    final parsed = _answer(question, answer);
    if (!_validQuestion(question) ||
        parsed == null ||
        !parsed.isValid ||
        (parsed.isInterval && !question.allowsInterval)) {
      return NumericOutcome.wrong;
    }
    try {
      double inAnswerUnit(double value) => numericValueInUnit(
        value,
        fromUnit: question.canonicalUnit,
        toUnit: parsed.unit,
      );
      if (question.isLegalMinimum) {
        return parsed.minimum == inAnswerUnit(question.canonicalMinimum)
            ? NumericOutcome.exact
            : NumericOutcome.wrong;
      }
      final upper = parsed.maximum ?? parsed.minimum;
      bool within(double width) =>
          parsed.minimum >=
              inAnswerUnit(numericOffset(question.canonicalMinimum, -width)) &&
          upper <=
              inAnswerUnit(numericOffset(question.canonicalMaximum, width));
      if (within(question.exactTolerance)) {
        return NumericOutcome.exact;
      }
      if (within(question.tolerance)) {
        return NumericOutcome.near;
      }
      return NumericOutcome.wrong;
    } on ArgumentError {
      return NumericOutcome.wrong;
    }
  }

  static Map<String, Object?>? _inUnit(NumericAnswer? answer, String unit) {
    if (answer == null || !answer.isValid) {
      return null;
    }
    try {
      final minimum = numericValueInUnit(
        answer.minimum,
        fromUnit: answer.unit,
        toUnit: unit,
      );
      final maximum = answer.maximum == null
          ? null
          : numericValueInUnit(
              answer.maximum!,
              fromUnit: answer.unit,
              toUnit: unit,
            );
      return {
        'minimum': minimum,
        'maximum': maximum,
        'unit': unit,
        'is_interval': answer.isInterval,
      };
    } on ArgumentError {
      return null;
    }
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    if (exercise is! NumericQuestion) {
      throw ArgumentError.value(exercise, 'exercise', 'is not numeric');
    }
    final result = outcome(exercise, answer);
    final parsed = _answer(exercise, answer);
    double? finite(double value) => value.isFinite ? value : null;
    double? display(bool upper) {
      try {
        return finite(
          upper ? exercise.displayMaximum : exercise.displayMinimum,
        );
      } on ArgumentError {
        return null;
      }
    }

    return [
      ItemGrade(
        exercise.knowledgeItemId,
        switch (result) {
          NumericOutcome.exact => fsrs.Rating.good,
          NumericOutcome.near => fsrs.Rating.hard,
          NumericOutcome.wrong => fsrs.Rating.again,
        },
        payload: {
          'raw': answer is String ? answer : null,
          'submitted': parsed?.toJson(),
          'canonical_answer': _inUnit(parsed, exercise.canonicalUnit),
          'display_answer': _inUnit(parsed, exercise.displayUnit),
          'quantity': {
            'canonical': {
              'minimum': finite(exercise.canonicalMinimum),
              'maximum': finite(exercise.canonicalMaximum),
              'unit': exercise.canonicalUnit,
            },
            'display': {
              'minimum': display(false),
              'maximum': display(true),
              'unit': exercise.displayUnit,
            },
            'exact_tolerance': finite(exercise.exactTolerance),
            'tolerance': finite(exercise.tolerance),
            'is_legal_minimum': exercise.isLegalMinimum,
          },
          'outcome': result.name,
          'valid_metadata': _validQuestion(exercise),
          'seed': exercise.seed,
        },
      ),
    ];
  }
}
