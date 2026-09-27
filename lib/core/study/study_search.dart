import '../curriculum/name_normalizer.dart';
import '../database/app_database.dart';

/// Searchable canonical names and aliases, updated when either table changes.
class StudySearchIndex {
  const StudySearchIndex(this.db);

  final AppDatabase db;

  Stream<Map<String, String>> watchNames() => db
      .customSelect(
        'SELECT n.id, n.name, a.name AS alternative_name '
        'FROM knowledge_nodes n LEFT JOIN node_alternative_names a '
        'ON a.knowledge_node_id = n.id',
        readsFrom: {db.knowledgeNodes, db.nodeAlternativeNames},
      )
      .watch()
      .map((rows) {
        final names = <String, Set<String>>{};
        for (final row in rows) {
          final values = names.putIfAbsent(row.read<String>('id'), () => {});
          values.add(row.read<String>('name'));
          final alternative = row.readNullable<String>('alternative_name');
          if (alternative != null) values.add(alternative);
        }
        return {
          for (final entry in names.entries)
            entry.key: normalizeName(entry.value.join(' ')),
        };
      });
}
