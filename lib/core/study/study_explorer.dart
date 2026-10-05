import 'package:clock/clock.dart';

import '../curriculum/name_normalizer.dart';
import '../database/app_database.dart';
import '../questions/exercise.dart';
import '../questions/exercise_presenter.dart';
import '../time/utc_clock.dart';
import 'study_planner.dart';
import 'wine_history_catalog.dart';

enum StudyCategory { grapes, history, regions, wines }

/// An editorial study selection, not a vineyard-area ranking or syllabus.
const coreStudyGrapeIds = <String>{
  'n_grape_cabernet_sauvignon',
  'n_grape_merlot',
  'n_grape_pinot_noir',
  'n_grape_syrah',
  'n_grape_grenache',
  'n_grape_tempranillo',
  'n_grape_sangiovese',
  'n_grape_nebbiolo',
  'n_grape_malbec',
  'n_grape_zinfandel',
  'n_grape_gamay',
  'n_grape_carmenere',
  'n_grape_pinotage',
  'n_grape_mourvedre',
  'n_grape_cabernet_franc',
  'n_grape_chardonnay',
  'n_grape_sauvignon_blanc',
  'n_grape_chenin_blanc',
  'n_grape_riesling',
  'n_grape_pinot_gris',
  'n_grape_gewurztraminer',
  'n_grape_semillon',
  'n_grape_viognier',
  'n_grape_garganega',
  'n_grape_albarino',
  'n_grape_gruner_veltliner',
  'n_grape_muscat_blanc_a_petits_grains',
  'n_grape_barbera',
  'n_grape_melon',
  'n_grape_palomino_fino',
};

const _areaTypes = {'country', 'region', 'subregion', 'appellation'};

class StudyTopic {
  StudyTopic({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.trackId,
    required this.cards,
    required this.mapCards,
    this.nodeId,
    this.aliases = const [],
    this.foundationItemIds = const {},
  });

  final String id;
  final StudyCategory category;
  final String title;
  final String subtitle;
  final String trackId;
  final String? nodeId;
  final List<String> aliases;
  final List<StudyCard> cards;
  final List<StudyCard> mapCards;
  final Set<String> foundationItemIds;

  bool matches(String query) {
    final text = normalizeName('$title $subtitle ${aliases.join(' ')}');
    return normalizeName(query).split(' ').every(text.contains);
  }

  List<StudyCard> get questionCards => cards
      .where(
        (card) => card.formats.any(
          (f) => const {'mcq', 'authored_choice', 'typed'}.contains(f.mode),
        ),
      )
      .toList();
}

/// Read-only exploration. All facts retain the planner's currentness,
/// supersession and delivery checks. It neither selects a learner track nor
/// records reviews. Regions/wines use Level 2 including inherited Level 1;
/// grapes/history are explicitly broader reference material.
class StudyExplorer {
  StudyExplorer(this.db, {Clock? clock}) : clock = clock ?? const Clock();
  final AppDatabase db;
  final Clock clock;

