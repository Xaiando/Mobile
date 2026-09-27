import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';
import '../database/uuid.dart';
import '../study/study_planner.dart';
import '../time/utc_clock.dart';

typedef RehearsalOption = ({String id, String text});

final _rehearsalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

DateTime _savedUtc(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid saved practice timestamp');
  }
  final time = DateTime.tryParse(value);
  if (time == null || !time.isUtc || time.toIso8601String() != value) {
    throw const FormatException(
      'Saved practice timestamps must use canonical UTC',
    );
  }
  return time;
}

Duration _rehearsalDuration(int level) => Duration(
  seconds: switch (level) {
    1 => 2700,
    2 => 3600,
    _ => 7200,
  },
);

class RehearsalMcq {
  RehearsalMcq(Map<String, dynamic> row)
    : id = row['id'] as String,
      prompt = row['prompt'] as String,
      levels = List<int>.from(row['levels'] as List),
      itemIds = List<String>.from(row['itemIds'] as List),
      options = [
        for (final option in row['options'] as List)
          (id: option['id'] as String, text: option['text'] as String),
      ],
      correctOptionId = row['correctOptionId'] as String,
      explanation = row['explanation'] as String,
      blueprintByLevel = Map<String, String>.from(
        row['blueprintByLevel'] as Map? ?? const {},
      ) {
    if (id.isEmpty ||
        prompt.trim().isEmpty ||
        explanation.trim().isEmpty ||
        options.length < 2 ||
        options.map((o) => o.id).toSet().length != options.length ||
        options.any((o) => o.id.isEmpty || o.text.trim().isEmpty) ||
        !options.any((o) => o.id == correctOptionId)) {
      throw const FormatException('Invalid rehearsal multiple-choice question');
    }
    _validateLinks(levels, itemIds);
    if (blueprintByLevel.entries.any(
      (e) =>
          !levels.any((level) => '$level' == e.key) || e.value.trim().isEmpty,
    )) {
      throw const FormatException('Invalid rehearsal question blueprint');
    }
  }

  final String id;
  final String prompt;
  final List<int> levels;
  final List<String> itemIds;
  final List<RehearsalOption> options;
  final String correctOptionId;
  final String explanation;
  final Map<String, String> blueprintByLevel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'levels': levels,
    'itemIds': itemIds,
    'options': [
      for (final o in options) {'id': o.id, 'text': o.text},
    ],
    'correctOptionId': correctOptionId,
    'explanation': explanation,
    'blueprintByLevel': blueprintByLevel,
  };
}

class RehearsalCriterion {
  RehearsalCriterion(Map<String, dynamic> row)
    : id = row['id'] as String,
      text = row['text'] as String,
      itemIds = List<String>.from(row['itemIds'] as List) {
    if (id.isEmpty || text.trim().isEmpty) {
      throw const FormatException('Invalid written rehearsal criterion');
    }
    _validateLinks([3], itemIds);
  }
  final String id;
  final String text;
  final List<String> itemIds;
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'itemIds': itemIds};
}

class RehearsalWritten {
  RehearsalWritten(Map<String, dynamic> row)
    : id = row['id'] as String,
      prompt = row['prompt'] as String,
      levels = List<int>.from(row['levels'] as List),
      criteria = [
        for (final c in row['criteria'] as List)
          RehearsalCriterion(Map<String, dynamic>.from(c as Map)),
      ] {
    if (id.isEmpty ||
        prompt.trim().isEmpty ||
        levels.length != 1 ||
        levels.single != 3 ||
        criteria.isEmpty ||
        criteria.map((c) => c.id).toSet().length != criteria.length) {
      throw const FormatException('Invalid written rehearsal question');
    }
  }
  final String id;
  final String prompt;
  final List<int> levels;
  final List<RehearsalCriterion> criteria;
  Set<String> get itemIds => {for (final c in criteria) ...c.itemIds};
  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'levels': levels,
    'criteria': [for (final c in criteria) c.toJson()],
  };
}

