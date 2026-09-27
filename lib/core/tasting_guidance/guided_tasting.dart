import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';
import '../study/study_planner.dart';
import '../tasting/tasting_practice.dart';
import '../time/utc_clock.dart';

typedef TastingEvidencePrompt = ({String id, String prompt});
typedef TastingEvidenceCriterion = ({String id, String text});
typedef TastingReferenceObservation = ({
  String attributeKey,
  List<String> valueKeys,
  String explanation,
});

final _guidedUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
DateTime _guidedSavedUtc(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid saved tasting timestamp');
  }
  final time = DateTime.tryParse(value);
  if (time == null || !time.isUtc || time.toIso8601String() != value) {
    throw const FormatException(
      'Saved tasting timestamps must use canonical UTC',
    );
  }
  return time;
}

class GuidedTastingLevel {
  GuidedTastingLevel(Map<String, dynamic> row)
    : level = row['level'] as int,
      gridId = row['gridId'] as String,
      evidencePrompts = [
        for (final p in row['evidencePrompts'] as List)
          (id: p['id'] as String, prompt: p['prompt'] as String),
      ] {
    if (level < 1 ||
        level > 3 ||
        gridId != 'tg_guided_wine_l${level}_v1' ||
        evidencePrompts.isEmpty ||
        evidencePrompts.map((p) => p.id).toSet().length !=
            evidencePrompts.length ||
        evidencePrompts.any((p) => p.id.isEmpty || p.prompt.trim().isEmpty)) {
      throw const FormatException('Invalid guided tasting level');
    }
  }
  final int level;
  final String gridId;
  final List<TastingEvidencePrompt> evidencePrompts;
  Map<String, dynamic> toJson() => {
    'level': level,
    'gridId': gridId,
    'evidencePrompts': [
      for (final p in evidencePrompts) {'id': p.id, 'prompt': p.prompt},
    ],
  };
}

class TastingCalibrationCase {
  TastingCalibrationCase(Map<String, dynamic> row)
    : id = row['id'] as String,
      level = row['level'] as int,
      title = row['title'] as String,
      description = row['description'] as String,
      itemIds = List<String>.from(row['itemIds'] as List),
      referenceObservations = [
        for (final r in row['referenceObservations'] as List)
          (
            attributeKey: r['attributeKey'] as String,
            valueKeys: List<String>.from(r['valueKeys'] as List),
            explanation: r['explanation'] as String,
          ),
      ],
      criteria = [
        for (final c in row['criteria'] as List)
          (id: c['id'] as String, text: c['text'] as String),
      ],
      feedback = row['feedback'] as String {
    if (id.isEmpty ||
        level < 1 ||
        level > 3 ||
        title.trim().isEmpty ||
        description.trim().isEmpty ||
        feedback.trim().isEmpty ||
        itemIds.isEmpty ||
        itemIds.toSet().length != itemIds.length ||
        itemIds.any((id) => !RegExp(r'^ki_[a-z0-9_]+$').hasMatch(id)) ||
        referenceObservations.isEmpty ||
        referenceObservations.map((o) => o.attributeKey).toSet().length !=
            referenceObservations.length ||
        referenceObservations.any(
          (o) =>
              o.attributeKey.isEmpty ||
              o.valueKeys.isEmpty ||
              o.valueKeys.toSet().length != o.valueKeys.length ||
              o.explanation.trim().isEmpty,
        ) ||
        criteria.isEmpty ||
        criteria.map((c) => c.id).toSet().length != criteria.length ||
        criteria.any((c) => c.id.isEmpty || c.text.trim().isEmpty)) {
      throw const FormatException('Invalid original tasting calibration case');
    }
  }
  final String id;
  final int level;
  final String title;
  final String description;
  final List<String> itemIds;
  final List<TastingReferenceObservation> referenceObservations;
  final List<TastingEvidenceCriterion> criteria;
  final String feedback;
  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level,
    'title': title,
    'description': description,
    'itemIds': itemIds,
    'referenceObservations': [
      for (final o in referenceObservations)
        {
          'attributeKey': o.attributeKey,
          'valueKeys': o.valueKeys,
          'explanation': o.explanation,
        },
    ],
    'criteria': [
      for (final c in criteria) {'id': c.id, 'text': c.text},
    ],
    'feedback': feedback,
  };
}

