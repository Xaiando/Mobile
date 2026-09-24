import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// A source that supports an item, with the place in it that does.
class ItemSource {
  const ItemSource(this.citation, this.locator);

  final SourceCitation citation;

  /// The article, section or page within the source, when recorded.
  final String? locator;
}

/// Read access to the curriculum's reference data: its domains and the
/// sources behind each item.
class CurriculumCatalog {
  CurriculumCatalog(this.db);

  final AppDatabase db;

  /// The curriculum domains, in display order.
  Future<List<CurriculumDomain>> domains() => (db.select(
    db.curriculumDomains,
  )..orderBy([(d) => OrderingTerm(expression: d.position)])).get();

  /// The sources cited for [itemId], by title.
  Future<List<ItemSource>> sourcesOf(String itemId) async {
    final rows = await db
        .customSelect(
          '''
      SELECT s.*, c.locator FROM knowledge_item_citations c
      JOIN source_citations s ON s.id = c.source_citation_id
      WHERE c.knowledge_item_id = ?1
      ORDER BY s.title''',
          variables: [Variable(itemId)],
          readsFrom: {db.knowledgeItemCitations, db.sourceCitations},
        )
        .get();
    return [
      for (final row in rows)
        ItemSource(
          db.sourceCitations.map(row.data),
          row.readNullable<String>('locator'),
        ),
    ];
  }
}
