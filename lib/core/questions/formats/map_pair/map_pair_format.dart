import 'dart:convert';
import 'dart:math';

import 'package:fsrs/fsrs.dart' as fsrs;

import '../../../curriculum/knowledge_graph.dart';
import '../../../database/app_database.dart';
import '../../../geography/geometry_repository.dart';
import '../../../study/learner_profile.dart';
import '../../../study/study_planner.dart';
import '../../../time/utc_clock.dart';
import '../../exercise.dart';
import '../../exercise_format.dart';
import '../map/map_exercise.dart';

/// One independently graded location in a multi-place map question.
final class MapPlace {
  const MapPlace({
    required this.itemId,
    required this.nodeId,
    required this.name,
    required this.explanation,
  });

  final String itemId;
  final String nodeId;
  final String name;
  final String explanation;
}

final class MapPairExercise implements Exercise {
  const MapPairExercise({
    required this.map,
    required this.places,
    required this.prompt,
  });

  final MapExercise map;
  final List<MapPlace> places;

  @override
  final String prompt;
  @override
  String get formatId => 'map_pair';
  @override
  String get primaryItemId => map.primaryItemId;
  @override
  String get questionTemplateId => map.questionTemplateId;
  @override
  int get seed => map.seed;
  @override
  List<String> get itemIds => [for (final place in places) place.itemId];
}

/// Answers are associated with each requested place, so finding one place
/// never gives a successful review to a different place in the same card.
final class MapPairAnswer {
  MapPairAnswer(Map<String, MapLocateAnswer> selections)
    : selections = Map.unmodifiable(selections);

  final Map<String, MapLocateAnswer> selections;
}

/// Find two to four named places on a common frame, with one review per
/// location fact. The seed fixes both the co-items and the wording.
class MapPairFormat extends MapFormat {
  const MapPairFormat();

  @override
  String get id => 'map_pair';
  @override
  String get label => 'Find several places';
  @override
  int requiredDepth(String direction) => 1;
  @override
  int difficultyRank(String direction) => 8;

  static final _trackScopes =
      Expando<Future<List<Map<String, EffectiveMapping>>>>();

  static Future<List<Map<String, EffectiveMapping>>> _scopes(
    GeneratorContext context,
  ) => _trackScopes[context] ??= () async {
    final tracks = await (context.db.select(
      context.db.certifications,
    )..where((c) => c.isSelectable.equals(true))).get();
    final planner = StudyPlanner(context.db);
    return [
      for (final track in tracks) await planner.effectiveMappings(track.id),
    ];
  }();

