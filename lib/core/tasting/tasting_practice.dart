import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

/// One attribute of a tasting grid, with the values it offers in order.
class GridAttribute {
  const GridAttribute(this.attribute, this.values);

  final TastingGridAttribute attribute;
  final List<TastingGridValue> values;

  String get key => attribute.attributeKey;
  bool get isSingle => attribute.selection == 'single';
}

/// A tasting grid with its attributes in order, grouped by section.
class GridLayout {
  const GridLayout(this.grid, this.attributes);

  final TastingGrid grid;
  final List<GridAttribute> attributes;

  /// The sections in the order their first attribute comes.
  List<String> get sections =>
      {for (final a in attributes) a.attribute.section}.toList();

  List<GridAttribute> inSection(String section) => [
    for (final a in attributes)
      if (a.attribute.section == section) a,
  ];

  /// The required attributes [answers] leaves unanswered, in grid order.
  List<GridAttribute> missing(Map<String, Set<String>> answers) => [
    for (final a in attributes)
      if (a.attribute.isRequired && (answers[a.key] ?? const {}).isEmpty) a,
  ];
}

/// Tasting practice (spec Phase 4, backlog T2): sessions on one of the
/// app's grids, answered value by value, saved as they go and resumable.
///
/// The schema keeps a session to its own grid's vocabulary and one value
/// per single-choice attribute (TASK-008).
class TastingPractice {
  TastingPractice(this.db, {Clock? clock, this.random})
    : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  /// Makes session IDs reproducible in tests; secure by default.
  final Random? random;

  /// The grids, by name.
  Future<List<TastingGrid>> grids() => (db.select(
    db.tastingGrids,
  )..orderBy([(g) => OrderingTerm(expression: g.displayName)])).get();

  /// Grid [id] with its attributes and values, in order.
  Future<GridLayout> layout(String id) async {
    final grid = await (db.select(
      db.tastingGrids,
    )..where((g) => g.id.equals(id))).getSingle();
    final attributes =
        await (db.select(db.tastingGridAttributes)
              ..where((a) => a.tastingGridId.equals(id))
              ..orderBy([(a) => OrderingTerm(expression: a.position)]))
            .get();
    final values =
        await (db.select(db.tastingGridValues)
              ..where((v) => v.tastingGridId.equals(id))
              ..orderBy([(v) => OrderingTerm(expression: v.position)]))
            .get();
    return GridLayout(grid, [
      for (final attribute in attributes)
        GridAttribute(attribute, [
          for (final value in values)
            if (value.attributeKey == attribute.attributeKey) value,
        ]),
    ]);
  }

  /// The grid a track tastes with (its `default_tasting_grid_id`), if any.
  Future<String?> gridFor(String certificationId) async =>
      (await (db.select(
            db.certifications,
          )..where((c) => c.id.equals(certificationId))).getSingleOrNull())
          ?.defaultTastingGridId;

