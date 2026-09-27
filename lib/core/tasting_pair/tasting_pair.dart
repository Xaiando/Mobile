import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../tasting/tasting_practice.dart';
import '../tasting_guidance/guided_tasting.dart';
import '../time/utc_clock.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
DateTime _utc(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid paired tasting timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException(
      'Paired tasting timestamps must use canonical UTC',
    );
  }
  return parsed;
}

typedef PairObservationValue = ({String key, String label});

/// Original grid wording is snapshotted rather than read from a later release.
class PairObservationAttribute {
  PairObservationAttribute.fromJson(Map<String, dynamic> row)
    : key = row['key'] as String,
      label = row['label'] as String,
      section = row['section'] as String,
      isRequired = row['isRequired'] as bool,
      isSingle = row['isSingle'] as bool,
      values = [
        for (final value in row['values'] as List)
          (key: value['key'] as String, label: value['label'] as String),
      ] {
    if (key.isEmpty ||
        label.trim().isEmpty ||
        section.trim().isEmpty ||
        values.isEmpty ||
        values.map((v) => v.key).toSet().length != values.length ||
        values.any((v) => v.key.isEmpty || v.label.trim().isEmpty)) {
      throw const FormatException(
        'Invalid paired tasting observation vocabulary',
      );
    }
  }
  final String key;
  final String label;
  final String section;
  final bool isRequired;
  final bool isSingle;
  final List<PairObservationValue> values;
  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'section': section,
    'isRequired': isRequired,
    'isSingle': isSingle,
    'values': [
      for (final value in values) {'key': value.key, 'label': value.label},
    ],
  };
  static PairObservationAttribute fromGrid(GridAttribute attribute) =>
      PairObservationAttribute.fromJson({
        'key': attribute.key,
        'label': attribute.attribute.label,
        'section': attribute.attribute.section,
        'isRequired': attribute.attribute.isRequired,
        'isSingle': attribute.isSingle,
        'values': [
          for (final value in attribute.values)
            {'key': value.valueKey, 'label': value.label},
        ],
      });
}

class TastingPairWine {
  TastingPairWine.fromJson(Map<String, dynamic> row)
    : sessionId = row['sessionId'] as String,
      bankVersion = row['bankVersion'] as String,
      level = GuidedTastingLevel(
        Map<String, dynamic>.from(row['level'] as Map),
      ),
      attributes = [
        for (final a in row['attributes'] as List)
          PairObservationAttribute.fromJson(
            Map<String, dynamic>.from(a as Map),
          ),
      ],
      observations = {
        for (final e in (row['observations'] as Map).entries)
          e.key as String: Set<String>.from(e.value as List),
      },
      evidence = Map<String, String>.from(row['evidence'] as Map) {
    if (!_uuid.hasMatch(sessionId) ||
        bankVersion.trim().isEmpty ||
        level.level != 3 ||
        attributes.isEmpty ||
        attributes.map((a) => a.key).toSet().length != attributes.length ||
        evidence.entries.any(
          (e) =>
              !level.evidencePrompts.any((p) => p.id == e.key) ||
              e.value.length > 20000,
        ) ||
        observations.entries.any(
          (e) => !attributes.any(
            (a) =>
                a.key == e.key &&
                (!a.isSingle || e.value.length <= 1) &&
                e.value.every((v) => a.values.any((option) => option.key == v)),
          ),
        ) ||
        (row['observations'] as Map).values.any(
          (v) => (v as List).toSet().length != v.length,
        )) {
      throw const FormatException('Invalid saved paired wine');
    }
  }
  final String sessionId;
  final String bankVersion;
  final GuidedTastingLevel level;
  final List<PairObservationAttribute> attributes;
  final Map<String, Set<String>> observations;
  final Map<String, String> evidence;
  List<PairObservationAttribute> get missingObservations => [
    for (final a in attributes)
      if (a.isRequired && (observations[a.key] ?? const <String>{}).isEmpty) a,
  ];
  List<TastingEvidencePrompt> get missingEvidence => [
    for (final p in level.evidencePrompts)
      if ((evidence[p.id] ?? '').trim().isEmpty) p,
  ];
  bool get isComplete => missingObservations.isEmpty && missingEvidence.isEmpty;
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'bankVersion': bankVersion,
    'level': level.toJson(),
    'attributes': [for (final a in attributes) a.toJson()],
    'observations': {
      for (final e in observations.entries) e.key: e.value.toList(),
    },
    'evidence': evidence,
  };
}

