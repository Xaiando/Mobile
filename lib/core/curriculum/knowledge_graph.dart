import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../time/utc_clock.dart';

/// A node reached by a traversal, [depth] steps from where it started.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.nodeType,
    required this.name,
    required this.depth,
  });

  final String id;
  final String nodeType;
  final String name;
  final int depth;

  @override
  String toString() => '$name ($nodeType, depth $depth)';
}

/// A relation with both ends named, as seen from one of them.
class NodeRelation {
  const NodeRelation({
    required this.subjectId,
    required this.subjectName,
    required this.relationType,
    required this.label,
    required this.objectId,
    required this.objectName,
  });

  final String subjectId;
  final String subjectName;
  final String relationType;

  /// The relation type's label, e.g. "permits the principal grape".
  final String label;
  final String objectId;
  final String objectName;

  @override
  String toString() => '$subjectName $label $objectName';
}

/// An item whose fact no longer holds (spec §S.4): its relation has ended,
/// or a newer item supersedes it.
class ExpiredItem {
  const ExpiredItem({
    required this.itemId,
    this.validUntil,
    this.supersededByItemId,
  });

  final String itemId;
  final String? validUntil;
  final String? supersededByItemId;
}

/// Graph traversal over the curriculum, as relational JOINs and recursive
/// CTEs (spec §C, §O Phase 1).
///
/// Only relations current on the date given (by default the device's local
/// date) are followed: `valid_from <= date < valid_until` (audit V-2).
class KnowledgeGraph {
  KnowledgeGraph(this.db, {Clock? clock}) : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  /// Deep enough for any containment chain; bounds the recursion even if a
  /// cycle slipped past the validator.
  static const maxDepth = 32;

  /// SQL for "relation [alias] is in force on the date bound to `?2`".
  static String _current(String alias) =>
      '$alias.valid_from <= ?2 '
      'AND ($alias.valid_until IS NULL OR $alias.valid_until > ?2)';

  String _date(String? on) => on ?? localToday(_clock);

  /// The places containing [nodeId], nearest first: Chablis gives Burgundy,
  /// then France.
  Future<List<GraphNode>> ancestors(String nodeId, {String? on}) =>
      _containment(nodeId, upward: true, on: on);

  /// The places [nodeId] contains, nearest first.
  Future<List<GraphNode>> descendants(String nodeId, {String? on}) =>
      _containment(nodeId, upward: false, on: on);