class GuidedTastingBank {
  GuidedTastingBank.fromJson(String text) {
    final row = jsonDecode(text) as Map<String, dynamic>;
    if (row['schemaVersion'] != 1) {
      throw const FormatException('Unsupported guided tasting bank');
    }
    version = row['version'] as String;
    levels = [
      for (final l in row['levels'] as List)
        GuidedTastingLevel(Map<String, dynamic>.from(l as Map)),
    ];
    cases = [
      for (final c in row['cases'] as List)
        TastingCalibrationCase(Map<String, dynamic>.from(c as Map)),
    ];
    if (version.trim().isEmpty ||
        levels.length != 3 ||
        levels.map((l) => l.level).toSet().length != 3 ||
        cases.map((c) => c.id).toSet().length != cases.length) {
      throw const FormatException('Invalid guided tasting bank');
    }
  }
  late final String version;
  late final List<GuidedTastingLevel> levels;
  late final List<TastingCalibrationCase> cases;
}

/// Checks saved training references against their original descriptive grid.
/// A reference may name several acceptable values even for a single-choice
/// observation. This validates vocabulary, without requiring current item links
/// or replacing a historical case with the latest authored bank.
void validateCalibrationVocabulary(
  TastingCalibrationCase calibration,
  GridLayout grid,
) {
  for (final reference in calibration.referenceObservations) {
    final attributes = grid.attributes.where(
      (a) => a.key == reference.attributeKey,
    );
    if (attributes.length != 1 ||
        reference.valueKeys.any(
          (key) => !attributes.single.values.any((v) => v.valueKey == key),
        )) {
      throw FormatException(
        'Calibration reference is outside its grid: ${reference.attributeKey}',
      );
    }
  }
}

class GuidedTastingRecord {
  GuidedTastingRecord.fromJson(Map<String, dynamic> row)
    : sessionId = row['sessionId'] as String,
      bankVersion = row['bankVersion'] as String,
      level = GuidedTastingLevel(
        Map<String, dynamic>.from(row['level'] as Map),
      ),
      calibration = row['calibration'] == null
          ? null
          : TastingCalibrationCase(
              Map<String, dynamic>.from(row['calibration'] as Map),
            ),
      evidence = Map<String, String>.from(row['evidence'] as Map),
      completedAt = row['completedAt'] == null
          ? null
          : _guidedSavedUtc(row['completedAt']),
      completedObservations = {
        for (final e in (row['completedObservations'] as Map).entries)
          e.key as String: Set<String>.from(e.value as List),
      },
      selfAssessment = Set<String>.from(row['selfAssessment'] as List) {
    if (row['schemaVersion'] != 1 ||
        !_guidedUuid.hasMatch(sessionId) ||
        bankVersion.trim().isEmpty ||
        (calibration != null && calibration!.level != level.level) ||
        evidence.keys.any(
          (id) => !level.evidencePrompts.any((p) => p.id == id),
        ) ||
        evidence.values.any((text) => text.length > 20000) ||
        (isFinished &&
            level.evidencePrompts.any(
              (p) => (evidence[p.id] ?? '').trim().isEmpty,
            )) ||
        selfAssessment.any(
          (id) => !(calibration?.criteria.any((c) => c.id == id) ?? false),
        ) ||
        (!isFinished &&
            (completedObservations.isNotEmpty || selfAssessment.isNotEmpty))) {
      throw const FormatException('Invalid saved guided tasting');
    }
  }
  final String sessionId;
  final String bankVersion;
  final GuidedTastingLevel level;
  final TastingCalibrationCase? calibration;
  final Map<String, String> evidence;
  final DateTime? completedAt;
  final Map<String, Set<String>> completedObservations;
  final Set<String> selfAssessment;
  bool get isFinished => completedAt != null;
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'bankVersion': bankVersion,
    'level': level.toJson(),
    'calibration': calibration?.toJson(),
    'evidence': evidence,
    'completedAt': completedAt?.toIso8601String(),
    'completedObservations': {
      for (final e in completedObservations.entries) e.key: e.value.toList(),
    },
    'selfAssessment': selfAssessment.toList(),
  };
}