  /// Every session, or those about one wine in the journal, the most
  /// recent first.
  Stream<List<TastingSession>> watchSessions({String? journalEntryId}) {
    final query = db.select(db.tastingSessions)
      ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]);
    if (journalEntryId != null) {
      query.where((s) => s.wineJournalEntryId.equals(journalEntryId));
    }
    return query.watch();
  }

  Stream<TastingSession?> watchSession(String id) => (db.select(
    db.tastingSessions,
  )..where((s) => s.id.equals(id))).watchSingleOrNull();

  /// Starts a session on grid [gridId], blind unless [isBlind] is false,
  /// optionally about a wine in the journal.
  Future<TastingSession> start(
    String gridId, {
    bool isBlind = true,
    String? journalEntryId,
  }) async {
    final id = newUuid(random);
    await db
        .into(db.tastingSessions)
        .insert(
          TastingSessionsCompanion.insert(
            id: id,
            tastingGridId: gridId,
            isBlind: Value(isBlind),
            wineJournalEntryId: Value(journalEntryId),
            startedAt: utcNow(_clock),
          ),
        );
    return (await (db.select(
      db.tastingSessions,
    )..where((s) => s.id.equals(id))).getSingle());
  }

  /// Session [id]'s answers: the values chosen for each attribute.
  Stream<Map<String, Set<String>>> watchAnswers(String id) =>
      _answers(id).watch().map(_group);

  Future<Map<String, Set<String>>> answers(String id) async =>
      _group(await _answers(id).get());

  SimpleSelectStatement<TastingDescriptors, TastingDescriptor> _answers(
    String id,
  ) =>
      db.select(db.tastingDescriptors)
        ..where((d) => d.tastingSessionId.equals(id));

  static Map<String, Set<String>> _group(List<TastingDescriptor> rows) {
    final answers = <String, Set<String>>{};
    for (final row in rows) {
      answers.putIfAbsent(row.attributeKey, () => {}).add(row.valueKey);
    }
    return answers;
  }

  /// Replaces the values of [attributeKey] in session [id] with [values].
  /// The database refuses a value of another grid, and a second value for
  /// a single-choice attribute.
  Future<void> choose(String id, String attributeKey, Set<String> values) =>
      db.transaction(() async {
        final session = await _session(id);
        await _clear(id, attributeKey);
        for (final value in values) {
          await _add(session, attributeKey, value);
        }
        await _reopenIfUnanswered(session, attributeKey);
      });

  /// Chooses [valueKey] of [attributeKey] in session [id], or clears it.
  /// Choosing a single choice's value replaces the one before; a multiple
  /// choice adds or removes this value only, so quick taps on several values
  /// never undo one another.
  Future<void> select(
    String id,
    String attributeKey,
    String valueKey, {
    required bool selected,
  }) => db.transaction(() async {
    final session = await _session(id);
    if (!selected) {
      await (db.delete(db.tastingDescriptors)..where(
            (d) =>
                d.tastingSessionId.equals(id) &
                d.attributeKey.equals(attributeKey) &
                d.valueKey.equals(valueKey),
          ))
          .go();
      await _reopenIfUnanswered(session, attributeKey);
      return;
    }
    final attribute = await _attribute(session, attributeKey);
    if (attribute.selection == 'single') await _clear(id, attributeKey);
    await _add(session, attributeKey, valueKey, orIgnore: true);
  });

  Future<TastingSession> _session(String id) => (db.select(
    db.tastingSessions,
  )..where((s) => s.id.equals(id))).getSingle();

  Future<TastingGridAttribute> _attribute(
    TastingSession session,
    String attributeKey,
  ) =>
      (db.select(db.tastingGridAttributes)..where(
            (a) =>
                a.tastingGridId.equals(session.tastingGridId) &
                a.attributeKey.equals(attributeKey),
          ))
          .getSingle();

  Future<void> _clear(String id, String attributeKey) =>
      (db.delete(db.tastingDescriptors)..where(
            (d) =>
                d.tastingSessionId.equals(id) &
                d.attributeKey.equals(attributeKey),
          ))
          .go();

  Future<void> _add(
    TastingSession session,
    String attributeKey,
    String valueKey, {
    bool orIgnore = false,
  }) => db
      .into(db.tastingDescriptors)
      .insert(
        TastingDescriptorsCompanion.insert(
          tastingSessionId: session.id,
          tastingGridId: session.tastingGridId,
          attributeKey: attributeKey,
          valueKey: valueKey,
        ),
        mode: orIgnore ? InsertMode.insertOrIgnore : InsertMode.insert,
      );

  /// A finished tasting whose required [attributeKey] lost its last value
  /// is open again, until the learner finishes it anew.
  Future<void> _reopenIfUnanswered(
    TastingSession session,
    String attributeKey,
  ) async {
    if (session.completedAt == null) return;
    final attribute = await _attribute(session, attributeKey);
    if (!attribute.isRequired) return;
    final left =
        await (db.select(db.tastingDescriptors)..where(
              (d) =>
                  d.tastingSessionId.equals(session.id) &
                  d.attributeKey.equals(attributeKey),
            ))
            .get();
    if (left.isNotEmpty) return;
    await (db.update(db.tastingSessions)..where((s) => s.id.equals(session.id)))
        .write(const TastingSessionsCompanion(completedAt: Value(null)));
  }

  Future<void> setNotes(String id, String? notes) =>
      (db.update(db.tastingSessions)..where((s) => s.id.equals(id))).write(
        TastingSessionsCompanion(
          notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
        ),
      );

  /// Links session [id] to a wine in the journal, or unlinks it.
  Future<void> linkWine(String id, String? journalEntryId) =>
      (db.update(db.tastingSessions)..where((s) => s.id.equals(id))).write(
        TastingSessionsCompanion(wineJournalEntryId: Value(journalEntryId)),
      );

  /// Finishes session [id] when every required attribute has a value;
  /// otherwise returns the attributes still missing and changes nothing.
  Future<List<GridAttribute>> complete(String id) async {
    final session = await (db.select(
      db.tastingSessions,
    )..where((s) => s.id.equals(id))).getSingle();
    final grid = await layout(session.tastingGridId);
    final missing = grid.missing(await answers(id));
    if (missing.isNotEmpty) return missing;
    final now = utcNow(_clock);
    await (db.update(db.tastingSessions)..where((s) => s.id.equals(id))).write(
      TastingSessionsCompanion(
        completedAt: Value(
          now.isBefore(session.startedAt) ? session.startedAt : now,
        ),
      ),
    );
    return const [];
  }

  /// Deletes session [id] and its answers.
  Future<void> delete(String id) =>
      (db.delete(db.tastingSessions)..where((s) => s.id.equals(id))).go();
}