/// A separate timed exercise; it does not assert objective quality or a pass.
class TastingPairAttempt {
  TastingPairAttempt.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      startedAt = _utc(row['startedAt']),
      deadline = _utc(row['deadline']),
      completedAt = row['completedAt'] == null
          ? null
          : _utc(row['completedAt']),
      finishReason = row['finishReason'] as String?,
      wines = [
        for (final wine in row['wines'] as List)
          TastingPairWine.fromJson(Map<String, dynamic>.from(wine as Map)),
      ] {
    if (row['schemaVersion'] != 1 ||
        !_uuid.hasMatch(id) ||
        wines.length != 2 ||
        wines.map((w) => w.sessionId).toSet().length != 2 ||
        deadline.difference(startedAt) != const Duration(minutes: 30) ||
        (completedAt == null) != (finishReason == null) ||
        (finishReason != null &&
            !const {
              'submitted',
              'expired',
              'abandoned',
            }.contains(finishReason)) ||
        (completedAt != null &&
            (completedAt!.isBefore(startedAt) ||
                completedAt!.isAfter(deadline))) ||
        (finishReason == 'expired' && completedAt != deadline)) {
      throw const FormatException('Invalid saved paired tasting attempt');
    }
  }
  final String id;
  final DateTime startedAt;
  final DateTime deadline;
  final DateTime? completedAt;
  final String? finishReason;
  final List<TastingPairWine> wines;
  int get level => 3;
  bool get isFinished => completedAt != null;
  bool get abandoned => finishReason == 'abandoned';
  int get completeWineCount => wines.where((w) => w.isComplete).length;
  Duration remaining(DateTime now) {
    final utc = now.toUtc();
    final left = deadline.difference(utc.isBefore(startedAt) ? startedAt : utc);
    return isFinished || left.isNegative ? Duration.zero : left;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'finishReason': finishReason,
    'wines': [for (final wine in wines) wine.toJson()],
  };
}