/// Saves observations in legacy tasting tables and original evidence in
/// backed-up settings. Unknown physical wines receive no objective grade.
class GuidedTastingRepository {
  GuidedTastingRepository(
    this.db, {
    required this.bank,
    Clock? clock,
    TastingPractice? practice,
  }) : clock = clock ?? const Clock(),
       practice = practice ?? TastingPractice(db, clock: clock);
  final AppDatabase db;
  final GuidedTastingBank bank;
  final Clock clock;
  final TastingPractice practice;
  static const currentKey = 'guided_tasting_current_v1';
  static const recordPrefix = 'guided_tasting_record_v1_';
  String _recordKey(String id) => '$recordPrefix${id.replaceAll('-', '_')}';

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

  Future<void> _save(GuidedTastingRecord record) =>
      _put(_recordKey(record.sessionId), jsonEncode(record.toJson()));
  Future<TastingSession> session(String id) => (db.select(
    db.tastingSessions,
  )..where((s) => s.id.equals(id))).getSingle();
  Future<GuidedTastingRecord> _load(String id) async {
    if (!_guidedUuid.hasMatch(id)) {
      throw const FormatException('Invalid saved guided tasting ID');
    }
    final text = await _setting(_recordKey(id));
    if (text == null) throw StateError('Saved guided tasting was not found.');
    var record = GuidedTastingRecord.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
    if (record.sessionId != id) {
      throw const FormatException(
        'Saved guided tasting identity does not match its key',
      );
    }
    final savedSession = await session(id);
    if (record.completedAt != null &&
        record.completedAt!.isBefore(savedSession.startedAt)) {
      throw const FormatException(
        'Saved guided tasting finishes before it starts',
      );
    }
    if (savedSession.tastingGridId != record.level.gridId) {
      throw const FormatException(
        'Guided tasting grid does not match its saved session',
      );
    }
    if (record.calibration case final calibration?) {
      validateCalibrationVocabulary(
        calibration,
        await practice.layout(record.level.gridId),
      );
    }
    final observations = await practice.answers(id);
    bool same() =>
        record.completedObservations.length == observations.length &&
        record.completedObservations.entries.every(
          (e) =>
              observations[e.key]?.length == e.value.length &&
              e.value.every((v) => observations[e.key]!.contains(v)),
        );
    if (record.isFinished &&
        (savedSession.completedAt != record.completedAt || !same())) {
      record = GuidedTastingRecord.fromJson({
        ...record.toJson(),
        'completedAt': null,
        'completedObservations': <String, List<String>>{},
        'selfAssessment': <String>[],
      });
      await _save(record);
    }
    return record;
  }

  Future<GuidedTastingRecord?> current() => db.transaction(() async {
    final id = await _setting(currentKey);
    return id == null ? null : _load(id);
  });
  Future<GuidedTastingRecord> read(String id) =>
      db.transaction(() => _load(id));
  Future<GuidedTastingRecord> resume(String id) => db.transaction(() async {
    final record = await _load(id);
    final previous = await _setting(currentKey);
    if (previous != null &&
        previous != id &&
        !(await _load(previous)).isFinished) {
      throw StateError(
        'Leave the current guided draft before resuming another.',
      );
    }
    await _put(currentKey, id);
    return record;
  });
  Future<GridLayout> layout(GuidedTastingRecord record) =>
      practice.layout(record.level.gridId);
  Future<Map<String, Set<String>>> observations(GuidedTastingRecord record) =>
      practice.answers(record.sessionId);

  Future<void> _validateCase(
    TastingCalibrationCase calibration,
    GridLayout grid,
  ) async {
    validateCalibrationVocabulary(calibration, grid);
    final mappings = await StudyPlanner(
      db,
      clock: clock,
    ).effectiveMappings('WSET_L${calibration.level}');
    final current = {
      for (final item in await KnowledgeGraph(db, clock: clock).currentItems())
        item.id,
    };
    if (!calibration.itemIds.every(
      (id) => mappings.containsKey(id) && current.contains(id),
    )) {
      throw StateError(
        'This calibration case is not currently available for the selected study level.',
      );
    }
  }

