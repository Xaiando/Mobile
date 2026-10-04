import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/uuid.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/core/time/utc_clock.dart';

/// App-authored arrangements; neither is a promised official paper layout.
enum D3TastingPaperKind { grouped, mixed }

const d3TastingPaperDuration = Duration(minutes: 90);
const _maxText = 4000;
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);
DateTime _instant(Object? value) {
  if (value is! String) throw const FormatException('Missing paper timestamp.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.microsecond != 0 ||
      parsed.toIso8601String() != value) {
    throw const FormatException(
      'Paper time must be canonical millisecond UTC.',
    );
  }
  return parsed;
}

class _FrozenAttribute extends DiplomaObservationAttribute {
  _FrozenAttribute.fromJson(super.row)
    : _values = List.unmodifiable([
        for (final v in row['values'] as List)
          (key: _map(v)['key'] as String, label: _map(v)['label'] as String),
      ]),
      super.fromJson();
  final List<DiplomaObservationValue> _values;
  @override
  List<DiplomaObservationValue> get values => _values;
}

class _FrozenWine extends DiplomaTastingWine {
  _FrozenWine.fromJson(super.row)
    : _attributes = List.unmodifiable([
        for (final a in row['attributes'] as List)
          _FrozenAttribute.fromJson(_map(a)),
      ]),
      _prompts = List.unmodifiable([
        for (final p in row['prompts'] as List)
          DiplomaTastingPrompt.fromJson(_map(p)),
      ]),
      _observations = Map.unmodifiable({
        for (final e in (row['observations'] as Map).entries)
          e.key as String: Set<String>.unmodifiable(
            List<String>.from(e.value as List),
          ),
      }),
      _evidence = Map<String, String>.unmodifiable(row['evidence'] as Map),
      super.fromJson();
  final List<DiplomaObservationAttribute> _attributes;
  final List<DiplomaTastingPrompt> _prompts;
  final Map<String, Set<String>> _observations;
  final Map<String, String> _evidence;
  @override
  List<DiplomaObservationAttribute> get attributes => _attributes;
  @override
  List<DiplomaTastingPrompt> get prompts => _prompts;
  @override
  Map<String, Set<String>> get observations => _observations;
  @override
  Map<String, String> get evidence => _evidence;
}