  static ({int minimum, int maximum}) _limits(QuestionTemplate template) {
    final parameters = template.parameters == null
        ? <String, dynamic>{}
        : jsonDecode(template.parameters!) as Map<String, dynamic>;
    return (
      minimum: (parameters['min_places'] as int?) ?? 2,
      maximum: (parameters['max_places'] as int?) ?? 4,
    );
  }

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) {
    final problems = <String>[];
    if (template.relationType != 'LOCATED_IN' ||
        template.direction != 'forward') {
      problems.add('map_pair requires a forward LOCATED_IN template');
    }
    try {
      final limits = _limits(template);
      if (limits.minimum < 2 ||
          limits.maximum > 4 ||
          limits.minimum > limits.maximum) {
        problems.add(
          'map_pair min_places/max_places must satisfy 2 <= min <= max <= 4',
        );
      }
    } on Object {
      problems.add(
        'map_pair parameters must be a mapping with integer min_places/max_places',
      );
    }
    return problems;
  }

  static List<KnowledgeItem> _peers(
    List<KnowledgeItem> items,
    KnowledgeItem primary,
    MapFrame frame,
  ) {
    final candidates = {for (final candidate in frame.candidates) candidate.id};
    final seen = {primary.subjectId};
    return [
      for (final item in items)
        if (item.relationType == 'LOCATED_IN' &&
            candidates.contains(item.subjectId) &&
            seen.add(item.subjectId))
          item,
    ];
  }

  static List<KnowledgeItem> _mappedLocations(
    List<KnowledgeItem> items,
    Map<String, EffectiveMapping> scope,
  ) => [
    for (final item in items)
      if (item.relationType == 'LOCATED_IN' &&
          (scope[item.id]?.minimumDepth ?? 0) >= 1)
        item,
  ];

  static Future<MapFrame?> _locationFrame(
    AppDatabase db,
    KnowledgeItem primary,
    List<KnowledgeItem> locations,
    String on,
    int minimum,
  ) => GeometryRepository(db).frameOf(
    primary.subjectId,
    minimum: minimum,
    eligibleNodeIds: {for (final item in locations) item.subjectId},
    on: on,
  );

  static final _presentedLocations = Expando<Future<List<KnowledgeItem>>>();

  static Future<List<KnowledgeItem>> _locations(
    PresentationContext context,
    String on,
  ) => _presentedLocations[context] ??= () async {
    final current = await KnowledgeGraph(context.db).currentItems(on: on);
    if (context.allowedItemIds case final allowed?) {
      return [
        for (final item in current)
          if (item.relationType == 'LOCATED_IN' && allowed.contains(item.id))
            item,
      ];
    }
    final profile = await LearnerProfiles(context.db).current();
    if (profile == null) {
      return current.where((i) => i.relationType == 'LOCATED_IN').toList();
    }
    return _mappedLocations(
      current,
      await StudyPlanner(context.db)
          .effectiveMappings(profile.activeCertificationId),
    );
  }();

  @override
  Future<MapFrame?> frameFor(
    PresentationContext context, {
    required String itemId,
    required String nodeId,
    required String questionTemplateId,
    required String on,
  }) async {
    final primary = await (context.db.select(
      context.db.knowledgeItems,
    )..where((i) => i.id.equals(itemId))).getSingle();
    final locations = await _locations(context, on);
    if (!locations.any((i) => i.id == itemId)) return null;
    final template = await (context.db.select(
      context.db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    return _locationFrame(
      context.db,
      primary,
      locations,
      on,
      _limits(template).minimum,
    );
  }

  @override
  Future<bool> isEligible(
    GeneratorContext context,
    KnowledgeItem item,
    QuestionTemplate template,
  ) async {
    if (item.relationType != 'LOCATED_IN' || template.direction != 'forward') {
      return false;
    }
    final minimum = _limits(template).minimum;
    final needed = minimum - 1;
    // Ingestion is shared by all tracks. Generate a composite only when
    // every selectable track serving the primary can supply enough peers.
    var checkedTrack = false;
    for (final scope in await _scopes(context)) {
      if ((scope[item.id]?.minimumDepth ?? 0) < requiredDepth('forward')) {
        continue;
      }
      checkedTrack = true;
      final locations = _mappedLocations(context.items, scope);
      final frame = await _locationFrame(
        context.db,
        item,
        locations,
        context.today,
        minimum,
      );
      if (frame == null || _peers(locations, item, frame).length < needed) {
        return false;
      }
    }
    if (checkedTrack) return true;
    final locations = context.items
        .where((i) => i.relationType == 'LOCATED_IN')
        .toList();
    final frame = await _locationFrame(
      context.db,
      item,
      locations,
      context.today,
      minimum,
    );
    return frame != null && _peers(locations, item, frame).length >= needed;
  }

  @override
  Future<Exercise> present(
    PresentationContext context, {
    required String itemId,
    required String questionTemplateId,
    required int seed,
  }) async {
    final map = await super.present(
      context,
      itemId: itemId,
      questionTemplateId: questionTemplateId,
      seed: seed,
    ) as MapExercise;
    final db = context.db;
    final primary = await (db.select(
      db.knowledgeItems,
    )..where((i) => i.id.equals(itemId))).getSingle();
    final template = await (db.select(
      db.questionTemplates,
    )..where((t) => t.id.equals(questionTemplateId))).getSingle();
    final on = isoDate(context.now.toLocal());
    final others = _peers(await _locations(context, on), primary, map.frame);
    final limits = _limits(template);
    if (others.length < limits.minimum - 1) {
      throw StateError('$itemId has too few mapped co-items');
    }
    final random = Random(seed);
    others.shuffle(random);
    final maximum = min(limits.maximum, others.length + 1);
    final count = limits.minimum + random.nextInt(maximum - limits.minimum + 1);
    final chosen = [primary, ...others.take(count - 1)];
    final places = [
      for (final item in chosen)
        MapPlace(
          itemId: item.id,
          nodeId: item.subjectId,
          name: map.names[item.subjectId]!,
          explanation: item.assertionText,
        ),
    ];
    final names = [for (final place in places) place.name];
    final named = names.length == 2
        ? '${names.first} and ${names.last}'
        : '${names.take(names.length - 1).join(', ')} and ${names.last}';
    final prompt = switch (random.nextInt(3)) {
      0 => 'Where are $named? Select a location for each place.',
      1 => 'Find $named on this map.',
      _ => 'Locate each of these places: $named.',
    };
    return MapPairExercise(map: map, places: places, prompt: prompt);
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    final pair = exercise as MapPairExercise;
    if (answer is! MapPairAnswer) {
      throw ArgumentError.value(
        answer,
        'answer',
        'is not a multi-place map answer',
      );
    }
    if (answer.selections.keys.any((item) => !pair.itemIds.contains(item))) {
      throw ArgumentError.value(answer, 'answer', 'contains an unasked item');
    }
    for (final selection in answer.selections.values) {
      if (selection.nodeId != null &&
          !pair.map.candidateIds.contains(selection.nodeId)) {
        throw ArgumentError.value(
          selection.nodeId,
          'answer',
          'is not a map candidate',
        );
      }
    }
    return [
      for (final place in pair.places)
        ItemGrade(
          place.itemId,
          answer.selections[place.itemId]?.nodeId == place.nodeId
              ? fsrs.Rating.good
              : fsrs.Rating.again,
          optionNodeIds: pair.map.frame.candidates.map((c) => c.id).toList(),
          selectedNodeId: answer.selections[place.itemId]?.nodeId,
          payload: {
            ...?answer.selections[place.itemId]?.payload(pair.map),
            'target': place.nodeId,
            'requested_nodes': [
              for (final requested in pair.places) requested.nodeId,
            ],
            'selections': {
              for (final entry in answer.selections.entries)
                entry.key: entry.value.payload(pair.map),
            },
          },
        ),
    ];
  }
}