void _validateLinks(List<int> levels, List<String> itemIds) {
  if (levels.isEmpty ||
      levels.any((v) => v < 1 || v > 3) ||
      levels.toSet().length != levels.length ||
      itemIds.isEmpty ||
      itemIds.toSet().length != itemIds.length ||
      itemIds.any((id) => !RegExp(r'^ki_[a-z0-9_]+$').hasMatch(id))) {
    throw const FormatException('Invalid rehearsal level or fact links');
  }
}

class RehearsalPreset {
  const RehearsalPreset(
    this.level,
    this.mcqCount,
    this.writtenCount,
    this.durationSeconds, {
    this.blueprint = const {},
  });
  final int level;
  final int mcqCount;
  final int writtenCount;
  final int durationSeconds;
  final Map<String, int> blueprint;
}

class RehearsalBank {
  RehearsalBank.fromJson(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported rehearsal bank');
    }
    version = json['version'] as String;
    if (version.trim().isEmpty) {
      throw const FormatException('Missing rehearsal bank version');
    }
    presets = [
      for (final row in json['levels'] as List)
        RehearsalPreset(
          row['level'] as int,
          row['mcqCount'] as int,
          row['writtenCount'] as int,
          row['durationSeconds'] as int,
          blueprint: Map<String, int>.from(
            row['blueprint'] as Map? ?? const {},
          ),
        ),
    ];
    if (presets.length != 3 ||
        presets.map((p) => p.level).toSet().length != 3 ||
        presets.any(
          (p) =>
              p.level < 1 ||
              p.level > 3 ||
              p.mcqCount != (p.level == 1 ? 30 : 50) ||
              p.writtenCount != (p.level == 3 ? 4 : 0) ||
              p.durationSeconds !=
                  switch (p.level) {
                    1 => 2700,
                    2 => 3600,
                    _ => 7200,
                  },
        )) {
      throw const FormatException('Invalid WSET practice preset');
    }
    if (presets.any(
      (p) =>
          p.blueprint.isNotEmpty &&
          (p.blueprint.entries.any(
                (e) => e.key.trim().isEmpty || e.value <= 0,
              ) ||
              p.blueprint.values.fold(0, (int sum, value) => sum + value) !=
                  p.mcqCount),
    )) {
      throw const FormatException('Invalid rehearsal blueprint counts');
    }
    mcqs = [
      for (final row in json['mcqs'] as List)
        RehearsalMcq(Map<String, dynamic>.from(row as Map)),
    ];
    written = [
      for (final row in json['written'] as List)
        RehearsalWritten(Map<String, dynamic>.from(row as Map)),
    ];
    final ids = [...mcqs.map((q) => q.id), ...written.map((q) => q.id)];
    if (ids.toSet().length != ids.length) {
      throw const FormatException('Duplicate rehearsal question ID');
    }
  }
  late final String version;
  late final List<RehearsalPreset> presets;
  late final List<RehearsalMcq> mcqs;
  late final List<RehearsalWritten> written;
}

/// An attempt owns a snapshot: later bank changes cannot rewrite its marking.
class RehearsalAttempt {
  RehearsalAttempt.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      level = row['level'] as int,
      bankVersion = row['bankVersion'] as String,
      startedAt = _savedUtc(row['startedAt']),
      deadline = _savedUtc(row['deadline']),
      completedAt = row['completedAt'] == null
          ? null
          : _savedUtc(row['completedAt']),
      finishReason = row['finishReason'] as String?,
      mcqs = [
        for (final q in row['mcqs'] as List)
          RehearsalMcq(Map<String, dynamic>.from(q as Map)),
      ],
      written = [
        for (final q in row['written'] as List)
          RehearsalWritten(Map<String, dynamic>.from(q as Map)),
      ],
      answers = Map<String, String>.from(row['answers'] as Map),
      prose = Map<String, String>.from(row['prose'] as Map),
      selfAssessment = {
        for (final entry in (row['selfAssessment'] as Map).entries)
          entry.key as String: Set<String>.from(entry.value as List),
      } {
    if (row['schemaVersion'] != 1 ||
        !_rehearsalUuid.hasMatch(id) ||
        bankVersion.trim().isEmpty ||
        level < 1 ||
        level > 3 ||
        mcqs.length != (level == 1 ? 30 : 50) ||
        written.length != (level == 3 ? 4 : 0) ||
        mcqs.any((q) => !q.levels.contains(level)) ||
        written.any((q) => !q.levels.contains(level)) ||
        deadline.difference(startedAt) != _rehearsalDuration(level) ||
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
        (finishReason == 'expired' && completedAt != deadline) ||
        mcqs.map((q) => q.id).toSet().length != mcqs.length ||
        written.map((q) => q.id).toSet().length != written.length ||
        answers.entries.any(
          (e) => !mcqs.any(
            (q) => q.id == e.key && q.options.any((o) => o.id == e.value),
          ),
        ) ||
        prose.entries.any(
          (e) => !written.any((q) => q.id == e.key) || e.value.length > 20000,
        ) ||
        selfAssessment.entries.any(
          (e) => !written.any(
            (q) =>
                q.id == e.key &&
                e.value.every((id) => q.criteria.any((c) => c.id == id)),
          ),
        ) ||
        selfAssessment.entries.any(
          (e) => e.value.isNotEmpty && (prose[e.key] ?? '').trim().isEmpty,
        ) ||
        (!isFinished && selfAssessment.isNotEmpty)) {
      throw const FormatException('Invalid saved rehearsal attempt');
    }
  }

