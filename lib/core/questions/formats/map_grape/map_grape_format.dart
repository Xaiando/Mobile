import 'dart:math';

import 'package:drift/drift.dart';
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
import '../map_locate/map_locate_format.dart';

/// A grape-to-geography question based on a cited complete legal union or
/// a bounded, dated planting ranking. The two kinds never share candidates
/// or bonus reviews. Every represented answer in the frame is accepted.
class MapGrapeFormat extends MapLocateFormat {
  const MapGrapeFormat();

  static const permissionRelations = {
    'PERMITS_GRAPE',
    'PERMITS_PRINCIPAL_GRAPE',
    'PERMITS_ACCESSORY_GRAPE',
  };
  static const plantingRelation = 'TOP_PLANTED_GRAPE';
  static const grapeRelations = {...permissionRelations, plantingRelation};

  static Set<String> _family(String relationType) =>
      relationType == plantingRelation
      ? {plantingRelation}
      : permissionRelations;

  /// Dated vineyard statistics keep their survey year in a distinct subject
  /// (EU-2). A map uses the subject's structural area link, never gives the
  /// statistic itself invented geometry, and never mixes survey cohorts.
  static Future<Map<String, String>> _plantingAreas(
    AppDatabase db,
    String subjectId,
    String on,
  ) async {
    final nodes = {
      for (final node in await db.select(db.knowledgeNodes).get())
        node.id: node,
    };
    String yearOf(String id) {
      final years = RegExp(r'\b(?:19|20)\d{2}\b')
          .allMatches(nodes[id]?.name ?? '')
          .map((m) => m.group(0)!)
          .toSet();
      if (years.length != 1) {
        throw StateError('$id must name one planting-record year');
      }
      return years.single;
    }

    final assertions =
        await (db.select(db.relationSetAssertions)..where(
              (a) =>
                  a.relationType.equals(plantingRelation) &
                  a.direction.equals('forward') &
                  a.memberNodeType.equals('grape') &
                  a.validFrom.isSmallerOrEqualValue(on) &
                  (a.validUntil.isNull() | a.validUntil.isBiggerThanValue(on)),
            ))
            .get();
    final own = assertions.where((a) => a.nodeId == subjectId).firstOrNull;
    if (own == null) return {};
    final year = yearOf(subjectId);
    final cohort = {
      for (final assertion in assertions)
        if (assertion.sourceCitationId == own.sourceCitationId &&
            yearOf(assertion.nodeId) == year)
          assertion.nodeId,
    };
    final links =
        await (db.select(db.knowledgeRelations)..where(
              (r) =>
                  r.subjectId.isIn(cohort) &
                  r.relationType.equals('STATISTIC_IN_AREA') &
                  r.validFrom.isSmallerOrEqualValue(on) &
                  (r.validUntil.isNull() | r.validUntil.isBiggerThanValue(on)),
            ))
            .get();
    return {for (final link in links) link.subjectId: link.objectId};
  }

  @override
  String get id => 'map_grape';
  @override
  String get label => 'Grapes on the map';
  @override
  int requiredDepth(String direction) => 2;
  @override
  int difficultyRank(String direction) => 9;

  @override
  List<String> templateProblems(
    QuestionTemplate template, {
    required Set<String> relationTypes,
  }) => [
    if (!grapeRelations.contains(template.relationType) ||
        template.direction != 'forward')
      'map_grape requires a forward grape-permission or planting template',
    if (template.parameters != null && template.parameters != '{}')
      'map_grape does not take parameters',
  ];

  @override
  Future<bool> isEligible(
    GeneratorContext context,
    KnowledgeItem item,
    QuestionTemplate template,
  ) async =>
      grapeRelations.contains(item.relationType) &&
      template.direction == 'forward' &&
      await _knownFrame(
            context.db,
            item.subjectId,
            context.today,
            item.relationType,
          ) !=
          null;

