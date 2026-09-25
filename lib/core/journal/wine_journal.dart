import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

/// What a learner writes about one wine (spec §J, backlog J1). Every field
/// is optional, but an entry must name its wine somehow.
class JournalDraft {
  const JournalDraft({
    this.tastedOn,
    this.producerName,
    this.cuveeName,
    this.vintage,
    this.isNonVintage = false,
    this.appellationText,
    this.grapesText,
    this.abvPercent,
    this.rating,
    this.tastingNotes,
  });

  /// The draft of an existing [entry], for editing it.
  factory JournalDraft.of(WineJournalEntry entry) => JournalDraft(
    tastedOn: entry.tastedOn,
    producerName: entry.producerName,
    cuveeName: entry.cuveeName,
    vintage: entry.vintage,
    isNonVintage: entry.isNonVintage,
    appellationText: entry.appellationText,
    grapesText: entry.grapesText,
    abvPercent: entry.abvPercent,
    rating: entry.rating,
    tastingNotes: entry.tastingNotes,
  );

  /// `YYYY-MM-DD`.
  final String? tastedOn;
  final String? producerName;
  final String? cuveeName;
  final int? vintage;
  final bool isNonVintage;
  final String? appellationText;
  final String? grapesText;
  final double? abvPercent;

  /// 1 to 5 (P-3).
  final int? rating;
  final String? tastingNotes;

  static const minimumVintage = 1800;
  static const maximumVintage = 2100;

  /// Why the database would refuse this draft, in the learner's words; empty
  /// when it can be saved.
  List<String> get problems => [
    if ([
      producerName,
      cuveeName,
      appellationText,
      grapesText,
    ].every((text) => (text ?? '').trim().isEmpty))
      'Name the wine: a producer, cuvée, appellation or grapes.',
    if (vintage != null &&
        (vintage! < minimumVintage || vintage! > maximumVintage))
      'A vintage lies between $minimumVintage and $maximumVintage.',
    if (isNonVintage && vintage != null) 'A non-vintage wine has no vintage.',
    if (abvPercent != null && (abvPercent! <= 0 || abvPercent! >= 100))
      'Alcohol lies between 0 and 100 %.',
    if (rating != null && (rating! < 1 || rating! > 5))
      'A rating is from 1 to 5.',
    if (tastedOn != null && !_isDate(tastedOn!))
      'The tasting date is not a calendar date.',
  ];

  bool get isValid => problems.isEmpty;

  static bool _isDate(String text) {
    final parsed = DateTime.tryParse('${text}T00:00:00Z');
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
        parsed != null &&
        isoDate(parsed) == text;
  }

  /// Empty text stored as NULL, so "no appellation" has one form.
  static String? _text(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  WineJournalEntriesCompanion _columns() => WineJournalEntriesCompanion(
    tastedOn: Value(tastedOn),
    producerName: Value(_text(producerName)),
    cuveeName: Value(_text(cuveeName)),
    vintage: Value(vintage),
    isNonVintage: Value(isNonVintage),
    appellationText: Value(_text(appellationText)),
    grapesText: Value(_text(grapesText)),
    abvPercent: Value(abvPercent),
    rating: Value(rating),
    tastingNotes: Value(_text(tastingNotes)),
  );
}

/// Thrown when a draft cannot be saved; [problems] says why.
class JournalDraftException implements Exception {
  JournalDraftException(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'The journal entry cannot be saved: ${problems.join(' ')}';
}

/// The wine journal (spec §J, backlog J1): the learner's own entries, and
/// the knowledge nodes each one is linked to (J2).
class WineJournal {
  WineJournal(this.db, {Clock? clock, this.random})
    : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  /// Makes entry IDs reproducible in tests; secure by default.
  final Random? random;

  /// Every entry, the most recently tasted first; entries without a date
  /// come after dated ones, newest first.
  Stream<List<WineJournalEntry>> watchAll() =>
      (db.select(db.wineJournalEntries)..orderBy([
            (e) => OrderingTerm(expression: e.tastedOn.isNull()),
            (e) => OrderingTerm.desc(e.tastedOn),
            (e) => OrderingTerm.desc(e.createdAt),
          ]))
          .watch();

  /// The entry [id] as it changes; null once deleted.
  Stream<WineJournalEntry?> watch(String id) => (db.select(
    db.wineJournalEntries,
  )..where((e) => e.id.equals(id))).watchSingleOrNull();

  Future<WineJournalEntry?> entry(String id) => (db.select(
    db.wineJournalEntries,
  )..where((e) => e.id.equals(id))).getSingleOrNull();