  final String id;
  final int level;
  final String bankVersion;
  final DateTime startedAt;
  final DateTime deadline;
  final DateTime? completedAt;
  final String? finishReason;
  final List<RehearsalMcq> mcqs;
  final List<RehearsalWritten> written;
  final Map<String, String> answers;
  final Map<String, String> prose;
  final Map<String, Set<String>> selfAssessment;
  bool get isFinished => completedAt != null;
  bool get abandoned => finishReason == 'abandoned';
  int get mcqCorrect =>
      mcqs.where((q) => answers[q.id] == q.correctOptionId).length;
  Duration remaining(DateTime now) {
    final effective = now.toUtc().isBefore(startedAt) ? startedAt : now.toUtc();
    final duration = deadline.difference(effective);
    return duration.isNegative || isFinished ? Duration.zero : duration;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'level': level,
    'bankVersion': bankVersion,
    'startedAt': startedAt.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'finishReason': finishReason,
    'mcqs': [for (final q in mcqs) q.toJson()],
    'written': [for (final q in written) q.toJson()],
    'answers': answers,
    'prose': prose,
    'selfAssessment': {
      for (final e in selfAssessment.entries) e.key: e.value.toList(),
    },
  };
}

/// Timed original practice, persisted in backed-up settings. No official marks
/// or automatic FSRS credit: multi-fact answers do not establish fact mastery.
class RehearsalRepository {
  RehearsalRepository(
    this.db, {
    required this.bank,
    Clock? clock,
    Random? random,
  }) : clock = clock ?? const Clock(),
       random = random ?? Random.secure();
  final AppDatabase db;
  final RehearsalBank bank;
  final Clock clock;
  final Random random;
  static const currentKey = 'wset_rehearsal_current_v1';
  static const attemptPrefix = 'wset_rehearsal_attempt_v1_';
  static String _attemptKey(String id) =>
      '$attemptPrefix${id.replaceAll('-', '_')}';

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

  Future<void> _save(RehearsalAttempt attempt) =>
      _put(_attemptKey(attempt.id), jsonEncode(attempt.toJson()));
  Future<RehearsalAttempt> _load(String id) async {
    if (!_rehearsalUuid.hasMatch(id)) {
      throw const FormatException('Invalid saved practice selection');
    }
    final text = await _setting(_attemptKey(id));
    if (text == null) throw StateError('Saved practice attempt was not found.');
    final attempt = RehearsalAttempt.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
    if (attempt.id != id) {
      throw const FormatException(
        'Saved practice identity does not match its selection',
      );
    }
    return attempt;
  }

