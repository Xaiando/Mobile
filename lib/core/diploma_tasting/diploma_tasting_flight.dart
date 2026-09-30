import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;

import '../database/app_database.dart';
import '../database/uuid.dart';
import '../tasting/tasting_practice.dart';
import '../time/utc_clock.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _promptId = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
const _requiredPromptIds = {
  'description',
  'quality',
  'ageing',
  'style_clues',
  'uncertainty',
};

/// Unit kinds are explicit; historical snapshots retain their original prompts.
const diplomaTastingWineKinds = {
  'D3': 'still',
  'D4': 'sparkling',
  'D5': 'fortified',
};
const _maxProse = 4000;
const _maxSnapshotCharacters = 300000;

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

DateTime _savedUtc(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid Diploma tasting timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('Diploma tasting time must be canonical UTC.');
  }
  return parsed;
}

/// Original prompts for real wines, without reference answers or a grade.
class DiplomaTastingPrompt {
  DiplomaTastingPrompt.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      prompt = row['prompt'] as String {
    if (!_promptId.hasMatch(id) ||
        prompt.trim().isEmpty ||
        prompt.length > 500) {
      throw const FormatException('Invalid Diploma tasting prompt.');
    }
  }

  final String id;
  final String prompt;

  Map<String, dynamic> toJson() => {'id': id, 'prompt': prompt};
}

class DiplomaTastingUnit {
  DiplomaTastingUnit.fromJson(Map<String, dynamic> row)
    : unitId = row['unitId'] as String,
      title = row['title'] as String,
      wineKind = row['wineKind'] as String,
      evidencePrompts = [
        for (final value in row['evidencePrompts'] as List)
          DiplomaTastingPrompt.fromJson(_map(value)),
      ],
      comparisonPrompt = row['comparisonPrompt'] as String,
      selfReviewPrompt = row['selfReviewPrompt'] as String {
    if (!diplomaTastingWineKinds.containsKey(unitId) ||
        title.trim().isEmpty ||
        title.length > 100 ||
        wineKind != diplomaTastingWineKinds[unitId] ||
        evidencePrompts.length != _requiredPromptIds.length ||
        evidencePrompts
            .map((p) => p.id)
            .toSet()
            .difference(_requiredPromptIds)
            .isNotEmpty ||
        evidencePrompts.map((p) => p.id).toSet().length !=
            _requiredPromptIds.length ||
        comparisonPrompt.trim().isEmpty ||
        comparisonPrompt.length > 500 ||
        selfReviewPrompt.trim().isEmpty ||
        selfReviewPrompt.length > 500) {
      throw const FormatException('Invalid Diploma tasting unit.');
    }
  }

  final String unitId;
  final String title;
  final String wineKind;
  final List<DiplomaTastingPrompt> evidencePrompts;
  final String comparisonPrompt;
  final String selfReviewPrompt;
}

class DiplomaTastingBank {
  DiplomaTastingBank.fromJson(String text) {
    final row = _map(jsonDecode(text));
    if (row['schemaVersion'] != 1 || row['gridId'] != 'tg_structured') {
      throw const FormatException('Unsupported Diploma tasting prompt bank.');
    }
    version = row['version'] as String;
    gridId = row['gridId'] as String;
    units = [
      for (final unit in row['units'] as List)
        DiplomaTastingUnit.fromJson(_map(unit)),
    ];
    final ids = units.map((unit) => unit.unitId).toSet();
    final legacyUnits = ids.length == 2 && ids.containsAll({'D4', 'D5'});
    final currentUnits =
        ids.length == 3 && ids.containsAll(diplomaTastingWineKinds.keys);
    if (version.trim().isEmpty ||
        version.length > 40 ||
        ids.length != units.length ||
        (!legacyUnits && !currentUnits)) {
      throw const FormatException('Invalid Diploma tasting prompt bank.');
    }
  }

  late final String version;
  late final String gridId;
  late final List<DiplomaTastingUnit> units;

  DiplomaTastingUnit unit(String id) => units.singleWhere(
    (unit) => unit.unitId == id,
    orElse: () => throw ArgumentError.value(id, 'unitId'),
  );
}

typedef DiplomaObservationValue = ({String key, String label});