  /// Saves a new entry, linked to [nodeIds].
  Future<WineJournalEntry> create(
    JournalDraft draft, {
    Set<String> nodeIds = const {},
  }) async {
    _check(draft);
    final id = newUuid(random);
    final now = utcNow(_clock);
    return db.transaction(() async {
      await db
          .into(db.wineJournalEntries)
          .insert(
            draft._columns().copyWith(
              id: Value(id),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await _link(id, nodeIds);
      return (await entry(id))!;
    });
  }

  /// Replaces entry [id]'s fields with [draft], and its links with
  /// [nodeIds] when given.
  Future<WineJournalEntry> update(
    String id,
    JournalDraft draft, {
    Set<String>? nodeIds,
  }) async {
    _check(draft);
    return db.transaction(() async {
      final existing = await entry(id);
      if (existing == null) {
        throw ArgumentError.value(id, 'id', 'is no journal entry');
      }
      final now = utcNow(_clock);
      await (db.update(
        db.wineJournalEntries,
      )..where((e) => e.id.equals(id))).write(
        draft._columns().copyWith(
          // The schema requires updated_at >= created_at, even if the
          // device clock was set back.
          updatedAt: Value(
            now.isBefore(existing.createdAt) ? existing.createdAt : now,
          ),
        ),
      );
      if (nodeIds != null) await _link(id, nodeIds);
      return (await entry(id))!;
    });
  }

  /// Deletes entry [id] and its links. A tasting session of the wine keeps
  /// its notes and loses only the link (schema: ON DELETE SET NULL).
  Future<void> delete(String id) => db.transaction(() async {
    await (db.delete(
      db.wineJournalEntries,
    )..where((e) => e.id.equals(id))).go();
  });

  /// The knowledge nodes entry [id] is linked to, by name.
  Stream<List<KnowledgeNode>> watchLinkedNodes(String id) =>
      _linkedNodes(id).watch();

  /// The knowledge nodes entry [id] is linked to now, by name.
  Future<List<KnowledgeNode>> linkedNodes(String id) => _linkedNodes(id).get();

  Selectable<KnowledgeNode> _linkedNodes(String id) {
    final query =
        db.select(db.knowledgeNodes).join([
            innerJoin(
              db.wineJournalEntryNodes,
              db.wineJournalEntryNodes.knowledgeNodeId.equalsExp(
                db.knowledgeNodes.id,
              ),
            ),
          ])
          ..where(db.wineJournalEntryNodes.wineJournalEntryId.equals(id))
          ..orderBy([OrderingTerm(expression: db.knowledgeNodes.name)]);
    return query.map((row) => row.readTable(db.knowledgeNodes));
  }

  /// The IDs of the nodes entry [id] is linked to.
  Future<Set<String>> linkedNodeIds(String id) async => {
    for (final row in await (db.select(
      db.wineJournalEntryNodes,
    )..where((n) => n.wineJournalEntryId.equals(id))).get())
      row.knowledgeNodeId,
  };

  Future<void> _link(String id, Set<String> nodeIds) async {
    await (db.delete(
      db.wineJournalEntryNodes,
    )..where((n) => n.wineJournalEntryId.equals(id))).go();
    for (final nodeId in nodeIds) {
      await db
          .into(db.wineJournalEntryNodes)
          .insert(
            WineJournalEntryNodesCompanion.insert(
              wineJournalEntryId: id,
              knowledgeNodeId: nodeId,
            ),
          );
    }
  }

  static void _check(JournalDraft draft) {
    final problems = draft.problems;
    if (problems.isNotEmpty) throw JournalDraftException(problems);
  }

  /// For each knowledge node the journal links, the day the learner last
  /// met it: the latest tasting date of its entries, or the day an undated
  /// entry was written (A-5).
  Future<Map<String, String>> lastMetByNode() async {
    final rows = await db
        .customSelect(
          'SELECT n.knowledge_node_id AS node, '
          'MAX(COALESCE(e.tasted_on, substr(e.created_at, 1, 10))) AS day '
          'FROM wine_journal_entry_nodes n '
          'JOIN wine_journal_entries e ON e.id = n.wine_journal_entry_id '
          'GROUP BY n.knowledge_node_id',
          readsFrom: {db.wineJournalEntries, db.wineJournalEntryNodes},
        )
        .get();
    return {
      for (final row in rows) row.read<String>('node'): row.read<String>('day'),
    };
  }
}