/// Private six-wine timed practice. Completeness is participation, not accuracy.
class D3TastingPaper {
  D3TastingPaper.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      kind = D3TastingPaperKind.values.singleWhere(
        (k) => k.name == row['kind'],
      ),
      bankVersion = row['bankVersion'] as String,
      startedAt = _instant(row['startedAt']),
      deadline = _instant(row['deadline']),
      updatedAt = _instant(row['updatedAt']),
      endedAt = row['endedAt'] == null ? null : _instant(row['endedAt']),
      finishReason = row['finishReason'] as String?,
      wines = List.unmodifiable([
        for (final w in row['wines'] as List) _FrozenWine.fromJson(_map(w)),
      ]),
      comparisonPrompts = List<String>.unmodifiable(
        row['comparisonPrompts'] as List,
      ),
      groupComparisons = List<String>.unmodifiable(
        row['groupComparisons'] as List,
      ),
      selfReviewPrompt = row['selfReviewPrompt'] as String,
      selfReview = row['selfReview'] as String,
      reviewedAt = row['reviewedAt'] == null
          ? null
          : _instant(row['reviewedAt']) {
    final expected = kind == D3TastingPaperKind.grouped ? 2 : 1;
    if (row['schemaVersion'] != 1 ||
        row['unitId'] != 'D3' ||
        row['gridId'] != 'tg_structured' ||
        !_uuid.hasMatch(id) ||
        bankVersion.trim().isEmpty ||
        bankVersion.length > 40 ||
        deadline.difference(startedAt) != d3TastingPaperDuration ||
        updatedAt.isBefore(startedAt) ||
        wines.length != 6 ||
        comparisonPrompts.length != expected ||
        groupComparisons.length != expected ||
        comparisonPrompts.any((p) => p.trim().isEmpty || p.length > 500) ||
        groupComparisons.any((p) => p.length > _maxText) ||
        selfReviewPrompt.trim().isEmpty ||
        selfReviewPrompt.length > 500 ||
        selfReview.length > _maxText ||
        (endedAt == null) != (finishReason == null) ||
        (endedAt != null &&
            (endedAt!.isBefore(startedAt) ||
                endedAt!.isAfter(deadline) ||
                endedAt!.isAfter(updatedAt) ||
                !const {
                  'submitted',
                  'abandoned',
                  'expired',
                }.contains(finishReason))) ||
        (finishReason == 'expired' && endedAt != deadline) ||
        (endedAt == null && !updatedAt.isBefore(deadline)) ||
        (reviewedAt == null && selfReview.isNotEmpty) ||
        (reviewedAt != null &&
            (!readyToReview ||
                selfReview.trim().isEmpty ||
                reviewedAt!.isBefore(endedAt!) ||
                reviewedAt!.isAfter(updatedAt))) ||
        wines.any(
          (w) =>
              jsonEncode(w.attributes.map((a) => a.toJson()).toList()) !=
                  jsonEncode(
                    wines.first.attributes.map((a) => a.toJson()).toList(),
                  ) ||
              jsonEncode(w.prompts.map((p) => p.toJson()).toList()) !=
                  jsonEncode(
                    wines.first.prompts.map((p) => p.toJson()).toList(),
                  ),
        ) ||
        jsonEncode(row).length > 600000) {
      throw const FormatException('Invalid saved D3 tasting paper.');
    }
  }
  final String id;
  final D3TastingPaperKind kind;
  final String bankVersion;
  final DateTime startedAt, deadline, updatedAt;
  final DateTime? endedAt;
  final String? finishReason;
  final List<DiplomaTastingWine> wines;
  final List<String> comparisonPrompts, groupComparisons;
  final String selfReviewPrompt, selfReview;
  final DateTime? reviewedAt;
  String get unitId => 'D3';
  String get gridId => 'tg_structured';
  String get wineKind => 'still';
  bool get isFinished => endedAt != null;
  bool get isAbandoned => finishReason == 'abandoned';
  int get completeWineCount => wines.where((w) => w.isComplete).length;
  bool get readyToReview =>
      isFinished &&
      !isAbandoned &&
      completeWineCount == 6 &&
      groupComparisons.every((v) => v.trim().isNotEmpty);
  bool get isReviewed =>
      readyToReview && reviewedAt != null && selfReview.trim().isNotEmpty;
  Duration remaining(DateTime now) {
    if (isFinished) return Duration.zero;
    final difference = deadline.difference(toStorageInstant(now));
    return difference.isNegative ? Duration.zero : difference;
  }

