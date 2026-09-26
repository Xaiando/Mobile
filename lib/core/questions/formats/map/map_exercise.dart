import 'dart:math';

import 'package:drift/drift.dart';

import '../../../database/app_database.dart';
import '../../../geography/coordinates.dart';
import '../../../geography/geometry_repository.dart';
import '../../../geography/hit_test.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../../question_presenter.dart';

/// How much a map question shows (geography §4, GEO-8).
enum MapMode {
  /// Every candidate is outlined and named: recognition.
  labelled,

  /// Candidates are outlined but unnamed.
  outline,

  /// Only the coastline, borders and major rivers; candidates appear after
  /// the answer.
  minimal,

  /// Minimal, starting one level up: the learner zooms to find the answer.
  blank,
}

/// The mode for an item's memory, until the presentation ladder (F4)
/// chooses: labelled while the item is new or on a step, then outline,
/// minimal and blank as its stability passes 7 and 30 days (GEO-8, the
/// bands of question-system §5).
MapMode mapModeFor(ReviewState? state) {
  if (state == null || state.step != null) return MapMode.labelled;
  if (state.stability < 7) return MapMode.outline;
  if (state.stability < 30) return MapMode.minimal;
  return MapMode.blank;
}

/// A map question (backlog G4): an area to find or to name, on the frame of
/// geography §5. It practises the area's location item (GEO-1, GEO-6).
final class MapExercise implements Exercise {
  const MapExercise({
    required this.formatId,
    required this.primaryItemId,
    required this.questionTemplateId,
    required this.prompt,
    required this.seed,
    required this.nodeId,
    required this.nodeName,
    required this.explanation,
    required this.frame,
    required this.zoomedOut,
    required this.mode,
    required this.names,
    this.options = const [],
    this._correct,
  });

  @override
  final String formatId;
  @override
  final String primaryItemId;
  @override
  final String questionTemplateId;
  @override
  final String prompt;
  @override
  final int seed;

  /// The area asked about: the location item's subject.
  final String nodeId;
  final String nodeName;

  /// The item's assertion, shown after answering.
  final String explanation;

  final MapFrame frame;

  /// Where the blank mode starts: the frame one level up, if there is one.
  final GeoBox? zoomedOut;

  final MapMode mode;

  /// The candidates' names, by node ID, which is also the feature key.
  final Map<String, String> names;

  /// The names offered by `map_identify`, in display order; empty for
  /// `map_locate`.
  final List<QuestionOption> options;

  @override
  List<String> get itemIds => [primaryItemId];

  final Set<String>? _correct;

  /// Every node that answers the question: any correct node counts
  /// (question-system §6). A location item's is its area alone.
  Set<String> get correctNodeIds => _correct ?? {nodeId};

  /// This exercise shown in [mode] instead.
  MapExercise inMode(MapMode mode) => MapExercise(
    formatId: formatId,
    primaryItemId: primaryItemId,
    questionTemplateId: questionTemplateId,
    prompt: prompt,
    seed: seed,
    nodeId: nodeId,
    nodeName: nodeName,
    explanation: explanation,
    frame: frame,
    zoomedOut: zoomedOut,
    mode: mode,
    names: names,
    options: options,
    correct: _correct,
  );

  Set<String> get candidateIds => {for (final c in frame.candidates) c.id};
}

/// A `map_locate` answer: the area tapped, where, and how the map was shown;
/// or a name chosen in the accessible list (GEO-13).
final class MapLocateAnswer {
  const MapLocateAnswer({
    this.nodeId,
    this.position,
    this.zoom,
    this.view,
    this.fromList = false,
  });

  /// A tap, hit-tested against the candidates (geography §4).
  MapLocateAnswer.fromTap(MapTap tap)
    : this(
        nodeId: tap.hit?.key,
        position: tap.position,
        zoom: tap.zoom,
        view: tap.visibleBounds,
      );

  /// A name chosen in the list instead of a tap.
  const MapLocateAnswer.fromList(String nodeId)
    : this(nodeId: nodeId, fromList: true);

  /// The candidate hit, or null for a tap outside every one.
  final String? nodeId;
  final LonLat? position;
  final double? zoom;
  final GeoBounds? view;
  final bool fromList;

  /// What `answer_payload` logs, so a later miss can say what was tapped
  /// (geography §4).
  Map<String, Object?> payload(MapExercise exercise) => {
    'node': nodeId,
    if (position case final p?) 'tap': [p.lon, p.lat],
    'zoom': ?zoom,
    if (view case final v?) 'view': [v.minLon, v.minLat, v.maxLon, v.maxLat],
    'frame': exercise.frame.parent.id,
    'mode': exercise.mode.name,
    if (fromList) 'list': true,
  };
}

/// What both map formats share: eligibility, and a presentation from the
/// question's row, the area's frame and the item's memory.
abstract class MapFormat extends ExerciseFormat {
  const MapFormat();

  @override
  FormatFamily get family => FormatFamily.spatial;

  @override
  bool get isObjective => true;

  /// A map question asks where an area lies: forward, about a drawn area
  /// that a frame holds with enough candidates (geography §5).
  @override
  Future<bool> isEligible(
    GeneratorContext context,
    KnowledgeItem item,
    QuestionTemplate template,
  ) async =>
      template.direction == 'forward' &&
      await GeometryRepository(context.db)
              .frameOf(item.subjectId, on: context.today) !=
          null;

  /// The mode of this format for [mode], the one the item's memory calls
  /// for.
  MapMode modeFor(MapMode mode) => mode;

  /// The names this format offers, in display order; none by default.
  List<QuestionOption> optionsFor(
    QuestionOption answer,
    List<QuestionOption> candidates,
    Random random,
  ) => const [];

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final db = context.db;
    final row = await db
        .customSelect(
          '''
      SELECT q.prompt_text, i.subject_id, i.assertion_text, n.name
      FROM questions q
      JOIN knowledge_items i ON i.id = q.knowledge_item_id
      JOIN knowledge_nodes n ON n.id = i.subject_id
      WHERE q.knowledge_item_id = ?1 AND q.question_template_id = ?2''',
          variables: [Variable(itemId), Variable(questionTemplateId)],
          readsFrom: {db.questions, db.knowledgeItems, db.knowledgeNodes},
        )
        .getSingle();
    final nodeId = row.read<String>('subject_id');
    final maps = GeometryRepository(db);
    final frame = await maps.frameOf(nodeId);
    if (frame == null) {
      throw StateError('$nodeId has no map frame');
    }
    final zoomedOut = await maps.frameOf(frame.parent.id);
    final state = await (db.select(
      db.reviewStates,
    )..where((s) => s.knowledgeItemId.equals(itemId))).getSingleOrNull();
    final names = {for (final c in frame.candidates) c.id: c.node.name};
    final answer = QuestionOption(nodeId, row.read<String>('name'));
    return MapExercise(
      formatId: id,
      primaryItemId: itemId,
      questionTemplateId: questionTemplateId,
      prompt: row.read<String>('prompt_text'),
      seed: seed,
      nodeId: nodeId,
      nodeName: answer.name,
      explanation: row.read<String>('assertion_text'),
      frame: frame,
      zoomedOut: zoomedOut?.box,
      mode: modeFor(mapModeFor(state)),
      names: names,
      options: optionsFor(answer, [
        for (final MapEntry(:key, :value) in names.entries)
          QuestionOption(key, value),
      ], Random(seed)),
    );
  }
}
