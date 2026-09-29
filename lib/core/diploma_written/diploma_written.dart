import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../time/utc_clock.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _id = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
const _maxProse = 20000;
const _maxReview = 4000;
const _maxSnapshot = 160000;

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

DateTime _savedUtc(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid written-practice time.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('Written-practice time must be canonical UTC.');
  }
  return parsed;
}

int _seconds(String unitId) => switch (unitId) {
  'D1' => 5400,
  'D2' => 3600,
  _ => throw ArgumentError.value(unitId, 'unitId'),
};

class DiplomaWrittenCriterion {
  DiplomaWrittenCriterion.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      text = row['text'] as String {
    if (!_id.hasMatch(id) || text.trim().isEmpty || text.length > 500) {
      throw const FormatException('Invalid written-practice criterion.');
    }
  }

  final String id;
  final String text;
  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

class DiplomaWrittenQuestion {
  DiplomaWrittenQuestion.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      prompt = row['prompt'] as String,
      criteria = [
        for (final value in row['criteria'] as List)
          DiplomaWrittenCriterion.fromJson(_map(value)),
      ] {
    if (!_id.hasMatch(id) ||
        prompt.trim().isEmpty ||
        prompt.length > 1000 ||
        criteria.length != 4 ||
        criteria.map((c) => c.id).toSet().length != 4) {
      throw const FormatException('Invalid written-practice question.');
    }
  }

  final String id;
  final String prompt;
  final List<DiplomaWrittenCriterion> criteria;
  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'criteria': [for (final criterion in criteria) criterion.toJson()],
  };
}

class DiplomaWrittenPreset {
  DiplomaWrittenPreset.fromJson(Map<String, dynamic> row)
    : unitId = row['unitId'] as String,
      title = row['title'] as String,
      durationSeconds = row['durationSeconds'] as int,
      questions = [
        for (final value in row['questions'] as List)
          DiplomaWrittenQuestion.fromJson(_map(value)),
      ] {
    if (!const {'D1', 'D2'}.contains(unitId) ||
        title.trim().isEmpty ||
        title.length > 100 ||
        durationSeconds != _seconds(unitId) ||
        questions.length != 3 ||
        questions.map((q) => q.id).toSet().length != 3) {
      throw const FormatException('Invalid Diploma written preset.');
    }
  }

  final String unitId;
  final String title;
  final int durationSeconds;
  final List<DiplomaWrittenQuestion> questions;
}

class DiplomaWrittenBank {
  DiplomaWrittenBank.fromJson(String text) {
    final row = _map(jsonDecode(text));
    if (row['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Diploma written bank.');
    }
    version = row['version'] as String;
    presets = [
      for (final value in row['units'] as List)
        DiplomaWrittenPreset.fromJson(_map(value)),
    ];
    if (version.trim().isEmpty ||
        version.length > 40 ||
        presets.length != 2 ||
        presets.map((p) => p.unitId).toSet().length != 2) {
      throw const FormatException('Invalid Diploma written bank.');
    }
  }

  late final String version;
  late final List<DiplomaWrittenPreset> presets;
  DiplomaWrittenPreset preset(String unitId) => presets.singleWhere(
    (preset) => preset.unitId == unitId,
    orElse: () => throw ArgumentError.value(unitId, 'unitId'),
  );
}

class DiplomaWrittenReview {
  DiplomaWrittenReview.fromJson(Map<String, dynamic> row)
    : selectedCriteria = Set<String>.from(row['selectedCriteria'] as List),
      improvement = row['improvement'] as String,
      reviewedAt = _savedUtc(row['reviewedAt']) {
    if ((row['selectedCriteria'] as List).length != selectedCriteria.length ||
        improvement.trim().isEmpty ||
        improvement.length > _maxReview) {
      throw const FormatException('Invalid written self-review.');
    }
  }

  final Set<String> selectedCriteria;
  final String improvement;
  final DateTime reviewedAt;
  Map<String, dynamic> toJson() => {
    'selectedCriteria': selectedCriteria.toList()..sort(),
    'improvement': improvement,
    'reviewedAt': reviewedAt.toIso8601String(),
  };
}