  Future<List<GraphNode>> _containment(
    String nodeId, {
    required bool upward,
    String? on,
  }) async {
    final (from, to) = upward
        ? ('subject_id', 'object_id')
        : ('object_id', 'subject_id');
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE walk(id, depth) AS (
        SELECT ?1, 0
        UNION
        SELECT r.$to, walk.depth + 1
        FROM knowledge_relations r JOIN walk ON r.$from = walk.id
        WHERE r.relation_type = 'LOCATED_IN' AND walk.depth < $maxDepth
          AND ${_current('r')}
      )
      SELECT n.id, n.node_type, n.name, min(walk.depth) AS depth
      FROM walk JOIN knowledge_nodes n ON n.id = walk.id
      WHERE walk.depth > 0
      GROUP BY n.id
      ORDER BY depth, n.name''',
          variables: [Variable(nodeId), Variable(_date(on))],
          readsFrom: {db.knowledgeRelations, db.knowledgeNodes},
        )
        .get();
    return [for (final row in rows) _graphNode(row)];
  }

  /// Nodes of the same type as [nodeId] that share one of its direct
  /// parents: the other appellations of its region (spec TASK-004).
  Future<List<GraphNode>> siblings(String nodeId, {String? on}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT DISTINCT n.id, n.node_type, n.name, 1 AS depth
      FROM knowledge_relations up
      JOIN knowledge_nodes me ON me.id = up.subject_id
      JOIN knowledge_relations down
        ON down.object_id = up.object_id AND down.relation_type = 'LOCATED_IN'
      JOIN knowledge_nodes n
        ON n.id = down.subject_id AND n.node_type = me.node_type
      WHERE up.subject_id = ?1 AND up.relation_type = 'LOCATED_IN'
        AND n.id <> ?1
        AND ${_current('up')} AND ${_current('down')}
      ORDER BY n.name''',
          variables: [Variable(nodeId), Variable(_date(on))],
          readsFrom: {db.knowledgeRelations, db.knowledgeNodes},
        )
        .get();
    return [for (final row in rows) _graphNode(row)];
  }

  /// Every relation with [nodeId] at either end, with both ends named.
  Future<List<NodeRelation>> relationsOf(String nodeId, {String? on}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT r.subject_id, s.name AS subject_name, r.relation_type, t.label,
             r.object_id, o.name AS object_name
      FROM knowledge_relations r
      JOIN knowledge_nodes s ON s.id = r.subject_id
      JOIN knowledge_nodes o ON o.id = r.object_id
      JOIN relation_types t ON t.id = r.relation_type
      WHERE (r.subject_id = ?1 OR r.object_id = ?1) AND ${_current('r')}
      ORDER BY r.relation_type, s.name, o.name''',
          variables: [Variable(nodeId), Variable(_date(on))],
          readsFrom: {
            db.knowledgeRelations,
            db.knowledgeNodes,
            db.relationTypes,
          },
        )
        .get();
    return [
      for (final row in rows)
        NodeRelation(
          subjectId: row.read<String>('subject_id'),
          subjectName: row.read<String>('subject_name'),
          relationType: row.read<String>('relation_type'),
          label: row.read<String>('label'),
          objectId: row.read<String>('object_id'),
          objectName: row.read<String>('object_name'),
        ),
    ];
  }

  /// The items [itemId] builds on, directly or transitively, nearest first.
  Future<List<(String itemId, int depth)>> prerequisitesOf(
    String itemId,
  ) async {
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE needs(id, depth) AS (
        SELECT prerequisite_item_id, 1 FROM knowledge_item_prerequisites
        WHERE knowledge_item_id = ?1
        UNION
        SELECT p.prerequisite_item_id, needs.depth + 1
        FROM knowledge_item_prerequisites p JOIN needs
          ON p.knowledge_item_id = needs.id
        WHERE needs.depth < $maxDepth
      )
      SELECT id, min(depth) AS depth FROM needs
      GROUP BY id ORDER BY depth, id''',
          variables: [Variable(itemId)],
          readsFrom: {db.knowledgeItemPrerequisites},
        )
        .get();
    return [
      for (final row in rows) (row.read<String>('id'), row.read<int>('depth')),
    ];
  }

  /// Items that are their own prerequisite through a chain of any length
  /// (spec §S.2). Empty for a valid curriculum.
  Future<List<String>> prerequisiteCycles() async {
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE reach(start, id, depth) AS (
        SELECT knowledge_item_id, prerequisite_item_id, 1
        FROM knowledge_item_prerequisites
        UNION
        SELECT reach.start, p.prerequisite_item_id, reach.depth + 1
        FROM reach JOIN knowledge_item_prerequisites p
          ON p.knowledge_item_id = reach.id
        WHERE reach.depth < $maxDepth
      )
      SELECT DISTINCT start FROM reach WHERE id = start ORDER BY start''',
          readsFrom: {db.knowledgeItemPrerequisites},
        )
        .get();
    return [for (final row in rows) row.read<String>('start')];
  }

  /// Items whose relation ended on or before [on], or that are superseded
  /// (spec §S.4). The app tells the learner the rules changed (audit V-3).
  Future<List<ExpiredItem>> expiredItems({String? on}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT i.id, r.valid_until, i.superseded_by_item_id
      FROM knowledge_items i
      JOIN knowledge_relations r ON r.subject_id = i.subject_id
        AND r.relation_type = i.relation_type AND r.object_id = i.object_id
      WHERE (r.valid_until IS NOT NULL AND r.valid_until <= ?1)
         OR i.superseded_by_item_id IS NOT NULL
      ORDER BY i.id''',
          variables: [Variable(_date(on))],
          readsFrom: {db.knowledgeItems, db.knowledgeRelations},
        )
        .get();
    return [
      for (final row in rows)
        ExpiredItem(
          itemId: row.read<String>('id'),
          validUntil: row.readNullable<String>('valid_until'),
          supersededByItemId: row.readNullable<String>('superseded_by_item_id'),
        ),
    ];
  }

  /// Items not re-verified for [months] months: shown as "may be out of
  /// date" (audit V-4; 24 months per decision P-1).
  Future<List<KnowledgeItem>> staleItems({int months = 24}) {
    final now = utcNow(_clock);
    final cutoff = DateTime.utc(
      now.year,
      now.month - months,
      now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
    );
    return (db.select(db.knowledgeItems)
          ..where((i) => i.lastVerifiedAt.isSmallerThanValue(cutoff))
          ..orderBy([(i) => OrderingTerm(expression: i.lastVerifiedAt)]))
        .get();
  }

  static GraphNode _graphNode(QueryRow row) => GraphNode(
    id: row.read<String>('id'),
    nodeType: row.read<String>('node_type'),
    name: row.read<String>('name'),
    depth: row.read<int>('depth'),
  );
}
