import 'package:fsrs/fsrs.dart' as fsrs;

/// One presentation of a format (question-system §1). A single-item
/// exercise practises its primary item; a composite exercise also practises
/// co-items drawn from a pool.
abstract interface class Exercise {
  /// The format: the template's `mode`.
  String get formatId;

  /// The item the session planned.
  String get primaryItemId;

  /// Every item the exercise practises, the primary first, each once.
  List<String> get itemIds;

  String get questionTemplateId;

  String get prompt;

  /// The seed that fixed the presentation (QG-7).
  int get seed;
}

/// The grade one item earned in an exercise (question-system §4).
class ItemGrade {
  const ItemGrade(
    this.itemId,
    this.rating, {
    this.optionNodeIds = const [],
    this.selectedNodeId,
    this.payload,
  });

  final String itemId;
  final fsrs.Rating rating;

  /// The options shown, in display order, when the format shows options.
  final List<String> optionNodeIds;

  /// The option the learner chose, when it is a node.
  final String? selectedNodeId;

  /// The learner's answer as the format records it, encodable as JSON: the
  /// order given, the number typed (`answer_payload`, QF-3).
  final Object? payload;

  @override
  String toString() => '$itemId: ${rating.name}';
}