  RehearsalAttempt _finished(RehearsalAttempt attempt, String reason) {
    final now = utcNow(clock);
    final expired = reason == 'expired' || !now.isBefore(attempt.deadline);
    return RehearsalAttempt.fromJson({
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

  Future<RehearsalAttempt> _expire(RehearsalAttempt attempt) async {
    if (!attempt.isFinished && !utcNow(clock).isBefore(attempt.deadline)) {
      attempt = _finished(attempt, 'expired');
      await _save(attempt);
    }
    return attempt;
  }

  Future<RehearsalAttempt?> current() => db.transaction(() async {
    final id = await _setting(currentKey);
    return id == null ? null : _expire(await _load(id));
  });

  /// Read a saved snapshot, committing any elapsed deadline before returning it.
  Future<RehearsalAttempt> read(String id) =>
      db.transaction(() async => _expire(await _load(id)));

  /// Select an unfinished historical draft without hiding another active timer.
  /// Finished history can be viewed without replacing the selected draft.
  Future<RehearsalAttempt> resume(String id) => db.transaction(() async {
    final attempt = await _expire(await _load(id));
    if (!attempt.isFinished) {
      final currentId = await _setting(currentKey);
      if (currentId != null &&
          currentId != id &&
          !(await _expire(await _load(currentId))).isFinished) {
        throw StateError('Resume or end the selected practice attempt first.');
      }
      await _put(currentKey, id);
    }
    return attempt;
  });

  Future<RehearsalAttempt> start(int level) => db.transaction(() async {
    if (level < 1 || level > 3) throw ArgumentError.value(level, 'level');
    final currentId = await _setting(currentKey);
    if (currentId != null &&
        !(await _expire(await _load(currentId))).isFinished) {
      throw StateError('Resume or end the saved practice attempt first.');
    }
    final profile = await (db.select(
      db.userProfiles,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (profile?.activeCertificationId != 'WSET_L$level') {
      throw StateError('Choose WSET Level $level as your study track first.');
    }
    final mappings = await StudyPlanner(
      db,
      clock: clock,
    ).effectiveMappings('WSET_L$level');
    final currentIds = {
      for (final item in await KnowledgeGraph(db, clock: clock).currentItems())
        item.id,
    };
    bool linked(Iterable<String> ids) =>
        ids.every((id) => mappings.containsKey(id) && currentIds.contains(id));
    final eligibleMcqs = bank.mcqs
        .where((q) => q.levels.contains(level) && linked(q.itemIds))
        .toList();
    final written =
        bank.written
            .where((q) => q.levels.contains(level) && linked(q.itemIds))
            .toList()
          ..shuffle(random);
    final preset = bank.presets.singleWhere((p) => p.level == level);
    final mcqs = <RehearsalMcq>[];
    if (preset.blueprint.isEmpty) {
      eligibleMcqs.shuffle(random);
      mcqs.addAll(eligibleMcqs.take(preset.mcqCount));
    } else {
      for (final bucket in preset.blueprint.entries) {
        final pool =
            eligibleMcqs
                .where((q) => q.blueprintByLevel['$level'] == bucket.key)
                .toList()
              ..shuffle(random);
        if (pool.length < bucket.value) {
          throw StateError(
            'Not enough current questions for the ${bucket.key} practice topic.',
          );
        }
        mcqs.addAll(pool.take(bucket.value));
      }
      mcqs.shuffle(random);
    }
    if (mcqs.length < preset.mcqCount || written.length < preset.writtenCount) {
      throw StateError(
        'This track does not yet have enough current practice questions for the full preset.',
      );
    }
    final started = utcNow(clock);
    var id = newUuid(random);
    while (await _setting(_attemptKey(id)) != null) {
      id = newUuid(random);
    }
    final attempt = RehearsalAttempt.fromJson({
      'schemaVersion': 1,
      'id': id,
      'level': level,
      'bankVersion': bank.version,
      'startedAt': started.toIso8601String(),
      'deadline': started
          .add(Duration(seconds: preset.durationSeconds))
          .toIso8601String(),
      'completedAt': null,
      'finishReason': null,
      'mcqs': [
        for (final q in mcqs.take(preset.mcqCount))
          {
            ...q.toJson(),
            'options': ([
              for (final o in q.options) {'id': o.id, 'text': o.text},
            ]..shuffle(random)),
          },
      ],
      'written': [
        for (final q in written.take(preset.writtenCount)) q.toJson(),
      ],
      'answers': <String, String>{},
      'prose': <String, String>{},
      'selfAssessment': <String, List<String>>{},
    });
    await _save(attempt);
    await _put(currentKey, attempt.id);
    return attempt;
  });

  Future<RehearsalAttempt> _change(
    String id,
    void Function(Map<String, dynamic> row) mutate, {
    bool afterFinish = false,
  }) async {
    // Commit a deadline-triggered completion before reporting a rejected
    // late answer. Throwing inside the transaction would undo the expiry.
    final result = await db.transaction(() async {
      final attempt = await _expire(await _load(id));
      if (afterFinish
          ? !attempt.isFinished || attempt.abandoned
          : attempt.isFinished) {
        return (attempt: attempt, allowed: false);
      }
      final row = attempt.toJson();
      // Detach mutable answers from the snapshot returned to callers.
      final detached = jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
      mutate(detached);
      final changed = RehearsalAttempt.fromJson(detached);
      await _save(changed);
      return (attempt: changed, allowed: true);
    });
    if (!result.allowed) {
      throw StateError(
        afterFinish
            ? 'Finish the practice before checking your written criteria.'
            : 'This practice attempt has ended.',
      );
    }
    return result.attempt;
  }

  Future<RehearsalAttempt> answerMcq(
    String id,
    String questionId,
    String optionId,
  ) => _change(id, (row) {
    (row['answers'] as Map)[questionId] = optionId;
  });
  Future<RehearsalAttempt> answerWritten(
    String id,
    String questionId,
    String text,
  ) {
    if (text.length > 20000) throw ArgumentError('Written answer is too long.');
    return _change(id, (row) {
      (row['prose'] as Map)[questionId] = text;
    });
  }

  Future<RehearsalAttempt> selfAssess(
    String id,
    String questionId,
    Set<String> criteria,
  ) => _change(id, (row) {
    (row['selfAssessment'] as Map)[questionId] = criteria.toList();
  }, afterFinish: true);
  Future<RehearsalAttempt> finish(String id) => db.transaction(() async {
    var attempt = await _expire(await _load(id));
    if (!attempt.isFinished) {
      attempt = _finished(attempt, 'submitted');
      await _save(attempt);
    }
    return attempt;
  });
  Future<List<RehearsalAttempt>> history() async =>
      (await historyWithDiagnostics()).entries;

  Future<({List<RehearsalAttempt> entries, int unreadableCount})>
  historyWithDiagnostics() => db.transaction(() async {
    final rows = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$attemptPrefix%'))).get();
    final attempts = <RehearsalAttempt>[];
    var unreadableCount = 0;
    for (final row in rows) {
      if (!row.name.startsWith(attemptPrefix)) continue;
      RehearsalAttempt attempt;
      try {
        attempt = RehearsalAttempt.fromJson(
          jsonDecode(row.value) as Map<String, dynamic>,
        );
        if (_attemptKey(attempt.id) != row.name) {
          throw const FormatException(
            'Saved practice history identity does not match its key',
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
      // Storage failures must propagate, rather than being called corrupt data.
      attempts.add(await _expire(attempt));
    }
    attempts.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (entries: attempts, unreadableCount: unreadableCount);
  });

  Future<void> discardCurrent({String? expectedId}) => db.transaction(() async {
    final id = await _setting(currentKey);
    if (expectedId != null && id != expectedId) {
      throw StateError(
        'The selected practice attempt has changed. Reopen it first.',
      );
    }
    if (id != null) {
      final attempt = await _expire(await _load(id));
      if (!attempt.isFinished) await _save(_finished(attempt, 'abandoned'));
    }
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.equals(currentKey))).go();
  });

  /// Leave completed feedback without ending a different selected draft.
  Future<RehearsalAttempt?> leaveFinished(String id) =>
      db.transaction(() async {
        if (!(await _expire(await _load(id))).isFinished) {
          throw StateError('Finish or end this practice attempt first.');
        }
        final currentId = await _setting(currentKey);
        if (currentId == id) {
          await (db.delete(
            db.userSettings,
          )..where((s) => s.name.equals(currentKey))).go();
          return null;
        }
        return currentId == null ? null : _expire(await _load(currentId));
      });

  /// Recover the current selection without deleting saved history or backups.
  Future<void> resetCurrentPointer() async {
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.equals(currentKey))).go();
  }
}