  Future<List<StudyTopic>> topics() async {
    final planner = StudyPlanner(db, clock: clock);
    final basics = await planner.cards('WSET_L2');
    final basicIds = basics.map((c) => c.itemId).toSet();
    final reference = await planner.cards('WSET_L4');
    final referenceMaps = <String, StudyCard>{
      for (final card in [...basics, ...reference]) card.itemId: card,
    }.values.toList();
    final on = localToday(clock);
    final nodes = {
      for (final node in await db.select(db.knowledgeNodes).get())
        if ((node.validFrom == null || node.validFrom!.compareTo(on) <= 0) &&
            (node.validUntil == null || node.validUntil!.compareTo(on) > 0))
          node.id: node,
    };
    final aliases = <String, List<String>>{};
    for (final alias in await db.select(db.nodeAlternativeNames).get()) {
      aliases.putIfAbsent(alias.knowledgeNodeId, () => []).add(alias.name);
    }
    final children = <String, Set<String>>{};
    for (final r in await db.select(db.knowledgeRelations).get()) {
      if (r.relationType == 'LOCATED_IN' &&
          r.validFrom.compareTo(on) <= 0 &&
          (r.validUntil == null || r.validUntil!.compareTo(on) > 0)) {
        children.putIfAbsent(r.objectId, () => {}).add(r.subjectId);
      }
    }
    Set<String> inside(String id) {
      final result = <String>{};
      final queue = [id];
      while (queue.isNotEmpty) {
        final next = queue.removeLast();
        if (result.add(next)) queue.addAll(children[next] ?? const {});
      }
      return result;
    }

    final searchText = <String, String>{};
    final namePhrases = <String, List<String>>{};
    bool mentions(StudyCard card, KnowledgeNode node) {
      if (card.item.subjectId == node.id || card.item.objectId == node.id) {
        return true;
      }
      // A passing grape/place mention in a Diploma decision case does not
      // make its entire business/production scenario a variety profile.
      if (nodes[card.item.subjectId]?.nodeType == 'production_case') {
        return false;
      }
      // Authored profile lessons use principle/point nodes, rather than the
      // grape as a graph endpoint. Match whole phrases, including synonyms,
      // without altering the graph or the question grader.
      final text = searchText.putIfAbsent(
        card.itemId,
        () =>
            ' ${normalizeName('${nodes[card.item.subjectId]?.name ?? ''} '
            '${card.item.assertionText}')} ',
      );
      final phrases = namePhrases.putIfAbsent(
        node.id,
        () => [
          for (final name in [node.name, ...?aliases[node.id]])
            ' ${normalizeName(name)} ',
        ],
      );
      return phrases.any(text.contains);
    }

    List<StudyCard> mapsFor(
      List<StudyCard> cards,
      List<StudyCard> pool,
      Set<String> locations,
    ) {
      final ids = {...locations};
      for (final c in cards) {
        for (final id in [c.item.subjectId, c.item.objectId]) {
          if (_areaTypes.contains(nodes[id]?.nodeType)) ids.add(id);
        }
      }
      // Narrative profile/history lessons often mention a place without using
      // it as a graph endpoint. These links are navigation to independent,
      // already served location facts, not new growing-region assertions.
      for (final mapCard in pool) {
        if (!mapCard.formats.any((f) => f.mode == 'map_locate')) continue;
        final place = nodes[mapCard.item.subjectId];
        if (place != null && cards.any((card) => mentions(card, place))) {
          ids.add(place.id);
        }
      }
      return pool
          .where(
            (c) =>
                ids.contains(c.item.subjectId) &&
                c.formats.any((f) => f.mode == 'map_locate'),
          )
          .toList();
    }

    final topics = <StudyTopic>[];
    void addNode(
      KnowledgeNode node,
      StudyCategory category,
      List<StudyCard> pool,
      String track, {
      String? title,
    }) {
      final geography = category == StudyCategory.regions;
      final scope = geography ? inside(node.id) : <String>{node.id};
      final cards = pool
          .where(
            (c) => geography
                ? scope.contains(c.item.subjectId) ||
                      scope.contains(c.item.objectId)
                : mentions(c, node),
          )
          .toList();
      if (cards.isEmpty) return;
      cards.sort((a, b) {
        final foundation = (basicIds.contains(a.itemId) ? 0 : 1).compareTo(
          basicIds.contains(b.itemId) ? 0 : 1,
        );
        return foundation != 0 ? foundation : a.itemId.compareTo(b.itemId);
      });
      topics.add(
        StudyTopic(
          id: '${category.name}-${node.id}',
          category: category,
          title: title ?? node.name,
          nodeId: node.id,
          trackId: track,
          aliases: aliases[node.id] ?? const [],
          cards: cards,
          foundationItemIds: basicIds,
          mapCards: mapsFor(
            cards,
            track == 'WSET_L4' ? referenceMaps : pool,
            geography ? scope : {node.id},
          ),
          subtitle: geography || category == StudyCategory.wines
              ? 'WSET Levels 1–2 · ${node.nodeType}'
              : 'Core sommelier reference · beyond Level 2 where available',
        ),
      );
    }

    for (final id in coreStudyGrapeIds) {
      if (nodes[id] case final node?) {
        addNode(node, StudyCategory.grapes, reference, 'WSET_L4');
      }
    }
    final basicNodeIds = {
      for (final c in basics) ...[c.item.subjectId, c.item.objectId],
    };
    for (final node in nodes.values) {
      if (!basicNodeIds.contains(node.id)) continue;
      if (_areaTypes.contains(node.nodeType)) {
        addNode(node, StudyCategory.regions, basics, 'WSET_L2');
      }
      if (const {
        'appellation',
        'wine_type',
        'wine_style',
      }.contains(node.nodeType)) {
        addNode(node, StudyCategory.wines, basics, 'WSET_L2');
      }
    }
    if (nodes['n_grape_pinot_noir'] case final pinot?) {
      addNode(
        pinot,
        StudyCategory.wines,
        basics,
        'WSET_L2',
        title: 'Spätburgunder / Pinot Noir',
      );
    }
    topics.sort(
      (a, b) => normalizeName(a.title).compareTo(normalizeName(b.title)),
    );
    final history = reference
        .where((c) => isWineHistoryItem(c.itemId))
        .toList();
    final grouped = <String>{};
    for (final moment in wineHistoryMoments) {
      final cards = history
          .where(
            (c) => moment.identifiers.any(
              (id) => c.itemId == id || c.item.subjectId == id,
            ),
          )
          .toList();
      if (cards.isEmpty) continue;
      grouped.addAll(cards.map((c) => c.itemId));
      topics.add(
        StudyTopic(
          id: 'history-${moment.id}',
          category: StudyCategory.history,
          title: moment.title,
          subtitle: '${moment.date} · optional history reference',
          trackId: 'WSET_L4',
          cards: cards,
          mapCards: mapsFor(cards, referenceMaps, const {}),
        ),
      );
    }
    final remaining = history
        .where((c) => !grouped.contains(c.itemId))
        .toList();
    if (remaining.isNotEmpty) {
      topics.add(
        StudyTopic(
          id: 'history-context',
          category: StudyCategory.history,
          title: 'Historical context',
          subtitle: 'Optional history reference',
          trackId: 'WSET_L4',
          cards: remaining,
          mapCards: mapsFor(remaining, referenceMaps, const {}),
        ),
      );
    }
    return topics;
  }

  /// Use precisely the existing templates served for this topic's scope.
  Future<Exercise> present(
    StudyTopic topic,
    StudyCard card,
    QuestionFormat format, {
    required int seed,
  }) {
    if (![
          ...topic.cards,
          ...topic.mapCards,
        ].any((c) => c.itemId == card.itemId) ||
        !card.formats.contains(format)) {
      throw ArgumentError('Question does not belong to this topic');
    }
    return ExercisePresenter(db, clock: clock).present(
      card.itemId,
      format.questionTemplateId,
      seed: seed,
      certificationId: topic.trackId,
    );
  }

  List<ItemGrade> grade(Exercise exercise, Object answer) =>
      ExercisePresenter(db, clock: clock).grade(exercise, answer);
}
