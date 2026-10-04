import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../study/study_planner.dart';

/// A geographic focus whose item IDs are already served as map questions by
/// the active track. A descendant's map facts count under every containing
/// region, so learners can choose France, Burgundy or Chablis independently.
class MapPracticeScope {
  const MapPracticeScope({
    required this.id,
    required this.name,
    required this.path,
    required this.countryName,
    required this.itemIds,
    required this.readyCount,
  });

  final String id;
  final String name;
  final String path;
  final String? countryName;
  final Set<String> itemIds;
  final int readyCount;

  int get factCount => itemIds.length;
}

/// Builds map choices from *served* track cards, not raw atlas nodes. Current
/// LOCATED_IN edges drive containment; dated planting records are resolved to
/// their real area before traversing. No scope can introduce a card absent
/// from the learner's certification.
class MapPracticeCatalog {
  const MapPracticeCatalog(this.db);

  final AppDatabase db;

  Future<List<MapPracticeScope>> scopes(
    List<StudyCard> cards, {
    required String on,
    required DateTime now,
  }) async {
    const mapModes = {'map_locate', 'map_identify', 'map_pair', 'map_grape'};
    final mapped = cards
        .where((card) => card.formats.any((f) => mapModes.contains(f.mode)))
        .toList();
    if (mapped.isEmpty) return const [];

    final nodes = {
      for (final node in await db.select(db.knowledgeNodes).get())
        node.id: node,
    };
    final relations =
        await (db.select(db.knowledgeRelations)..where(
              (r) =>
                  r.relationType.isIn(const {
                    'LOCATED_IN',
                    'STATISTIC_IN_AREA',
                  }) &
                  r.validFrom.isSmallerOrEqualValue(on) &
                  (r.validUntil.isNull() | r.validUntil.isBiggerThanValue(on)),
            ))
            .get();
    final parents = <String, Set<String>>{};
    final plantedIn = <String, String>{};
    for (final relation in relations) {
      if (relation.relationType == 'LOCATED_IN') {
        parents
            .putIfAbsent(relation.subjectId, () => <String>{})
            .add(relation.objectId);
      } else {
        plantedIn[relation.subjectId] = relation.objectId;
      }
    }

    final byScope = <String, Map<String, StudyCard>>{};
    for (final card in mapped) {
      final areaId = card.item.relationType == 'TOP_PLANTED_GRAPE'
          ? plantedIn[card.item.subjectId]
          : card.item.subjectId;
      if (areaId == null) continue;
      final seen = <String>{};
      final stack = [areaId];
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        if (!seen.add(id)) continue;
        final node = nodes[id];
        if (node == null || node.nodeType == 'statistic') continue;
        byScope.putIfAbsent(id, () => {})[card.itemId] = card;
        stack.addAll(parents[id] ?? const {});
      }
    }

    String? countryFor(String id) {
      final seen = <String>{};
      final queue = [id];
      while (queue.isNotEmpty) {
        final next = queue.removeAt(0);
        if (!seen.add(next)) continue;
        if (nodes[next]?.nodeType == 'country') return nodes[next]!.name;
        queue.addAll((parents[next] ?? const <String>{}).toList()..sort());
      }
      return null;
    }

    String pathFor(String id) {
      final names = <String>[];
      final seen = <String>{};
      var next = id;
      while (seen.add(next)) {
        final node = nodes[next];
        if (node == null) break;
        names.add(node.name);
        if (node.nodeType == 'country') break;
        final direct = (parents[next] ?? const <String>{}).toList()
          ..sort(
            (a, b) => (nodes[a]?.name ?? a).compareTo(nodes[b]?.name ?? b),
          );
        if (direct.isEmpty) break;
        next = direct.first;
      }
      return names.join(' · ');
    }

    final scopes = [
      for (final entry in byScope.entries)
        if (nodes[entry.key] case final node?)
          MapPracticeScope(
            id: entry.key,
            name: node.name,
            path: pathFor(entry.key),
            countryName: countryFor(entry.key),
            itemIds: Set.unmodifiable(entry.value.keys),
            readyCount: entry.value.values
                .where((card) => card.isNew || card.isDue(now))
                .length,
          ),
    ];
    scopes.sort((a, b) {
      final country = (a.countryName ?? '').compareTo(b.countryName ?? '');
      if (country != 0) return country;
      final depth = a.path
          .split(' · ')
          .length
          .compareTo(b.path.split(' · ').length);
      if (depth != 0) return depth;
      return a.name.compareTo(b.name);
    });
    return scopes;
  }
}