/// Saved prose and learner-led review; never an examiner mark or qualification.
class DiplomaWrittenAttempt {
  DiplomaWrittenAttempt.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      unitId = row['unitId'] as String,
      bankVersion = row['bankVersion'] as String,
      startedAt = _savedUtc(row['startedAt']),
      deadline = _savedUtc(row['deadline']),
      completedAt = row['completedAt'] == null
          ? null
          : _savedUtc(row['completedAt']),
      finishReason = row['finishReason'] as String?,
      questions = [
        for (final value in row['questions'] as List)
          DiplomaWrittenQuestion.fromJson(_map(value)),
      ],
      prose = Map<String, String>.from(row['prose'] as Map),
      reviews = {
        for (final entry in (row['reviews'] as Map).entries)
          entry.key as String: DiplomaWrittenReview.fromJson(_map(entry.value)),
      } {
    if (row['schemaVersion'] != 1 ||
        !_uuid.hasMatch(id) ||
        !const {'D1', 'D2'}.contains(unitId) ||
        bankVersion.trim().isEmpty ||
        bankVersion.length > 40 ||
        questions.length != 3 ||
        questions.map((q) => q.id).toSet().length != 3 ||
        deadline.difference(startedAt) != Duration(seconds: _seconds(unitId)) ||
        (completedAt == null) != (finishReason == null) ||
        (completedAt != null &&
            (completedAt!.isBefore(startedAt) ||
                completedAt!.isAfter(deadline) ||
                !const {
                  'submitted',
                  'expired',
                  'abandoned',
                }.contains(finishReason))) ||
        (finishReason == 'expired' && completedAt != deadline) ||
        prose.entries.any(
          (entry) =>
              !questions.any((q) => q.id == entry.key) ||
              entry.value.length > _maxProse,
        ) ||
        reviews.entries.any((entry) {
          final question = questions
              .where((q) => q.id == entry.key)
              .firstOrNull;
          return question == null ||
              completedAt == null ||
              finishReason == 'abandoned' ||
              (prose[entry.key] ?? '').trim().isEmpty ||
              entry.value.reviewedAt.isBefore(completedAt!) ||
              !question.criteria
                  .map((c) => c.id)
                  .toSet()
                  .containsAll(entry.value.selectedCriteria);
        }) ||
        jsonEncode(row).length > _maxSnapshot) {
      throw const FormatException('Invalid saved Diploma written attempt.');
    }
  }

  final String id;
  final String unitId;
  final String bankVersion;
  final DateTime startedAt;
  final DateTime deadline;
  final DateTime? completedAt;
  final String? finishReason;
  final List<DiplomaWrittenQuestion> questions;
  final Map<String, String> prose;
  final Map<String, DiplomaWrittenReview> reviews;

  bool get isFinished => completedAt != null;
  bool get isAbandoned => finishReason == 'abandoned';
  bool get isReviewed =>
      isFinished &&
      !isAbandoned &&
      questions.every(
        (q) => (prose[q.id] ?? '').trim().isNotEmpty && reviews[q.id] != null,
      );
  Duration remaining(DateTime now) {
    if (isFinished) return Duration.zero;
    final elapsed = now.toUtc().isBefore(startedAt) ? startedAt : now.toUtc();
    final left = deadline.difference(elapsed);
    return left.isNegative ? Duration.zero : left;
  }