/// Pair snapshots are authoritative for the timed exercise. The linked legacy
/// observations remain useful in the recorder, but later edits cannot rewrite
/// these saved answers or import observations made after the deadline.
class TastingPairRepository {
  TastingPairRepository(
    this.db, {
    required this.guidance,
    Clock? clock,
    Random? random,
  }) : clock = clock ?? const Clock(),
       random = random ?? Random.secure() {
    if (!identical(guidance.db, db)) {
      throw ArgumentError('Paired and guided tasting must share one database.');
    }
  }
  final AppDatabase db;
  final GuidedTastingRepository guidance;
  final Clock clock;
  final Random random;
  static const currentKey = 'wset_tasting_pair_current_v1';
  static const attemptPrefix = 'wset_tasting_pair_attempt_v1_';
  static String _key(String id) => '$attemptPrefix${id.replaceAll('-', '_')}';
  Future<String?> _setting(String name) async => (await (db.select(
    db.userSettings,
  )..where((s) => s.name.equals(name))).getSingleOrNull())?.value;
  Future<void> _put(String name, String value) async {
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(name: name, value: value, updatedAt: utcNow(clock)),
        );
  }

  Future<void> _save(TastingPairAttempt attempt) =>
      _put(_key(attempt.id), jsonEncode(attempt.toJson()));
  Future<TastingPairAttempt> _load(String id) async {
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid paired tasting selection');
    }
    final text = await _setting(_key(id));
    if (text == null) throw StateError('Saved paired tasting was not found.');
    final attempt = TastingPairAttempt.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
    if (attempt.id != id) {
      throw const FormatException(
        'Paired tasting identity does not match its saved selection',
      );
    }
    return attempt;
  }

  TastingPairAttempt _finished(TastingPairAttempt attempt, String reason) {
    final now = utcNow(clock);
    final expired = reason == 'expired' || !now.isBefore(attempt.deadline);
    return TastingPairAttempt.fromJson({
      ...attempt.toJson(),
      'completedAt':
          (expired
                  ? attempt.deadline
                  : now.isBefore(attempt.startedAt)
                  ? attempt.startedAt
                  : now)
              .toIso8601String(),
      'finishReason': expired ? 'expired' : reason,
    });
  }

  Future<TastingPairAttempt> _expire(TastingPairAttempt attempt) async {
    if (!attempt.isFinished && !utcNow(clock).isBefore(attempt.deadline)) {
      attempt = _finished(attempt, 'expired');
      await _save(attempt);
    }
    return attempt;
  }

  Future<TastingPairAttempt?> current() => db.transaction(() async {
    final id = await _setting(currentKey);
    return id == null ? null : _expire(await _load(id));
  });
  Future<TastingPairAttempt> read(String id) =>
      db.transaction(() async => _expire(await _load(id)));
  Future<TastingPairAttempt> resume(String id) => db.transaction(() async {
    final attempt = await _expire(await _load(id));
    if (!attempt.isFinished) {
      final currentId = await _setting(currentKey);
      if (currentId != null &&
          currentId != id &&
          !(await _expire(await _load(currentId))).isFinished) {
        throw StateError('End or resume the other saved pair first.');
      }
      await _put(currentKey, id);
    }
    return attempt;
  });
  Future<TastingPairAttempt> start({List<String?>? journalEntryIds}) =>
      db.transaction(() async {
        if (journalEntryIds != null && journalEntryIds.length != 2) {
          throw ArgumentError('A pair needs exactly two journal links.');
        }
        final currentId = await _setting(currentKey);
        if (currentId != null &&
            !(await _expire(await _load(currentId))).isFinished) {
          throw StateError('Resume or end the saved paired tasting first.');
        }
        final profile = await (db.select(
          db.userProfiles,
        )..where((p) => p.id.equals(1))).getSingleOrNull();
        if (profile?.activeCertificationId != 'WSET_L3') {
          throw StateError('Choose WSET Level 3 as your study track first.');
        }
        final started = utcNow(clock);
        final wines = <TastingPairWine>[];
        for (var index = 0; index < 2; index++) {
          final record = await guidance.startDetachedInTransaction(
            3,
            journalEntryId: journalEntryIds?[index],
          );
          final grid = await guidance.layout(record);
          wines.add(
            TastingPairWine.fromJson({
              'sessionId': record.sessionId,
              'bankVersion': record.bankVersion,
              'level': record.level.toJson(),
              'attributes': [
                for (final a in grid.attributes)
                  PairObservationAttribute.fromGrid(a).toJson(),
              ],
              'observations': <String, List<String>>{},
              'evidence': <String, String>{},
            }),
          );
        }
        var id = newUuid(random);
        while (await _setting(_key(id)) != null) {
          id = newUuid(random);
        }
        final attempt = TastingPairAttempt.fromJson({
          'schemaVersion': 1,
          'id': id,
          'startedAt': started.toIso8601String(),
          'deadline': started
              .add(const Duration(minutes: 30))
              .toIso8601String(),
          'completedAt': null,
          'finishReason': null,
          'wines': [for (final wine in wines) wine.toJson()],
        });
        await _save(attempt);
        await _put(currentKey, id);
        return attempt;
      });

  Future<TastingPairAttempt> _change(
    String id,
    String sessionId,
    Future<void> Function(Map<String, dynamic> wine) mutate,
  ) async {
    // Commit expiry before reporting a rejected late answer; throwing inside
    // the transaction would otherwise roll that finalization back.
    final result = await db.transaction(() async {
      var attempt = await _expire(await _load(id));
      if (attempt.isFinished) return (attempt: attempt, ended: true);
      final index = attempt.wines.indexWhere((w) => w.sessionId == sessionId);
      if (index == -1) {
        throw ArgumentError('This wine does not belong to the saved pair.');
      }
      final row =
          jsonDecode(jsonEncode(attempt.toJson())) as Map<String, dynamic>;
      await mutate(row['wines'][index] as Map<String, dynamic>);
      attempt = TastingPairAttempt.fromJson(row);
      attempt = await _expire(attempt);
      await _save(attempt);
      return (attempt: attempt, ended: false);
    });
    if (result.ended) throw StateError('This paired tasting has ended.');
    return result.attempt;
  }

  Future<TastingPairAttempt> choose(
    String id,
    String sessionId,
    String attributeKey,
    Set<String> values,
  ) => _change(id, sessionId, (wine) async {
    (wine['observations'] as Map)[attributeKey] = values.toList();
    // Validate against the original snapshot before touching legacy tables.
    TastingPairWine.fromJson(wine);
    await guidance.chooseInTransaction(sessionId, attributeKey, values);
  });
  Future<TastingPairAttempt> evidence(
    String id,
    String sessionId,
    String promptId,
    String text,
  ) => _change(id, sessionId, (wine) async {
    (wine['evidence'] as Map)[promptId] = text;
    TastingPairWine.fromJson(wine);
    await guidance.evidenceInTransaction(sessionId, promptId, text);
  });
  Future<TastingPairAttempt> finish(String id) => db.transaction(() async {
    var attempt = await _expire(await _load(id));
    if (!attempt.isFinished) {
      attempt = _finished(attempt, 'submitted');
      await _save(attempt);
    }
    return attempt;
  });
  Future<List<TastingPairAttempt>> history() async =>
      (await historyWithDiagnostics()).entries;

  Future<({List<TastingPairAttempt> entries, int unreadableCount})>
  historyWithDiagnostics() => db.transaction(() async {
    final rows = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$attemptPrefix%'))).get();
    final attempts = <TastingPairAttempt>[];
    var unreadableCount = 0;
    for (final row in rows) {
      if (!row.name.startsWith(attemptPrefix)) continue;
      TastingPairAttempt attempt;
      try {
        attempt = TastingPairAttempt.fromJson(
          jsonDecode(row.value) as Map<String, dynamic>,
        );
        if (_key(attempt.id) != row.name) {
          throw const FormatException(
            'Paired tasting history identity does not match its key',
          );
        }
      } catch (error) {
        if (error is! FormatException &&
            error is! TypeError &&
            error is! StateError &&
            error is! ArgumentError) {
          rethrow;
        }
        unreadableCount++;
        continue;
      }
      attempts.add(await _expire(attempt));
    }
    attempts.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (entries: attempts, unreadableCount: unreadableCount);
  });
  Future<void> discardCurrent() => db.transaction(() async {
    final id = await _setting(currentKey);
    if (id != null) {
      final attempt = await _expire(await _load(id));
      if (!attempt.isFinished) await _save(_finished(attempt, 'abandoned'));
    }
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.equals(currentKey))).go();
  });

  /// Clear a corrupt selection only; preserve all saved attempt bytes.
  Future<void> resetCurrentPointer() async {
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.equals(currentKey))).go();
  }
}