  Future<GuidedTastingRecord> start(
    int level, {
    String? caseId,
    String? journalEntryId,
    bool makeCurrent = true,
  }) => db.transaction(() async {
    final definition = bank.levels.singleWhere((l) => l.level == level);
    final profile = await (db.select(
      db.userProfiles,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (profile?.activeCertificationId != 'WSET_L$level') {
      throw StateError('Choose WSET Level $level as your study track first.');
    }
    if (makeCurrent) {
      final previous = await _setting(currentKey);
      if (previous != null && !(await _load(previous)).isFinished) {
        throw StateError('Finish or leave the saved guided tasting first.');
      }
    }
    final grid = await practice.layout(definition.gridId);
    final calibration = caseId == null
        ? null
        : bank.cases.singleWhere((c) => c.id == caseId && c.level == level);
    if (calibration != null) await _validateCase(calibration, grid);
    final tasting = await practice.start(
      definition.gridId,
      isBlind: calibration == null,
      journalEntryId: journalEntryId,
    );
    final record = GuidedTastingRecord.fromJson({
      'schemaVersion': 1,
      'sessionId': tasting.id,
      'bankVersion': bank.version,
      'level': definition.toJson(),
      'calibration': calibration?.toJson(),
      'evidence': <String, String>{},
      'completedAt': null,
      'completedObservations': <String, List<String>>{},
      'selfAssessment': <String>[],
    });
    await _save(record);
    if (makeCurrent) await _put(currentKey, record.sessionId);
    return record;
  });

  Future<GuidedTastingRecord> choose(
    String id,
    String attributeKey,
    Set<String> values,
  ) => db.transaction(() async {
    final record = await _load(id);
    if (record.isFinished) throw StateError('This guided tasting is finished.');
    await practice.choose(id, attributeKey, values);
    return record;
  });
  Future<GuidedTastingRecord> evidence(
    String id,
    String promptId,
    String text,
  ) => db.transaction(() async {
    final record = await _load(id);
    if (record.isFinished) throw StateError('This guided tasting is finished.');
    if (text.length > 20000) {
      throw ArgumentError('Tasting evidence is too long.');
    }
    final row = jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;
    (row['evidence'] as Map)[promptId] = text;
    final changed = GuidedTastingRecord.fromJson(row);
    await _save(changed);
    return changed;
  });
  Future<GuidedTastingRecord> finish(String id) => db.transaction(() async {
    var record = await _load(id);
    if (record.isFinished) return record;
    if (record.level.evidencePrompts.any(
      (p) => (record.evidence[p.id] ?? '').trim().isEmpty,
    )) {
      throw StateError(
        'Write evidence for every guided prompt before finishing.',
      );
    }
    final missing = await practice.complete(id);
    if (missing.isNotEmpty) {
      throw StateError(
        'Complete the required observations: ${missing.map((a) => a.attribute.label).join(', ')}.',
      );
    }
    final tasting = await session(id);
    final observations = await practice.answers(id);
    record = GuidedTastingRecord.fromJson({
      ...record.toJson(),
      'completedAt': tasting.completedAt!.toIso8601String(),
      'completedObservations': {
        for (final e in observations.entries) e.key: e.value.toList(),
      },
    });
    await _save(record);
    return record;
  });
  Future<GuidedTastingRecord> selfAssess(String id, Set<String> criteria) =>
      db.transaction(() async {
        final record = await _load(id);
        if (!record.isFinished || record.calibration == null) {
          throw StateError(
            'Finish an original calibration case before checking its criteria.',
          );
        }
        final changed = GuidedTastingRecord.fromJson({
          ...record.toJson(),
          'selfAssessment': criteria.toList(),
        });
        await _save(changed);
        return changed;
      });
  Future<List<GuidedTastingRecord>> history() async =>
      (await historyWithDiagnostics()).entries;

  Future<({List<GuidedTastingRecord> entries, int unreadableCount})>
  historyWithDiagnostics() => db.transaction(() async {
    final rows = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$recordPrefix%'))).get();
    final entries = <GuidedTastingRecord>[];
    var unreadableCount = 0;
    for (final row in rows) {
      if (!row.name.startsWith(recordPrefix)) continue;
      try {
        entries.add(
          await _load(
            row.name.substring(recordPrefix.length).replaceAll('_', '-'),
          ),
        );
      } catch (error) {
        if (error is! FormatException &&
            error is! TypeError &&
            error is! StateError &&
            error is! ArgumentError) {
          rethrow;
        }
        unreadableCount++;
      }
    }
    return (entries: entries, unreadableCount: unreadableCount);
  });

  /// Leave the selection; observations and evidence remain in saved history.
  Future<void> leaveCurrent() async {
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.equals(currentKey))).go();
  }
}