  void validateAt(DateTime now) {
    final current = toStorageInstant(now);
    if (startedAt.isAfter(current) ||
        updatedAt.isAfter(current) ||
        (endedAt?.isAfter(current) ?? false) ||
        (reviewedAt?.isAfter(current) ?? false)) {
      throw const FormatException('D3 tasting paper time is in the future.');
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'unitId': unitId,
    'gridId': gridId,
    'kind': kind.name,
    'bankVersion': bankVersion,
    'startedAt': startedAt.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'finishReason': finishReason,
    'wines': [for (final w in wines) jsonDecode(jsonEncode(w.toJson()))],
    'comparisonPrompts': comparisonPrompts.toList(),
    'groupComparisons': groupComparisons.toList(),
    'selfReviewPrompt': selfReviewPrompt,
    'selfReview': selfReview,
    'reviewedAt': reviewedAt?.toIso8601String(),
  };
}

typedef _PaperResult = ({D3TastingPaper? paper, Object? error});
D3TastingPaper _result(_PaperResult value) {
  if (value.error != null) throw value.error!;
  return value.paper!;
}

/// One active six-wine paper; stored independently of untimed three-wine flights.
class D3TastingPaperRepository {
  D3TastingPaperRepository(
    this.db, {
    required this.bank,
    Clock? clock,
    Random? random,
  }) : clock = clock ?? const Clock(),
       random = random ?? Random.secure();
  final AppDatabase db;
  final DiplomaTastingBank bank;
  final Clock clock;
  final Random random;
  static const paperPrefix = 'd3_tasting_paper_v1_';
  static const currentSetting = 'd3_tasting_paper_current_v1';
  static String keyFor(String id) => '$paperPrefix${id.replaceAll('-', '_')}';
  Future<void> _gate() async {
    final profile = await (db.select(
      db.userProfiles,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (profile?.activeCertificationId != 'WSET_L4') {
      throw StateError('Choose WSET Level 4 as your study track first.');
    }
  }

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

  Future<void> _deleteCurrentIfMatches(String id) async {
    if (await _setting(currentSetting) == id) {
      await (db.delete(
        db.userSettings,
      )..where((s) => s.name.equals(currentSetting))).go();
    }
  }

  Future<void> _save(D3TastingPaper paper) =>
      _put(keyFor(paper.id), jsonEncode(paper.toJson()));
  Future<D3TastingPaper> _load(String id) async {
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid tasting paper selection.');
    }
    final value = await _setting(keyFor(id));
    if (value == null) throw StateError('Saved tasting paper was not found.');
    final paper = D3TastingPaper.fromJson(_map(jsonDecode(value)));
    if (paper.id != id) {
      throw const FormatException('Tasting paper identity mismatch.');
    }
    paper.validateAt(utcNow(clock));
    return paper;
  }

  Future<D3TastingPaper> _expire(D3TastingPaper paper) async {
    if (paper.isFinished || utcNow(clock).isBefore(paper.deadline)) {
      return paper;
    }
    final row = paper.toJson();
    row['endedAt'] = paper.deadline.toIso8601String();
    row['updatedAt'] = utcNow(clock).toIso8601String();
    row['finishReason'] = 'expired';
    final expired = D3TastingPaper.fromJson(row);
    await _save(expired);
    await _deleteCurrentIfMatches(paper.id);
    return expired;
  }

  Future<D3TastingPaper?> _current() async {
    final id = await _setting(currentSetting);
    if (id == null) return null;
    final paper = await _expire(await _load(id));
    return paper.isFinished ? null : paper;
  }

  Future<D3TastingPaper?> current() => db.transaction(() async {
    await _gate();
    return _current();
  });
  Future<D3TastingPaper> read(String id) => db.transaction(() async {
    await _gate();
    return _expire(await _load(id));
  });
  Future<D3TastingPaper> start(D3TastingPaperKind kind) =>
      db.transaction(() async {
        await _gate();
        final unit = bank.unit('D3');
        if (await _current() != null) {
          throw StateError('Resume or end the saved six-wine paper first.');
        }
        final layout = await TastingPractice(db).layout(bank.gridId);
        if (layout.attributes.isEmpty) {
          throw StateError('The structured tasting grid is unavailable.');
        }
        var id = newUuid(random);
        while (await _setting(keyFor(id)) != null) {
          id = newUuid(random);
        }
        final now = utcNow(clock);
        final comparisonPrompts = kind == D3TastingPaperKind.grouped
            ? [
                'Compare blind wines 1-3. Argue a possible shared grape or origin from your observations, distinguish style and quality, and state a competing explanation. Do not treat a resemblance as proof.',
                'Compare blind wines 4-6 independently. Identify common evidence and differences in structure, development and quality; justify a tentative grape or origin and a limitation.',
              ]
            : [
                'Compare all six blind wines without assuming a shared grape or origin. Explain contrasting styles, quality and ageing evidence; propose cautious identities and the clues that could challenge them.',
              ];
        final paper = D3TastingPaper.fromJson({
          'schemaVersion': 1,
          'id': id,
          'unitId': 'D3',
          'gridId': bank.gridId,
          'kind': kind.name,
          'bankVersion': bank.version,
          'startedAt': now.toIso8601String(),
          'deadline': now.add(d3TastingPaperDuration).toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'endedAt': null,
          'finishReason': null,
          'wines': [
            for (var i = 0; i < 6; i++)
              {
                'physicallyTasted': false,
                'attributes': [
                  for (final a in layout.attributes)
                    DiplomaObservationAttribute.fromGrid(a).toJson(),
                ],
                'prompts': [for (final p in unit.evidencePrompts) p.toJson()],
                'observations': <String, List<String>>{},
                'evidence': <String, String>{},
              },
          ],
          'comparisonPrompts': comparisonPrompts,
          'groupComparisons': [for (final _ in comparisonPrompts) ''],
          'selfReviewPrompt': 'After this paper ends, compare your saved evidence with the actual wine identities and a tutor or peer discussion. Name supported conclusions, errors and a concrete next practice task. This reflection is not an examiner mark.',
          'selfReview': '',
          'reviewedAt': null,
        });
        await _save(paper);
        await _put(currentSetting, id);
        return paper;
      });
  Future<D3TastingPaper> resume(String id) => db.transaction(() async {
    await _gate();
    final paper = await _expire(await _load(id));
    if (paper.isFinished) return paper;
    final active = await _current();
    if (active != null && active.id != id) {
      throw StateError('Another six-wine paper is active.');
    }
    await _put(currentSetting, id);
    return paper;
  });
  Future<D3TastingPaper> _change(
    String id,
    void Function(Map<String, dynamic>) edit,
  ) async => _result(
    await db.transaction<_PaperResult>(() async {
      await _gate();
      final paper = await _expire(await _load(id));
      // An error value leaves the expiry transaction committed before throwing.
      if (paper.isFinished) {
        return (paper: null, error: StateError('The tasting paper has ended.'));
      }
      final admittedAt = utcNow(clock);
      if (!admittedAt.isBefore(paper.deadline)) {
        await _expire(paper);
        return (paper: null, error: StateError('The tasting paper has ended.'));
      }
      final row = paper.toJson();
      edit(row);
      row['updatedAt'] = admittedAt.toIso8601String();
      final changed = D3TastingPaper.fromJson(row);
      changed.validateAt(utcNow(clock));
      await _save(changed);
      return (paper: changed, error: null);
    }),
  );
  static Map<String, dynamic> _wine(Map<String, dynamic> row, int index) {
    if (index < 0 || index >= 6) {
      throw RangeError.range(index, 0, 5, 'wineIndex');
    }
    return _map((row['wines'] as List)[index]);
  }

  Future<D3TastingPaper> answer(
    String id,
    int wineIndex,
    String promptId,
    String text,
  ) => _change(id, (row) {
    final wine = _wine(row, wineIndex);
    final prompts = (wine['prompts'] as List).map((p) => _map(p)['id']);
    if (!prompts.contains(promptId) || text.length > _maxText) {
      throw const FormatException('Invalid wine evidence.');
    }
    wine['evidence'] = _map(wine['evidence'])..[promptId] = text;
    (row['wines'] as List)[wineIndex] = wine;
  });
  Future<D3TastingPaper> observation(
    String id,
    int wineIndex,
    String attributeKey,
    Set<String> values,
  ) => _change(id, (row) {
    final wine = _wine(row, wineIndex);
    if (!(wine['attributes'] as List).any(
      (a) => _map(a)['key'] == attributeKey,
    )) {
      throw const FormatException('Unknown saved observation attribute.');
    }
    final observations = _map(wine['observations']);
    if (values.isEmpty) {
      observations.remove(attributeKey);
    } else {
      observations[attributeKey] = values.toList()..sort();
    }
    wine['observations'] = observations;
    (row['wines'] as List)[wineIndex] = wine;
  });
  Future<D3TastingPaper> markTasted(String id, int wineIndex, bool tasted) =>
      _change(id, (row) {
        (row['wines'] as List)[wineIndex] = _wine(row, wineIndex)
          ..['physicallyTasted'] = tasted;
      });
  Future<D3TastingPaper> comparison(String id, int index, String text) =>
      _change(id, (row) {
        final comparisons = row['groupComparisons'] as List;
        if (index < 0 || index >= comparisons.length) {
          throw RangeError.index(index, comparisons, 'comparisonIndex');
        }
        if (text.length > _maxText) {
          throw const FormatException('Comparison is too long.');
        }
        comparisons[index] = text;
      });
  Future<D3TastingPaper> _finish(String id, String reason) =>
      db.transaction(() async {
        await _gate();
        final paper = await _expire(await _load(id));
        if (paper.isFinished) return paper;
        final now = utcNow(clock);
        if (!now.isBefore(paper.deadline)) return _expire(paper);
        final row = paper.toJson();
        row['endedAt'] = now.toIso8601String();
        row['updatedAt'] = now.toIso8601String();
        row['finishReason'] = reason;
        final ended = D3TastingPaper.fromJson(row);
        await _save(ended);
        await _deleteCurrentIfMatches(id);
        return ended;
      });
  Future<D3TastingPaper> finish(String id) => _finish(id, 'submitted');
  Future<D3TastingPaper> abandon(String id) => _finish(id, 'abandoned');
  Future<D3TastingPaper> review(String id, String text) async => _result(
    await db.transaction<_PaperResult>(() async {
      await _gate();
      final paper = await _expire(await _load(id));
      if (!paper.readyToReview ||
          text.trim().isEmpty ||
          text.length > _maxText) {
        return (
          paper: null,
          error: StateError(
            'End the paper and complete all six physical wines and comparisons before self-review.',
          ),
        );
      }
      final now = utcNow(clock);
      final row = paper.toJson();
      row['selfReview'] = text;
      row['reviewedAt'] = now.toIso8601String();
      row['updatedAt'] = now.toIso8601String();
      final reviewed = D3TastingPaper.fromJson(row);
      reviewed.validateAt(now);
      await _save(reviewed);
      return (paper: reviewed, error: null);
    }),
  );
  Future<void> resetCurrentPointer() => db.transaction(() async {
    await _gate();
    await (db.delete(
      db.userSettings,
    )..where((s) => s.name.equals(currentSetting))).go();
  });
  Future<({List<D3TastingPaper> entries, int unreadableCount})>
  historyWithDiagnostics() async {
    await _gate();
    final rows = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$paperPrefix%'))).get();
    final entries = <D3TastingPaper>[];
    var unreadable = 0;
    for (final row in rows) {
      try {
        final paper = D3TastingPaper.fromJson(_map(jsonDecode(row.value)));
        if (keyFor(paper.id) != row.name) {
          throw const FormatException('Tasting paper key mismatch.');
        }
        paper.validateAt(utcNow(clock));
        entries.add(paper);
      } catch (_) {
        unreadable++;
      }
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (
      entries: List<D3TastingPaper>.unmodifiable(entries),
      unreadableCount: unreadable,
    );
  }
}

/// Reviewed timed papers are separate from three-wine flights and qualifications.
class D3TastingPaperEvidence {
  const D3TastingPaperEvidence({
    this.reviewedGrouped = 0,
    this.reviewedMixed = 0,
    this.unreadableCount = 0,
  });
  final int reviewedGrouped, reviewedMixed, unreadableCount;
  int get totalReviewed => reviewedGrouped + reviewedMixed;
}

class D3TastingPaperEvidenceReader {
  static D3TastingPaperEvidence read(
    Map<String, String> settings, {
    required DateTime now,
  }) {
    var grouped = 0, mixed = 0, unreadable = 0;
    for (final entry in settings.entries) {
      if (!entry.key.startsWith(D3TastingPaperRepository.paperPrefix)) continue;
      try {
        final paper = D3TastingPaper.fromJson(_map(jsonDecode(entry.value)));
        if (D3TastingPaperRepository.keyFor(paper.id) != entry.key) {
          throw const FormatException('Tasting paper key mismatch.');
        }
        paper.validateAt(now);
        if (paper.isReviewed) {
          if (paper.kind == D3TastingPaperKind.grouped) {
            grouped++;
          } else {
            mixed++;
          }
        }
      } catch (_) {
        unreadable++;
      }
    }
    return D3TastingPaperEvidence(
      reviewedGrouped: grouped,
      reviewedMixed: mixed,
      unreadableCount: unreadable,
    );
  }
}