/// A saved vocabulary snapshot, so later grid edits cannot rewrite practice.
class DiplomaObservationAttribute {
  DiplomaObservationAttribute.fromJson(Map<String, dynamic> row)
    : key = row['key'] as String,
      label = row['label'] as String,
      section = row['section'] as String,
      isRequired = row['isRequired'] as bool,
      isSingle = row['isSingle'] as bool,
      values = [
        for (final value in row['values'] as List)
          (
            key: _map(value)['key'] as String,
            label: _map(value)['label'] as String,
          ),
      ] {
    if (!_promptId.hasMatch(key) ||
        label.trim().isEmpty ||
        label.length > 200 ||
        section.trim().isEmpty ||
        section.length > 100 ||
        values.isEmpty ||
        values.length > 64 ||
        values.map((value) => value.key).toSet().length != values.length ||
        values.any(
          (value) =>
              !_promptId.hasMatch(value.key) ||
              value.label.trim().isEmpty ||
              value.label.length > 200,
        )) {
      throw const FormatException('Invalid saved tasting grid attribute.');
    }
  }

  final String key;
  final String label;
  final String section;
  final bool isRequired;
  final bool isSingle;
  final List<DiplomaObservationValue> values;

  static DiplomaObservationAttribute fromGrid(GridAttribute attribute) =>
      DiplomaObservationAttribute.fromJson({
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
}

class DiplomaTastingWine {
  DiplomaTastingWine.fromJson(Map<String, dynamic> row)
    : physicallyTasted = row['physicallyTasted'] as bool,
      attributes = [
        for (final value in row['attributes'] as List)
          DiplomaObservationAttribute.fromJson(_map(value)),
      ],
      prompts = [
        for (final value in row['prompts'] as List)
          DiplomaTastingPrompt.fromJson(_map(value)),
      ],
      observations = {
        for (final entry in (row['observations'] as Map).entries)
          entry.key as String: Set<String>.from(entry.value as List),
      },
      evidence = Map<String, String>.from(row['evidence'] as Map) {
    final rawObservations = row['observations'] as Map;
    if (attributes.isEmpty ||
        attributes.length > 64 ||
        attributes.map((a) => a.key).toSet().length != attributes.length ||
        prompts.length != _requiredPromptIds.length ||
        prompts.map((p) => p.id).toSet().length != prompts.length ||
        !prompts.map((p) => p.id).toSet().containsAll(_requiredPromptIds) ||
        evidence.entries.any(
          (entry) =>
              !_requiredPromptIds.contains(entry.key) ||
              entry.value.length > _maxProse,
        ) ||
        rawObservations.values.any(
          (value) => (value as List).toSet().length != value.length,
        ) ||
        observations.entries.any((entry) {
          final matches = attributes.where((a) => a.key == entry.key);
          if (matches.length != 1) return true;
          final attribute = matches.single;
          return (attribute.isSingle && entry.value.length > 1) ||
              entry.value.any(
                (choice) =>
                    !attribute.values.any((value) => value.key == choice),
              );
        })) {
      throw const FormatException('Invalid saved Diploma wine.');
    }
  }

  final bool physicallyTasted;
  final List<DiplomaObservationAttribute> attributes;
  final List<DiplomaTastingPrompt> prompts;
  final Map<String, Set<String>> observations;
  final Map<String, String> evidence;

  List<DiplomaObservationAttribute> get missingObservations => [
    for (final attribute in attributes)
      if (attribute.isRequired &&
          (observations[attribute.key] ?? const <String>{}).isEmpty)
        attribute,
  ];
  List<DiplomaTastingPrompt> get missingEvidence => [
    for (final prompt in prompts)
      if ((evidence[prompt.id] ?? '').trim().isEmpty) prompt,
  ];
  bool get isComplete =>
      physicallyTasted &&
      missingObservations.isEmpty &&
      missingEvidence.isEmpty;

  Map<String, dynamic> toJson() => {
    'physicallyTasted': physicallyTasted,
    'attributes': [for (final attribute in attributes) attribute.toJson()],
    'prompts': [for (final prompt in prompts) prompt.toJson()],
    'observations': {
      for (final entry in observations.entries)
        entry.key: entry.value.toList()..sort(),
    },
    'evidence': evidence,
  };
}

/// A private record of physical practice, never an assessed answer or pass.
class DiplomaTastingFlight {
  DiplomaTastingFlight.fromJson(Map<String, dynamic> row)
    : id = row['id'] as String,
      unitId = row['unitId'] as String,
      bankVersion = row['bankVersion'] as String,
      gridId = row['gridId'] as String,
      startedAt = _savedUtc(row['startedAt']),
      updatedAt = _savedUtc(row['updatedAt']),
      completedAt = row['completedAt'] == null
          ? null
          : _savedUtc(row['completedAt']),
      finishReason = row['finishReason'] as String?,
      wines = [
        for (final value in row['wines'] as List)
          DiplomaTastingWine.fromJson(_map(value)),
      ],
      comparisonPrompt = row['comparisonPrompt'] as String,
      selfReviewPrompt = row['selfReviewPrompt'] as String,
      reflection = row['reflection'] as String,
      selfReview = row['selfReview'] as String,
      selfReviewedAt = row['selfReviewedAt'] == null
          ? null
          : _savedUtc(row['selfReviewedAt']) {
    if (row['schemaVersion'] != 1 ||
        !_uuid.hasMatch(id) ||
        !diplomaTastingWineKinds.containsKey(unitId) ||
        bankVersion.trim().isEmpty ||
        bankVersion.length > 40 ||
        gridId != 'tg_structured' ||
        wines.length != 3 ||
        wines.any(
          (wine) =>
              jsonEncode(wine.attributes.map((a) => a.toJson()).toList()) !=
                  jsonEncode(
                    wines.first.attributes.map((a) => a.toJson()).toList(),
                  ) ||
              jsonEncode(wine.prompts.map((p) => p.toJson()).toList()) !=
                  jsonEncode(
                    wines.first.prompts.map((p) => p.toJson()).toList(),
                  ),
        ) ||
        comparisonPrompt.trim().isEmpty ||
        comparisonPrompt.length > 500 ||
        selfReviewPrompt.trim().isEmpty ||
        selfReviewPrompt.length > 500 ||
        reflection.length > _maxProse ||
        selfReview.length > _maxProse ||
        updatedAt.isBefore(startedAt) ||
        (selfReviewedAt != null &&
            (selfReviewedAt!.isBefore(startedAt) ||
                selfReviewedAt!.isAfter(updatedAt))) ||
        (completedAt == null) != (finishReason == null) ||
        (completedAt != null &&
            (completedAt != updatedAt ||
                !const {'submitted', 'abandoned'}.contains(finishReason))) ||
        (finishReason == 'submitted' && !readyToSubmit) ||
        jsonEncode(row).length > _maxSnapshotCharacters) {
      throw const FormatException('Invalid saved Diploma tasting flight.');
    }
  }

  final String id;
  final String unitId;
  final String bankVersion;
  final String gridId;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? finishReason;
  final List<DiplomaTastingWine> wines;
  final String comparisonPrompt;
  final String selfReviewPrompt;
  final String reflection;
  final String selfReview;
  final DateTime? selfReviewedAt;

  String get wineKind => diplomaTastingWineKinds[unitId]!;
  bool get isFinished => completedAt != null;
  bool get isSubmitted => finishReason == 'submitted';
  int get completeWineCount => wines.where((wine) => wine.isComplete).length;
  bool get readyToReview =>
      completeWineCount == 3 &&
      reflection.trim().isNotEmpty &&
      selfReview.trim().isNotEmpty;
  bool get readyToSubmit => readyToReview && selfReviewedAt != null;

  void validateAt(DateTime now) {
    final current = toStorageInstant(now);
    if (startedAt.isAfter(current) ||
        updatedAt.isAfter(current) ||
        (completedAt?.isAfter(current) ?? false) ||
        (selfReviewedAt?.isAfter(current) ?? false)) {
      throw const FormatException('Diploma tasting time is in the future.');
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'unitId': unitId,
    'bankVersion': bankVersion,
    'gridId': gridId,
    'startedAt': startedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'finishReason': finishReason,
    'wines': [for (final wine in wines) wine.toJson()],
    'comparisonPrompt': comparisonPrompt,
    'selfReviewPrompt': selfReviewPrompt,
    'reflection': reflection,
    'selfReview': selfReview,
    'selfReviewedAt': selfReviewedAt?.toIso8601String(),
  };
}

/// Three untimed real-wine observations, isolated from Levels 1–3 tastings.
class DiplomaTastingFlightRepository {
  DiplomaTastingFlightRepository(
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

  static const flightPrefix = 'diploma_tasting_flight_v1_';
  static const currentPrefix = 'diploma_tasting_current_v1_';
  static String keyFor(String id) => '$flightPrefix${id.replaceAll('-', '_')}';
  static String currentKey(String unitId) =>
      '$currentPrefix${unitId.toLowerCase()}';

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

  Future<void> _delete(String name) =>
      (db.delete(db.userSettings)..where((s) => s.name.equals(name))).go();

  /// Closing a historical flight must not orphan a newer active flight after
  /// the learner repaired a stale current pointer.
  Future<void> _deleteCurrentIfMatches(String unitId, String id) async {
    final name = currentKey(unitId);
    if (await _setting(name) == id) {
      await _delete(name);
    }
  }

  Future<void> _save(DiplomaTastingFlight flight) =>
      _put(keyFor(flight.id), jsonEncode(flight.toJson()));

  Future<DiplomaTastingFlight> _load(String id) async {
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid Diploma tasting selection.');
    }
    final text = await _setting(keyFor(id));
    if (text == null) throw StateError('Saved Diploma tasting was not found.');
    final flight = DiplomaTastingFlight.fromJson(_map(jsonDecode(text)));
    if (flight.id != id) {
      throw const FormatException('Diploma tasting identity does not match.');
    }
    flight.validateAt(utcNow(clock));
    return flight;
  }

  Future<DiplomaTastingFlight> read(String id) => _load(id);

  Future<DiplomaTastingFlight?> current(String unitId) async {
    bank.unit(unitId);
    final id = await _setting(currentKey(unitId));
    if (id == null) return null;
    final flight = await _load(id);
    if (flight.unitId != unitId) {
      throw const FormatException('Diploma tasting pointer has wrong unit.');
    }
    return flight.isFinished ? null : flight;
  }

  Future<DiplomaTastingFlight> start(String unitId) => db.transaction(() async {
    final unit = bank.unit(unitId);
    if (await current(unitId) case final active?) {
      throw StateError('Resume or abandon the saved ${active.unitId} flight.');
    }
    final profile = await (db.select(
      db.userProfiles,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (profile?.activeCertificationId != 'WSET_L4') {
      throw StateError('Choose WSET Level 4 as your study track first.');
    }
    final grid = await TastingPractice(db).layout(bank.gridId);
    if (grid.attributes.isEmpty) {
      throw StateError('The structured tasting grid is unavailable.');
    }
    var id = newUuid(random);
    while (await _setting(keyFor(id)) != null) {
      id = newUuid(random);
    }
    final now = utcNow(clock);
    final attributes = [
      for (final attribute in grid.attributes)
        DiplomaObservationAttribute.fromGrid(attribute).toJson(),
    ];
    final prompts = [
      for (final prompt in unit.evidencePrompts) prompt.toJson(),
    ];
    final flight = DiplomaTastingFlight.fromJson({
      'schemaVersion': 1,
      'id': id,
      'unitId': unitId,
      'bankVersion': bank.version,
      'gridId': bank.gridId,
      'startedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'completedAt': null,
      'finishReason': null,
      'wines': [
        for (var i = 0; i < 3; i++)
          {
            'physicallyTasted': false,
            'attributes': attributes,
            'prompts': prompts,
            'observations': <String, List<String>>{},
            'evidence': <String, String>{},
          },
      ],
      'comparisonPrompt': unit.comparisonPrompt,
      'selfReviewPrompt': unit.selfReviewPrompt,
      'reflection': '',
      'selfReview': '',
      'selfReviewedAt': null,
    });
    await _save(flight);
    await _put(currentKey(unitId), id);
    return flight;
  });

  Future<DiplomaTastingFlight> resume(String id) => db.transaction(() async {
    final flight = await _load(id);
    if (flight.isFinished) return flight;
    final active = await current(flight.unitId);
    if (active != null && active.id != id) {
      throw StateError('Resume or abandon the other saved flight first.');
    }
    await _put(currentKey(flight.unitId), id);
    return flight;
  });

  Future<DiplomaTastingFlight> _change(
    String id,
    void Function(Map<String, dynamic> row) edit, {
    bool resetReview = true,
  }) => db.transaction(() async {
    final flight = await _load(id);
    if (flight.isFinished) {
      throw StateError('This Diploma tasting flight has ended.');
    }
    final row = _map(jsonDecode(jsonEncode(flight.toJson())));
    edit(row);
    if (resetReview) row['selfReviewedAt'] = null;
    final now = utcNow(clock);
    row['updatedAt'] = (now.isBefore(flight.updatedAt) ? flight.updatedAt : now)
        .toIso8601String();
    final changed = DiplomaTastingFlight.fromJson(row);
    changed.validateAt(utcNow(clock));
    await _save(changed);
    return changed;
  });

  static Map<String, dynamic> _wine(Map<String, dynamic> row, int index) {
    if (index < 0 || index >= 3) {
      throw RangeError.range(index, 0, 2, 'wineIndex');
    }
    return _map((row['wines'] as List)[index]);
  }

  Future<DiplomaTastingFlight> acknowledgePhysical(
    String id,
    int wineIndex,
    bool tasted,
  ) => _change(id, (row) {
    (row['wines'] as List)[wineIndex] = _wine(row, wineIndex)
      ..['physicallyTasted'] = tasted;
  });

  Future<DiplomaTastingFlight> choose(
    String id,
    int wineIndex,
    String attributeKey,
    Set<String> values,
  ) => _change(id, (row) {
    final wine = _wine(row, wineIndex);
    final observations = _map(wine['observations']);
    if (values.isEmpty) {
      observations.remove(attributeKey);
    } else {
      observations[attributeKey] = values.toList()..sort();
    }
    wine['observations'] = observations;
    (row['wines'] as List)[wineIndex] = wine;
  });

  Future<DiplomaTastingFlight> saveEvidence(
    String id,
    int wineIndex,
    String promptId,
    String text,
  ) => _change(id, (row) {
    final wine = _wine(row, wineIndex);
    final evidence = _map(wine['evidence']);
    evidence[promptId] = text;
    wine['evidence'] = evidence;
    (row['wines'] as List)[wineIndex] = wine;
  });

  Future<DiplomaTastingFlight> saveReflection(String id, String text) =>
      _change(id, (row) => row['reflection'] = text);

  Future<DiplomaTastingFlight> saveSelfReview(String id, String text) =>
      _change(id, (row) => row['selfReview'] = text);

  Future<DiplomaTastingFlight> markSelfReviewed(String id) =>
      _change(id, (row) {
        final flight = DiplomaTastingFlight.fromJson(row);
        if (!flight.readyToReview) {
          throw StateError(
            'Taste and describe all three wines, then compare and review them.',
          );
        }
        row['selfReviewedAt'] = utcNow(clock).toIso8601String();
      }, resetReview: false);

  Future<DiplomaTastingFlight> finish(String id) => db.transaction(() async {
    final flight = await _load(id);
    if (flight.isFinished) {
      if (flight.isSubmitted) return flight;
      throw StateError('This Diploma tasting flight was abandoned.');
    }
    if (!flight.readyToSubmit) {
      throw StateError(
        'Complete three physical wines, their observations and evidence, '
        'the comparison, and your self-review before recording this flight.',
      );
    }
    final row = flight.toJson();
    final now = utcNow(clock);
    final finishedAt = now.isBefore(flight.updatedAt) ? flight.updatedAt : now;
    row['updatedAt'] = finishedAt.toIso8601String();
    row['completedAt'] = finishedAt.toIso8601String();
    row['finishReason'] = 'submitted';
    final finished = DiplomaTastingFlight.fromJson(row);
    await _save(finished);
    await _deleteCurrentIfMatches(flight.unitId, id);
    return finished;
  });

  Future<DiplomaTastingFlight> abandon(String id) => db.transaction(() async {
    final flight = await _load(id);
    if (flight.isFinished) {
      if (flight.finishReason == 'abandoned') return flight;
      throw StateError('This Diploma tasting flight was already recorded.');
    }
    final row = flight.toJson();
    final now = utcNow(clock);
    final finishedAt = now.isBefore(flight.updatedAt) ? flight.updatedAt : now;
    row['updatedAt'] = finishedAt.toIso8601String();
    row['completedAt'] = finishedAt.toIso8601String();
    row['finishReason'] = 'abandoned';
    final finished = DiplomaTastingFlight.fromJson(row);
    await _save(finished);
    await _deleteCurrentIfMatches(flight.unitId, id);
    return finished;
  });

  /// Repairs only a pointer, leaving every saved flight in history.
  Future<void> resetCurrentPointer(String unitId) async {
    bank.unit(unitId);
    await _delete(currentKey(unitId));
  }

  Future<({List<DiplomaTastingFlight> entries, int unreadableCount})>
  historyWithDiagnostics(String unitId) async {
    bank.unit(unitId);
    final rows = await (db.select(
      db.userSettings,
    )..where((s) => s.name.like('$flightPrefix%'))).get();
    final entries = <DiplomaTastingFlight>[];
    var unreadableCount = 0;
    for (final row in rows) {
      try {
        final flight = DiplomaTastingFlight.fromJson(
          _map(jsonDecode(row.value)),
        );
        if (keyFor(flight.id) != row.name) {
          throw const FormatException('Diploma tasting key mismatch.');
        }
        flight.validateAt(utcNow(clock));
        if (flight.unitId == unitId) entries.add(flight);
      } catch (_) {
        // Parsing only: the database query above remains outside this catch.
        unreadableCount++;
      }
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return (entries: entries, unreadableCount: unreadableCount);
  }
}