  void validateAt(DateTime now) {
    final current = toStorageInstant(now);
    if (startedAt.isAfter(current) ||
        (completedAt?.isAfter(current) ?? false) ||
        reviews.values.any((r) => r.reviewedAt.isAfter(current))) {
      throw const FormatException(
        'Diploma written attempt is dated in the future.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'unitId': unitId,
    'bankVersion': bankVersion,
    'startedAt': startedAt.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'finishReason': finishReason,
    'questions': [for (final q in questions) q.toJson()],
    'prose': prose,
    'reviews': {
      for (final entry in reviews.entries) entry.key: entry.value.toJson(),
    },
  };
}

/// Timed original prose practice in backed-up user settings. No FSRS credit.
class DiplomaWrittenRepository {
  DiplomaWrittenRepository(
    this.db, {
    required this.bank,
    Clock? clock,
    Random? random,
  }) : clock = clock ?? const Clock(),
       random = random ?? Random.secure();

  final AppDatabase db;
  final DiplomaWrittenBank bank;
  final Clock clock;
  final Random random;

  static const attemptPrefix = 'diploma_written_attempt_v1_';
  static const currentPrefix = 'diploma_written_current_v1_';
  static String keyFor(String id) => '$attemptPrefix${id.replaceAll('-', '_')}';
  static String currentKey(String unitId) =>
      '$currentPrefix${unitId.toLowerCase()}';

  Future<String?> _setting(String name) async => (await (db.select(
    db.userSettings,
  )..where((row) => row.name.equals(name))).getSingleOrNull())?.value;

  Future<void> _put(String name, String value) => db
      .into(db.userSettings)
      .insertOnConflictUpdate(
        UserSetting(name: name, value: value, updatedAt: utcNow(clock)),
      );

  Future<void> _deleteCurrentIfMatches(String unitId, String id) async {
    final name = currentKey(unitId);
    if (await _setting(name) == id) {
      await (db.delete(
        db.userSettings,
      )..where((row) => row.name.equals(name))).go();
    }
  }

  Future<void> _save(DiplomaWrittenAttempt attempt) =>
      _put(keyFor(attempt.id), jsonEncode(attempt.toJson()));

  Future<DiplomaWrittenAttempt> _load(String id) async {
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid written-practice selection.');
    }
    final value = await _setting(keyFor(id));
    if (value == null) throw StateError('Written practice was not found.');
    final attempt = DiplomaWrittenAttempt.fromJson(_map(jsonDecode(value)));
    if (attempt.id != id) {
      throw const FormatException('Written-practice identity does not match.');
    }
    attempt.validateAt(utcNow(clock));
    return attempt;
  }

  Future<DiplomaWrittenAttempt> _expire(DiplomaWrittenAttempt attempt) async {
    if (attempt.isFinished || utcNow(clock).isBefore(attempt.deadline)) {
      return attempt;
    }
    final row = attempt.toJson();
    row['completedAt'] = attempt.deadline.toIso8601String();
    row['finishReason'] = 'expired';
    final expired = DiplomaWrittenAttempt.fromJson(row);
    await _save(expired);
    await _deleteCurrentIfMatches(attempt.unitId, attempt.id);
    return expired;
  }

  Future<DiplomaWrittenAttempt> read(String id) =>
      db.transaction(() async => _expire(await _load(id)));

  Future<DiplomaWrittenAttempt?> current(String unitId) => db.transaction(
    () async {
      bank.preset(unitId);
      final id = await _setting(currentKey(unitId));
      if (id == null) return null;
      final attempt = await _expire(await _load(id));
      if (attempt.unitId != unitId) {
        throw const FormatException('Written-practice pointer has wrong unit.');
      }
      return attempt.isFinished ? null : attempt;
    },
  );

  Future<DiplomaWrittenAttempt> start(String unitId) =>
      db.transaction(() async {
        final preset = bank.preset(unitId);
        if (await current(unitId) != null) {
          throw StateError('Resume or end the saved $unitId written practice.');
        }
        final profile = await (db.select(
          db.userProfiles,
        )..where((row) => row.id.equals(1))).getSingleOrNull();
        if (profile?.activeCertificationId != 'WSET_L4') {
          throw StateError('Choose WSET Level 4 as your study track first.');
        }
        var id = newUuid(random);
        while (await _setting(keyFor(id)) != null) {
          id = newUuid(random);
        }
        final now = utcNow(clock);
        final attempt = DiplomaWrittenAttempt.fromJson({
          'schemaVersion': 1,
          'id': id,
          'unitId': unitId,
          'bankVersion': bank.version,
          'startedAt': now.toIso8601String(),
          'deadline': now
              .add(Duration(seconds: preset.durationSeconds))
              .toIso8601String(),
          'completedAt': null,
          'finishReason': null,
          'questions': [for (final q in preset.questions) q.toJson()],
          'prose': <String, String>{},
          'reviews': <String, Object>{},
        });
        await _save(attempt);
        await _put(currentKey(unitId), id);
        return attempt;
      });

  Future<DiplomaWrittenAttempt> answer(
    String id,
    String questionId,
    String text,
  ) => db.transaction(() async {
    final attempt = await _expire(await _load(id));
    if (attempt.isFinished) {
      throw StateError('The writing time has ended.');
    }
    if (!attempt.questions.any((q) => q.id == questionId) ||
        text.length > _maxProse) {
      throw const FormatException('Invalid written response.');
    }
    final row = attempt.toJson();
    final prose = _map(row['prose']);
    prose[questionId] = text;
    row['prose'] = prose;
    final changed = DiplomaWrittenAttempt.fromJson(row);
    await _save(changed);
    return changed;
  });

  Future<DiplomaWrittenAttempt> _finish(String id, String reason) =>
      db.transaction(() async {
        final attempt = await _expire(await _load(id));
        if (attempt.isFinished) {
          if (attempt.finishReason == reason ||
              (reason == 'submitted' && attempt.finishReason == 'expired')) {
            return attempt;
          }
          throw StateError('This written practice has already ended.');
        }
        final row = attempt.toJson();
        final now = utcNow(clock);
        row['completedAt'] =
            (now.isBefore(attempt.startedAt) ? attempt.startedAt : now)
                .toIso8601String();
        row['finishReason'] = reason;
        final finished = DiplomaWrittenAttempt.fromJson(row);
        await _save(finished);
        await _deleteCurrentIfMatches(attempt.unitId, id);
        return finished;
      });

  Future<DiplomaWrittenAttempt> finish(String id) => _finish(id, 'submitted');
  Future<DiplomaWrittenAttempt> abandon(String id) => _finish(id, 'abandoned');

  Future<DiplomaWrittenAttempt> review(
    String id,
    String questionId,
    Set<String> selectedCriteria,
    String improvement,
  ) => db.transaction(() async {
    final attempt = await _expire(await _load(id));
    final question = attempt.questions
        .where((q) => q.id == questionId)
        .firstOrNull;
    if (!attempt.isFinished ||
        attempt.isAbandoned ||
        question == null ||
        (attempt.prose[questionId] ?? '').trim().isEmpty) {
      throw StateError('Finish a written response before reviewing it.');
    }
    if (!question.criteria
            .map((c) => c.id)
            .toSet()
            .containsAll(selectedCriteria) ||
        improvement.trim().isEmpty ||
        improvement.length > _maxReview) {
      throw const FormatException('Invalid criterion-led self-review.');
    }
    final row = attempt.toJson();
    final reviews = _map(row['reviews']);
    reviews[questionId] = {
      'selectedCriteria': selectedCriteria.toList()..sort(),
      'improvement': improvement,
      'reviewedAt': utcNow(clock).toIso8601String(),
    };
    row['reviews'] = reviews;
    final changed = DiplomaWrittenAttempt.fromJson(row);
    await _save(changed);
    return changed;
  });

  Future<DiplomaWrittenAttempt> resume(String id) => db.transaction(() async {
    final attempt = await _expire(await _load(id));
    if (!attempt.isFinished) {
      final active = await current(attempt.unitId);
      if (active != null && active.id != id) {
        throw StateError('Resume or end the other saved attempt first.');
      }
      await _put(currentKey(attempt.unitId), id);
    }
    return attempt;
  });

  Future<void> resetCurrentPointer(String unitId) async {
    bank.preset(unitId);
    await (db.delete(
      db.userSettings,
    )..where((row) => row.name.equals(currentKey(unitId)))).go();
  }

  Future<({List<DiplomaWrittenAttempt> entries, int unreadableCount})>
  historyWithDiagnostics(String unitId) async {
    bank.preset(unitId);
    final rows = await (db.select(
      db.userSettings,
    )..where((row) => row.name.like('$attemptPrefix%'))).get();
    final entries = <DiplomaWrittenAttempt>[];
    var unreadable = 0;
    for (final row in rows) {
      try {
        final attempt = DiplomaWrittenAttempt.fromJson(
          _map(jsonDecode(row.value)),
        );
        if (keyFor(attempt.id) != row.name) {
          throw const FormatException('Written-practice key mismatch.');
        }
        attempt.validateAt(utcNow(clock));
        if (attempt.unitId == unitId) entries.add(attempt);
      } catch (_) {
        unreadable++;
      }
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (entries: entries, unreadableCount: unreadable);
  }
}