  /// Selectable places require completeness for the exact clue family:
  /// the legal union, or the bounded planting ranking. Positive cultivation
  /// facts never establish legal prohibition or the absence of a planting.
  static Future<MapFrame?> _knownFrame(
    AppDatabase db,
    String subjectId,
    String on,
    String relationType,
  ) async {
    if (relationType == plantingRelation) {
      final areas = await _plantingAreas(db, subjectId, on);
      final area = areas[subjectId];
      if (area == null) return null;
      return GeometryRepository(db)
          .frameOf(area, eligibleNodeIds: areas.values.toSet(), on: on);
    }
    final assertions =
        await (db.select(db.relationSetAssertions)..where(
              (a) =>
                  a.relationType.equals('PERMITS_GRAPE') &
                  a.direction.equals('forward') &
                  a.memberNodeType.equals('grape') &
                  a.validFrom.isSmallerOrEqualValue(on) &
                  (a.validUntil.isNull() | a.validUntil.isBiggerThanValue(on)),
            ))
            .get();
    final complete = {for (final assertion in assertions) assertion.nodeId};
    if (!complete.contains(subjectId)) return null;
    final maps = GeometryRepository(db);
    // Prefer enough alternatives to avoid a tiny frame consisting only of
    // closely related appellations that permit the same grape.
    return await maps.frameOf(subjectId, eligibleNodeIds: complete, on: on) ??
        await maps.frameOf(
          subjectId,
          minimum: 2,
          eligibleNodeIds: complete,
          on: on,
        );
  }

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
    )..where((i) => i.id.equals(itemId))).getSingle();
    final on = isoDate(context.now.toLocal());
    final frame = await _knownFrame(db, item.subjectId, on, item.relationType);
    final family = _family(item.relationType);
    if (frame == null) {
      throw StateError('$itemId has too few complete grape locations');
    }
    final candidateIds = {
      for (final candidate in frame.candidates) candidate.id,
    };
    final plantingAreas = item.relationType == plantingRelation
        ? await _plantingAreas(db, item.subjectId, on)
        : const <String, String>{};
    final mappedSubjectId = plantingAreas[item.subjectId] ?? item.subjectId;
    final relationSubjects = item.relationType == plantingRelation
        ? plantingAreas.entries
              .where((e) => candidateIds.contains(e.value))
              .map((e) => e.key)
              .toSet()
        : candidateIds;
    final names = {
      for (final candidate in frame.candidates)
        candidate.id: candidate.node.name,
    };
    // Read relations rather than items: a sourced alternative remains
    // correct even when it has no authored study card of its own.
    final relations =
        await (db.select(db.knowledgeRelations)..where(
              (r) =>
                  r.subjectId.isIn(relationSubjects) &
                  r.relationType.isIn(family) &
                  r.validFrom.isSmallerOrEqualValue(on) &
                  (r.validUntil.isNull() | r.validUntil.isBiggerThanValue(on)),
            ))
            .get();
    final permissions = <String, Set<String>>{};
    for (final relation in relations) {
      permissions
          .putIfAbsent(relation.objectId, () => {})
          .add(plantingAreas[relation.subjectId] ?? relation.subjectId);
    }
    if (!(permissions[item.objectId]?.contains(mappedSubjectId) ?? false)) {
      throw StateError('$itemId is no longer a mapped grape fact');
    }
    // Combination clues ask only current, authored facts in this family about
    // the primary area. Structural links still establish valid alternatives,
    // but never become unplanned bonus reviews.
    final served = await (db.select(
      db.questions,
    )..where((q) => q.questionTemplateId.equals(questionTemplateId))).get();
    final servedIds = served.map((q) => q.knowledgeItemId).toSet();
    var peers = (await KnowledgeGraph(db).currentItems(on: on))
        .where(
          (peer) =>
              peer.subjectId == item.subjectId &&
              servedIds.contains(peer.id) &&
              family.contains(peer.relationType) &&
              (permissions[peer.objectId]?.contains(mappedSubjectId) ?? false),
        )
        .toList();
    final profile = await LearnerProfiles(db).current();
    if (profile != null) {
      final scope = await StudyPlanner(db)
          .effectiveMappings(profile.activeCertificationId);
      peers = peers
          .where(
            (peer) =>
                (scope[peer.id]?.minimumDepth ?? 0) >= requiredDepth('forward'),
          )
          .toList();
    }
    final seenGrapes = {item.objectId};
    peers = peers.where((peer) => seenGrapes.add(peer.objectId)).toList();
    final random = Random(seed);
    peers.shuffle(random);
    final count = 1 + random.nextInt(min(3, peers.length + 1));
    final asked = [item, ...peers.take(count - 1)];
    final grapes = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.isIn(asked.map((i) => i.objectId)))).get();
    final grapeNames = {for (final grape in grapes) grape.id: grape.name};
    final named = [
      for (final askedItem in asked) grapeNames[askedItem.objectId]!,
    ];
    final clue = named.length == 1
        ? named.single
        : '${named.take(named.length - 1).join(', ')} and ${named.last}';
    final correctByItem = {
      for (final askedItem in asked)
        askedItem.id: permissions[askedItem.objectId]!,
    };
    final correct = correctByItem.values.reduce((a, b) => a.intersection(b));
    final subjectNode = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.equals(item.subjectId))).getSingle();
    final year = item.relationType == plantingRelation
        ? RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(subjectNode.name)!.group(0)
        : null;
    final prompt = item.relationType == plantingRelation
        ? switch (random.nextInt(3)) {
            0 =>
              'Find a region with $clue among its two most planted varieties ($year record).',
            1 =>
              'Where did $clue rank in the top two by planted area ($year record)? Select one region.',
            _ =>
              'Select a region whose top-two planted varieties include $clue ($year record).',
          }
        : named.length == 1
        ? switch (random.nextInt(3)) {
            0 => 'Where is $clue permitted? Find one wine area on this map.',
            1 =>
              'Find one mapped wine area whose permitted grapes include $clue.',
            _ =>
              'Which wine area on this map permits $clue? Select one location.',
          }
        : switch (random.nextInt(3)) {
            0 =>
              'Where are $clue all permitted? Find one wine area on this map.',
            1 =>
              'Find one mapped wine area whose permitted grapes include all of these: $clue.',
            _ =>
              'Which wine area on this map permits all of these grapes: $clue? Select one location.',
          };
    final acceptedNames = [for (final id in correct) names[id]!].join(', ');
    final node = await (db.select(
      db.knowledgeNodes,
    )..where((n) => n.id.equals(mappedSubjectId))).getSingle();
    final state = await (db.select(
      db.reviewStates,
    )..where((s) => s.knowledgeItemId.equals(itemId))).getSingleOrNull();
    final mode = mapModeFor(state);
    final zoomedOut = await GeometryRepository(db)
        .frameOf(frame.parent.id, on: on);
    return MapExercise(
      formatId: id,
      primaryItemId: itemId,
      questionTemplateId: questionTemplateId,
      prompt: prompt,
      seed: seed,
      nodeId: node.id,
      nodeName: node.name,
      explanation:
          'Accepted mapped wine areas: $acceptedNames. ${asked.map((i) => i.assertionText).join(' ')}',
      frame: frame,
      zoomedOut: zoomedOut?.box,
      // Keep eligible targets visible: unrepresented atlas areas are
      // context, and the learner needs to know which locations may be tapped.
      mode: mode == MapMode.labelled ? MapMode.labelled : MapMode.outline,
      names: names,
      correct: correct,
      correctByItem: correctByItem,
    );
  }

  @override
  List<ItemGrade> grade(Exercise exercise, Object answer) {
    final map = exercise as MapExercise;
    final graded = super.grade(exercise, answer).single;
    final accepted = map.correctByItem.isEmpty
        ? {map.primaryItemId: map.correctNodeIds}
        : map.correctByItem;
    return [
      for (final itemId in map.itemIds)
        ItemGrade(
          itemId,
          accepted[itemId]!.contains(graded.selectedNodeId)
              ? fsrs.Rating.good
              : fsrs.Rating.again,
          selectedNodeId: graded.selectedNodeId,
          optionNodeIds: map.frame.candidates.map((c) => c.id).toList(),
          payload: {
            ...graded.payload! as Map<String, Object?>,
            'accepted_nodes': accepted[itemId]!.toList(),
            'combination_nodes': map.correctNodeIds.toList(),
            'requested_items': map.itemIds,
          },
        ),
    ];
  }
}
